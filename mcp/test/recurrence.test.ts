import { describe, expect, it } from 'vitest';
import { expandRepeat, MAX_OCCURRENCES, type Repeat } from '../src/tools/recurrence.js';
import { parseWhen, toIso } from '../src/tools/util.js';

const tz = 'America/Sao_Paulo';
const first = parseWhen('2026-10-12T18:30:00', tz); // segunda-feira
const ymd = (l: Date[]) => l.map((d) => toIso(d, tz)!.slice(0, 10));
const run = (r: Repeat, f = first) => expandRepeat(f, r, tz);

describe('expandRepeat (espelha recurrence.dart)', () => {
  it('daily com count, mantendo a hora local', () => {
    const s = run({ freq: 'daily', count: 3 });
    expect(ymd(s)).toEqual(['2026-10-12', '2026-10-13', '2026-10-14']);
    expect(s.map((d) => toIso(d, tz)!.slice(11, 16))).toEqual(['18:30', '18:30', '18:30']);
  });

  it('until é inclusivo e vale o que acabar primeiro (until/count)', () => {
    expect(ymd(run({ freq: 'daily', until: '2026-10-14' }))).toEqual(['2026-10-12', '2026-10-13', '2026-10-14']);
    expect(run({ freq: 'daily', until: '2026-10-20', count: 2 })).toHaveLength(2);
    expect(run({ freq: 'daily', until: '2026-10-13', count: 9 })).toHaveLength(2);
    expect(run({ freq: 'daily', until: '2026-10-11' })).toHaveLength(0);
  });

  it('weekdays pula sábado e domingo', () => {
    const f = parseWhen('2026-10-15T09:00:00', tz);
    expect(ymd(run({ freq: 'weekdays', count: 6 }, f))).toEqual([
      '2026-10-15', '2026-10-16', '2026-10-19', '2026-10-20', '2026-10-21', '2026-10-22',
    ]);
  });

  it('weekly com ter e qui; sem dias usa o dia do primeiro; não volta antes do primeiro', () => {
    expect(ymd(run({ freq: 'weekly', days: [4, 2], count: 4 }))).toEqual(['2026-10-13', '2026-10-15', '2026-10-20', '2026-10-22']);
    expect(ymd(run({ freq: 'weekly', count: 3 }))).toEqual(['2026-10-12', '2026-10-19', '2026-10-26']);
    const wed = parseWhen('2026-10-14T08:00:00', tz);
    expect(ymd(run({ freq: 'weekly', days: [1, 3], count: 3 }, wed))).toEqual(['2026-10-14', '2026-10-19', '2026-10-21']);
  });

  it('biweekly pula uma semana (segunda a domingo)', () => {
    expect(ymd(run({ freq: 'biweekly', days: [1, 3], count: 4 }))).toEqual(['2026-10-12', '2026-10-14', '2026-10-26', '2026-10-28']);
  });

  it('monthly no mesmo dia; dia 31 só nos meses que têm 31', () => {
    expect(ymd(run({ freq: 'monthly', count: 3 }))).toEqual(['2026-10-12', '2026-11-12', '2026-12-12']);
    const d31 = parseWhen('2026-10-31T08:00:00', tz);
    expect(ymd(run({ freq: 'monthly', count: 5 }, d31))).toEqual(['2026-10-31', '2026-12-31', '2027-01-31', '2027-03-31', '2027-05-31']);
  });

  it('limites: 366 ocorrências e 1 ano (inclusive) a partir do primeiro', () => {
    expect(MAX_OCCURRENCES).toBe(366);
    expect(run({ freq: 'daily', count: 1000 })).toHaveLength(366);
    expect(run({ freq: 'daily' })).toHaveLength(366);
    const d = run({ freq: 'daily', until: '2030-01-01' });
    expect(d).toHaveLength(366);
    expect(toIso(d[365], tz)).toBe('2027-10-12T18:30:00-03:00');
    const w = run({ freq: 'weekly', until: '2030-01-01' });
    expect(w).toHaveLength(53);
    expect(toIso(w[52], tz)).toBe('2027-10-11T18:30:00-03:00');
  });
});
