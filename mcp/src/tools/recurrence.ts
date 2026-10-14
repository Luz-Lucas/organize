import { parseWhen, toIso } from './util.js';

/** Regra de repetição (mesma do app: `lib/domain/recurrence.dart`). Dias ISO: 1 = seg … 7 = dom. */
export interface Repeat {
  freq: 'daily' | 'weekdays' | 'weekly' | 'biweekly' | 'monthly';
  days?: number[];
  /** AAAA-MM-DD, inclusivo. */
  until?: string | null;
  count?: number | null;
}

export const MAX_OCCURRENCES = 366;

const pad = (n: number) => String(n).padStart(2, '0');

/**
 * Inícios das ocorrências, na hora local (de parede) de `firstStart`. Para no `until` (inclusivo), no `count`,
 * em 366 ocorrências ou 1 ano (inclusive) depois de `firstStart`. Sem `until`/`count` vale o limite duro.
 */
export function expandRepeat(firstStart: Date, r: Repeat, tz: string): Date[] {
  const local = toIso(firstStart, tz)!;
  const y = Number(local.slice(0, 4));
  const m = Number(local.slice(5, 7));
  const d = Number(local.slice(8, 10));
  const h = Number(local.slice(11, 13));
  const mi = Number(local.slice(14, 16));
  const firstDow = new Date(Date.UTC(y, m - 1, d)).getUTCDay() || 7; // ISO: 1 = seg … 7 = dom
  const limit = Date.UTC(y + 1, m - 1, d, h, mi);
  const max = Math.min(MAX_OCCURRENCES, Math.max(1, Math.floor(r.count ?? MAX_OCCURRENCES)));
  const out: Date[] = [];

  const accept = (wall: number): boolean => {
    if (wall > limit) return false;
    if (r.until) {
      const w = new Date(wall).toISOString().slice(0, 10);
      if (w > r.until) return false;
    }
    return true;
  };
  const push = (wall: number) => {
    const w = new Date(wall);
    out.push(parseWhen(`${w.toISOString().slice(0, 10)}T${pad(h)}:${pad(mi)}:00`, tz));
  };

  if (r.freq === 'monthly') {
    for (let i = 0; i < 14 && out.length < max; i++) {
      const wall = Date.UTC(y, m - 1 + i, d, h, mi);
      if (new Date(wall).getUTCMonth() !== (m - 1 + i) % 12) continue; // mês sem esse dia
      if (!accept(wall)) break;
      push(wall);
    }
    return out;
  }

  const wanted = new Set(r.days && r.days.length > 0 ? r.days : [firstDow]);
  const interval = r.freq === 'biweekly' ? 2 : 1;
  for (let i = 0; i <= 372 && out.length < max; i++) {
    const wall = Date.UTC(y, m - 1, d + i, h, mi);
    if (!accept(wall)) break;
    const dow = new Date(wall).getUTCDay() || 7;
    const ok = r.freq === 'daily'
      || (r.freq === 'weekdays' && dow <= 5)
      || ((r.freq === 'weekly' || r.freq === 'biweekly') && wanted.has(dow) && Math.floor((i + firstDow - 1) / 7) % interval === 0);
    if (ok) push(wall);
  }
  return out;
}

/** `start` mais `minutes` minutos no relógio local (duração igual em todas as ocorrências). */
export function addWallMinutes(start: Date, minutes: number, tz: string): Date {
  const local = toIso(start, tz)!;
  const wall = Date.UTC(
    Number(local.slice(0, 4)), Number(local.slice(5, 7)) - 1, Number(local.slice(8, 10)),
    Number(local.slice(11, 13)), Number(local.slice(14, 16)) + minutes,
  );
  return parseWhen(new Date(wall).toISOString().slice(0, 19), tz);
}
