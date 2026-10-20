import { z } from 'zod';
import { UserError, parseWhen, toIso } from './util.js';

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

const ymd = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Use AAAA-MM-DD.');

/** Parâmetro `repeat` de create_event e create_task. */
export const repeatSchema = z.object({
  freq: z.enum(['daily', 'weekdays', 'weekly', 'biweekly', 'monthly']),
  days: z.array(z.number().int().min(1).max(7)).max(7).optional()
    .describe('Dias da semana (1 = seg … 7 = dom) para weekly/biweekly; vazio = o dia da semana do início'),
  until: ymd.optional().describe('Último dia da repetição (AAAA-MM-DD, inclusivo)'),
  count: z.number().int().min(1).max(MAX_OCCURRENCES).optional().describe('Quantidade de ocorrências (1 a 366)'),
}).describe(
  'Repetição: daily (todo dia), weekdays (seg–sex), weekly, biweekly (a cada 2 semanas), monthly (mesmo dia do mês; ' +
  'meses sem esse dia são pulados). Termina em `until` ou `count` (o que vier primeiro); sem nenhum dos dois, ' +
  'repete por 3 meses. Limites: 366 ocorrências e 1 ano a partir do início.');

export type RepeatInput = z.infer<typeof repeatSchema>;

/** Regra gravada em `recurrence`: dias ordenados e sem repetição; sem fim informado, termina 3 meses depois do início. */
export function normalizeRepeat(r: RepeatInput, start: Date, tz: string): Repeat & { days: number[]; until: string | null; count: number | null } {
  const rule = { freq: r.freq, days: [...new Set(r.days ?? [])].sort(), until: r.until ?? null, count: r.count ?? null };
  const l = toIso(start, tz)!;
  if (rule.until === null && rule.count === null) {
    rule.until = new Date(Date.UTC(Number(l.slice(0, 4)), Number(l.slice(5, 7)) - 1 + 3, Number(l.slice(8, 10)))).toISOString().slice(0, 10);
  }
  if (rule.until !== null && rule.until < l.slice(0, 10)) {
    throw new UserError('A data final da repetição não pode ser antes do início.');
  }
  return rule;
}
