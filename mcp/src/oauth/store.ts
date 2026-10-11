import { createHash, randomBytes } from 'node:crypto';
import { chmodSync, existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

export const CODE_TTL_MS = 5 * 60_000;
export const REFRESH_TTL_MS = 30 * 24 * 3600_000;
export const MAX_CLIENTS = 50;
/** Cliente registrado há menos que isso nunca é despejado para dar lugar a outro. */
export const CLIENT_PROTECT_MS = 10 * 60_000;
/** Famílias revogadas ficam na lista de bloqueio por 1 h (vida máxima de um access token). */
export const REVOKED_TTL_MS = 3600_000;
const MAX_REVOKED = 200;
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
  /** Fim absoluto da família de refresh tokens (30 dias após a emissão do código). */
  familyExpiresAt: number;
  expiresAt: number;
  used: boolean;
}

interface RefreshRecord {
  hash: string;
  family: string;
  clientId: string;
  expiresAt: number;
  /** Teto absoluto da família: a rotação não o estende. */
  familyExpiresAt: number;
  /** "Geração" (hash de senha + segredo) vigente na emissão; se mudar, o token deixa de valer. */
  gen: string;
  status: 'active' | 'used' | 'revoked';
}

interface RevokedFamily {
  family: string;
  until: number;
}

export const sha256Hex = (s: string) => createHash('sha256').update(s).digest('hex');
export const randomToken = (bytes = 32) => randomBytes(bytes).toString('base64url');

export class OAuthStore {
  private clients = new Map<string, OAuthClient>();
  private codes = new Map<string, AuthCode>(); // chave: sha256 do código
  private refresh = new Map<string, RefreshRecord>(); // chave: sha256 do token
  private revoked = new Map<string, number>(); // familyId -> expira (ms)
  private clientsFile: string;
  private refreshFile: string;
  private revokedFile: string;

  /** `generation`: veja `generation()` em tokens.ts; tokens de outra geração são inválidos. */
  constructor(private dataDir: string, private now: () => Date, private generation: string) {
    this.clientsFile = join(dataDir, 'clients.json');
    this.refreshFile = join(dataDir, 'refresh.json');
    this.revokedFile = join(dataDir, 'revoked.json');
    try { mkdirSync(dataDir, { recursive: true }); } catch { /* sem persistência */ }
    for (const c of this.load<OAuthClient>(this.clientsFile)) {
      if (c && typeof c.clientId === 'string' && Array.isArray(c.redirectUris)) this.clients.set(c.clientId, c);
    }
    for (const r of this.load<RefreshRecord>(this.refreshFile)) {
      if (r && typeof r.hash === 'string' && typeof r.family === 'string' && typeof r.clientId === 'string'
        && typeof r.expiresAt === 'number' && typeof r.familyExpiresAt === 'number' && typeof r.gen === 'string'
        && ['active', 'used', 'revoked'].includes(r.status)) {
        this.refresh.set(r.hash, r);
      }
    }
    for (const v of this.load<RevokedFamily>(this.revokedFile)) {
      if (v && typeof v.family === 'string' && typeof v.until === 'number') this.revoked.set(v.family, v.until);
    }
    this.pruneRefresh();
    this.pruneRevoked();
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
  private saveRevoked(): void {
    this.save(this.revokedFile, [...this.revoked.entries()].map(([family, until]) => ({ family, until })));
  }

  // ---------- clientes ----------
  /** null = limite de clientes atingido (e nenhum pode ser despejado). */
  registerClient(redirectUris: string[], clientName?: string): OAuthClient | null {
    const t = this.now().getTime();
    if (this.clients.size >= MAX_CLIENTS) {
      // Libera espaço removendo o cliente mais antigo que não tem refresh token ativo e que não
      // foi registrado nos últimos 10 min (quem acabou de registrar não pode ser derrubado por spam).
      const inUse = new Set([...this.refresh.values()].filter((r) => r.status === 'active').map((r) => r.clientId));
      const victim = [...this.clients.values()]
        .filter((c) => !inUse.has(c.clientId) && t - c.createdAt >= CLIENT_PROTECT_MS)
        .sort((a, b) => a.createdAt - b.createdAt)[0];
      if (!victim) return null;
      this.clients.delete(victim.clientId);
    }
    const client: OAuthClient = { clientId: randomToken(24), redirectUris, clientName, createdAt: t };
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
      clientId, redirectUri, codeChallenge, family: randomToken(16), familyExpiresAt: t + REFRESH_TTL_MS,
      expiresAt: t + CODE_TTL_MS, used: false,
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
  /** `familyExpiresAt` é o teto absoluto da família; o token nunca vale além dele. */
  issueRefresh(family: string, clientId: string, familyExpiresAt: number): string {
    const token = randomToken(32);
    const hash = sha256Hex(token);
    const expiresAt = Math.min(this.now().getTime() + REFRESH_TTL_MS, familyExpiresAt);
    this.refresh.set(hash, { hash, family, clientId, expiresAt, familyExpiresAt, gen: this.generation, status: 'active' });
    this.pruneRefresh();
    this.saveRefresh();
    return token;
  }

  /**
   * Troca um refresh token: devolve a família (e o teto absoluto dela) para emitir o próximo, marcando o
   * antigo como usado. Reuso de um token já trocado (ou revogado) revoga a família inteira.
   * Token de outra geração (senha/segredo trocados) ou de família vencida => null.
   */
  rotateRefresh(token: string, clientId: string): { family: string; familyExpiresAt: number } | null {
    const rec = this.refresh.get(sha256Hex(token));
    if (!rec || rec.clientId !== clientId) return null;
    if (rec.gen !== this.generation) return null;
    if (rec.status === 'used') {
      this.revokeFamily(rec.family);
      return null;
    }
    const t = this.now().getTime();
    if (rec.status === 'revoked' || rec.expiresAt <= t || rec.familyExpiresAt <= t) return null;
    rec.status = 'used';
    this.saveRefresh();
    return { family: rec.family, familyExpiresAt: rec.familyExpiresAt };
  }

  /** RFC 7009: revoga a família do token informado (se existir). */
  revokeToken(token: string): void {
    const rec = this.refresh.get(sha256Hex(token));
    if (rec) this.revokeFamily(rec.family);
  }

  /** Revoga os refresh tokens da família e bloqueia por 1 h os access tokens dela (`fid`). */
  revokeFamily(family: string): void {
    let changed = false;
    for (const r of this.refresh.values()) {
      if (r.family === family && r.status !== 'revoked') { r.status = 'revoked'; changed = true; }
    }
    if (changed) this.saveRefresh();
    this.pruneRevoked();
    this.revoked.set(family, this.now().getTime() + REVOKED_TTL_MS);
    while (this.revoked.size > MAX_REVOKED) this.revoked.delete(this.revoked.keys().next().value as string);
    this.saveRevoked();
  }

  /** true se a família (claim `fid` do access token) foi revogada na última hora. */
  isFamilyRevoked(family: string): boolean {
    const until = this.revoked.get(family);
    return until !== undefined && until > this.now().getTime();
  }

  private pruneRevoked(): void {
    const t = this.now().getTime();
    for (const [k, until] of this.revoked) if (until <= t) this.revoked.delete(k);
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
