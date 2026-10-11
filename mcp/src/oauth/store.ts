import { createHash, randomBytes } from 'node:crypto';
import { chmodSync, existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

export const CODE_TTL_MS = 5 * 60_000;
export const REFRESH_TTL_MS = 30 * 24 * 3600_000;
export const MAX_CLIENTS = 50;
const MAX_CODES = 500;
const MAX_REFRESH = 1000;

export interface OAuthClient {
  clientId: string;
  redirectUris: string[];
  clientName?: string;
  createdAt: number;
}

interface AuthCode {
  clientId: string;
  redirectUri: string;
  codeChallenge: string;
  family: string;
  expiresAt: number;
  used: boolean;
}

interface RefreshRecord {
  hash: string;
  family: string;
  clientId: string;
  expiresAt: number;
  status: 'active' | 'used' | 'revoked';
}

export const sha256Hex = (s: string) => createHash('sha256').update(s).digest('hex');
export const randomToken = (bytes = 32) => randomBytes(bytes).toString('base64url');

export class OAuthStore {
  private clients = new Map<string, OAuthClient>();
  private codes = new Map<string, AuthCode>(); // chave: sha256 do código
  private refresh = new Map<string, RefreshRecord>(); // chave: sha256 do token
  private clientsFile: string;
  private refreshFile: string;

  constructor(private dataDir: string, private now: () => Date) {
    this.clientsFile = join(dataDir, 'clients.json');
    this.refreshFile = join(dataDir, 'refresh.json');
    try { mkdirSync(dataDir, { recursive: true }); } catch { /* sem persistência */ }
    for (const c of this.load<OAuthClient>(this.clientsFile)) {
      if (c && typeof c.clientId === 'string' && Array.isArray(c.redirectUris)) this.clients.set(c.clientId, c);
    }
    for (const r of this.load<RefreshRecord>(this.refreshFile)) {
      if (r && typeof r.hash === 'string' && typeof r.family === 'string' && typeof r.clientId === 'string'
        && typeof r.expiresAt === 'number' && ['active', 'used', 'revoked'].includes(r.status)) {
        this.refresh.set(r.hash, r);
      }
    }
    this.pruneRefresh();
  }

  // ---------- persistência ----------
  private load<T>(file: string): T[] {
    try {
      if (!existsSync(file)) return [];
      const data = JSON.parse(readFileSync(file, 'utf8'));
      return Array.isArray(data) ? data : [];
    } catch {
      return []; // ausente/corrompido: começa vazio
    }
  }

  private save(file: string, rows: unknown[]): void {
    try {
      const tmp = `${file}.${process.pid}.tmp`;
      writeFileSync(tmp, JSON.stringify(rows), { mode: 0o600 });
      renameSync(tmp, file);
      try { chmodSync(file, 0o600); } catch { /* ignora */ }
    } catch {
      console.error(`falha ao gravar ${file}`); // sem conteúdo
    }
  }

  private saveClients(): void { this.save(this.clientsFile, [...this.clients.values()]); }
  private saveRefresh(): void { this.save(this.refreshFile, [...this.refresh.values()]); }

  // ---------- clientes ----------
  /** null = limite de clientes atingido. */
  registerClient(redirectUris: string[], clientName?: string): OAuthClient | null {
    if (this.clients.size >= MAX_CLIENTS) {
      // Libera espaço removendo o cliente mais antigo que não tem refresh token ativo.
      const inUse = new Set([...this.refresh.values()].filter((r) => r.status === 'active').map((r) => r.clientId));
      const victim = [...this.clients.values()].filter((c) => !inUse.has(c.clientId)).sort((a, b) => a.createdAt - b.createdAt)[0];
      if (!victim) return null;
      this.clients.delete(victim.clientId);
    }
    const client: OAuthClient = { clientId: randomToken(24), redirectUris, clientName, createdAt: this.now().getTime() };
    this.clients.set(client.clientId, client);
    this.saveClients();
    return client;
  }

  getClient(id: string): OAuthClient | undefined {
    return this.clients.get(id);
  }

  // ---------- códigos de autorização ----------
  issueCode(clientId: string, redirectUri: string, codeChallenge: string): string {
    const t = this.now().getTime();
    for (const [k, v] of this.codes) if (v.expiresAt + CODE_TTL_MS < t) this.codes.delete(k);
    while (this.codes.size >= MAX_CODES) this.codes.delete(this.codes.keys().next().value as string);
    const code = randomToken(32);
    this.codes.set(sha256Hex(code), {
      clientId, redirectUri, codeChallenge, family: randomToken(16), expiresAt: t + CODE_TTL_MS, used: false,
    });
    return code;
  }

  /**
   * Consome o código (uso único). Reuso de um código já trocado revoga os refresh tokens
   * emitidos por ele. Retorna null se inexistente, expirado ou já usado.
   */
  takeCode(code: string): (Omit<AuthCode, 'used'> & { family: string }) | null {
    const key = sha256Hex(code);
    const entry = this.codes.get(key);
    if (!entry) return null;
    if (entry.used) {
      this.revokeFamily(entry.family);
      return null;
    }
    entry.used = true; // fica registrado até expirar, para detectar reuso
    if (entry.expiresAt <= this.now().getTime()) return null;
    return entry;
  }

  // ---------- refresh tokens ----------
  issueRefresh(family: string, clientId: string): string {
    const token = randomToken(32);
    const hash = sha256Hex(token);
    this.refresh.set(hash, { hash, family, clientId, expiresAt: this.now().getTime() + REFRESH_TTL_MS, status: 'active' });
    this.pruneRefresh();
    this.saveRefresh();
    return token;
  }

  /**
   * Troca um refresh token: devolve a família para emitir o próximo, marcando o antigo como usado.
   * Reuso de um token já trocado (ou revogado) revoga a família inteira. null = inválido.
   */
  rotateRefresh(token: string, clientId: string): string | null {
    const rec = this.refresh.get(sha256Hex(token));
    if (!rec || rec.clientId !== clientId) return null;
    if (rec.status === 'used') {
      this.revokeFamily(rec.family);
      return null;
    }
    if (rec.status === 'revoked' || rec.expiresAt <= this.now().getTime()) return null;
    rec.status = 'used';
    this.saveRefresh();
    return rec.family;
  }

  /** RFC 7009: revoga a família do token informado (se existir). */
  revokeToken(token: string): void {
    const rec = this.refresh.get(sha256Hex(token));
    if (rec) this.revokeFamily(rec.family);
  }

  revokeFamily(family: string): void {
    let changed = false;
    for (const r of this.refresh.values()) {
      if (r.family === family && r.status !== 'revoked') { r.status = 'revoked'; changed = true; }
    }
    if (changed) this.saveRefresh();
  }

  private pruneRefresh(): void {
    const t = this.now().getTime();
    for (const [k, r] of this.refresh) if (r.expiresAt <= t) this.refresh.delete(k);
    if (this.refresh.size > MAX_REFRESH) {
      const drop = [...this.refresh.values()].filter((r) => r.status !== 'active').sort((a, b) => a.expiresAt - b.expiresAt);
      for (const r of drop) {
        if (this.refresh.size <= MAX_REFRESH) break;
        this.refresh.delete(r.hash);
      }
    }
  }
}
