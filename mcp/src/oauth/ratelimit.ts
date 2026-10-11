/** Limite de falhas de senha: 5 por 15 min por IP e 20 por hora no total. */
export class LoginLimiter {
  private perIp = new Map<string, number[]>();
  private all: number[] = [];

  constructor(
    private now: () => Date,
    private ipMax = 5,
    private ipWindowMs = 15 * 60_000,
    private totalMax = 20,
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

  /** Segundos até poder tentar de novo, ou 0 se liberado. */
  blockedFor(ip: string): number {
    this.prune();
    const t = this.now().getTime();
    let wait = 0;
    const list = this.perIp.get(ip) ?? [];
    if (list.length >= this.ipMax) wait = Math.max(wait, list[0] + this.ipWindowMs - t);
    if (this.all.length >= this.totalMax) wait = Math.max(wait, this.all[0] + this.totalWindowMs - t);
    return wait > 0 ? Math.ceil(wait / 1000) : 0;
  }

  recordFailure(ip: string): void {
    const t = this.now().getTime();
    this.all.push(t);
    this.perIp.set(ip, [...(this.perIp.get(ip) ?? []), t]);
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
