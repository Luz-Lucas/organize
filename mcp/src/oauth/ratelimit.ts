import { isIP } from 'node:net';

/**
 * Chave de limite por cliente: IPv4 como está; IPv6 pelo prefixo /64 (quem tem um IPv6 doméstico
 * controla um /64 inteiro e giraria o endereço para escapar de um limite por endereço).
 * IPv4 mapeado em IPv6 (::ffff:a.b.c.d) vira o IPv4.
 */
export function clientKey(ip: string | undefined): string {
  if (!ip) return 'unknown';
  let addr = ip.trim().replace(/^\[|\]$/g, '').split('%')[0].toLowerCase();
  const mapped = /^::ffff:(\d+\.\d+\.\d+\.\d+)$/.exec(addr);
  if (mapped) addr = mapped[1];
  const kind = isIP(addr);
  if (kind === 4) return addr;
  if (kind !== 6) return 'unknown';
  // Expande "::" e converte um eventual sufixo IPv4 (::1.2.3.4) em dois grupos.
  let tail4: string[] = [];
  const v4 = /^(.*:)(\d+\.\d+\.\d+\.\d+)$/.exec(addr);
  if (v4) {
    const o = v4[2].split('.').map(Number);
    tail4 = [((o[0] << 8) | o[1]).toString(16), ((o[2] << 8) | o[3]).toString(16)];
    addr = v4[1] + (tail4.length ? '0:0' : '');
  }
  const [head, rest] = addr.split('::');
  const h = head ? head.split(':') : [];
  const r = rest === undefined ? [] : rest ? rest.split(':') : [];
  let groups: string[];
  if (rest === undefined) groups = h;
  else groups = [...h, ...Array(Math.max(0, 8 - h.length - r.length)).fill('0'), ...r];
  if (tail4.length) groups = [...groups.slice(0, 6), ...tail4];
  const first4 = groups.slice(0, 4).map((g) => (parseInt(g || '0', 16) || 0).toString(16).padStart(4, '0'));
  return `${first4.join(':')}::/64`;
}

/**
 * Limite de falhas de senha: `ipMax` por `ipWindowMs` por chave (IPv4 / prefixo IPv6 /64) e um teto global
 * alto (200 por hora) que só serve contra inundação distribuída. Uma chave sozinha contribui no máximo
 * `ipMax * (totalWindowMs / ipWindowMs)` = 20 falhas por hora, então nunca enche o teto global sozinha
 * (e o dono, em outro IP, continua entrando).
 */
export class LoginLimiter {
  private perIp = new Map<string, number[]>();
  private all: number[] = [];

  constructor(
    private now: () => Date,
    private ipMax = 5,
    private ipWindowMs = 15 * 60_000,
    private totalMax = 200,
    private totalWindowMs = 60 * 60_000,
  ) {}

  private prune(): void {
    const t = this.now().getTime();
    this.all = this.all.filter((x) => t - x < this.totalWindowMs);
    for (const [ip, list] of this.perIp) {
      const kept = list.filter((x) => t - x < this.ipWindowMs);
      if (kept.length) this.perIp.set(ip, kept);
      else this.perIp.delete(ip);
    }
  }

  /** Segundos até poder tentar de novo, ou 0 se liberado. `key` vem de `clientKey`. */
  blockedFor(key: string): number {
    this.prune();
    const t = this.now().getTime();
    let wait = 0;
    const list = this.perIp.get(key) ?? [];
    if (list.length >= this.ipMax) wait = Math.max(wait, list[0] + this.ipWindowMs - t);
    if (this.all.length >= this.totalMax) wait = Math.max(wait, this.all[0] + this.totalWindowMs - t);
    return wait > 0 ? Math.ceil(wait / 1000) : 0;
  }

  recordFailure(key: string): void {
    const t = this.now().getTime();
    this.all.push(t);
    this.perIp.set(key, [...(this.perIp.get(key) ?? []), t]);
  }
}

/** Contador simples por chave em janela deslizante (ex.: /register por IP). */
export class HitLimiter {
  private hits = new Map<string, number[]>();
  constructor(private now: () => Date, private max: number, private windowMs: number) {}

  /** Registra a tentativa; false se excedeu. */
  allow(key: string): boolean {
    const t = this.now().getTime();
    const list = (this.hits.get(key) ?? []).filter((x) => t - x < this.windowMs);
    if (list.length >= this.max) {
      this.hits.set(key, list);
      return false;
    }
    list.push(t);
    this.hits.set(key, list);
    if (this.hits.size > 5000) for (const k of this.hits.keys()) { this.hits.delete(k); break; }
    return true;
  }
}
