import { describe, expect, it } from 'vitest';
import {
  addDays, formatLongDate, formatTime, localParts, timeZoneMatches, tzOffsetMinutes, zonedDayRange, zonedTime,
} from '../src/time.js';

const SP = 'America/Sao_Paulo';

describe('time', () => {
  it('offset de São Paulo é -180 min', () => {
    expect(tzOffsetMinutes(new Date('2026-09-28T12:00:00Z'), SP)).toBe(-180);
  });

  it('localParts usa o fuso, não o do processo', () => {
    expect(localParts(new Date('2026-09-29T01:30:00Z'), SP)).toEqual({ date: '2026-09-28', weekday: 1, minutes: 22 * 60 + 30 });
    expect(localParts(new Date('2026-10-04T15:00:00Z'), SP).weekday).toBe(7);
  });

  it('zonedTime converte horário local em instante', () => {
    expect(zonedTime('2026-09-28', '07:00', SP).toISOString()).toBe('2026-09-28T10:00:00.000Z');
    expect(zonedTime('2026-09-28', '22:30', SP).toISOString()).toBe('2026-09-29T01:30:00.000Z');
  });

  it('zonedDayRange cobre o dia local inteiro', () => {
    const { start, end } = zonedDayRange(new Date('2026-09-29T02:00:00Z'), SP);
    expect(start.toISOString()).toBe('2026-09-28T03:00:00.000Z');
    expect(end.toISOString()).toBe('2026-09-29T03:00:00.000Z');
  });

  it('addDays atravessa mês', () => {
    expect(addDays('2026-09-30', 1)).toBe('2026-10-01');
    expect(addDays('2026-10-01', -1)).toBe('2026-09-30');
  });

  it('formatos em pt-BR', () => {
    const at = new Date('2026-09-28T11:05:00Z');
    expect(formatLongDate(at, SP)).toBe('segunda-feira, 28 de setembro');
    expect(formatTime(at, SP)).toBe('08:05');
  });

  it('timeZoneMatches compara com o offset do processo', () => {
    const now = new Date('2026-09-28T12:00:00Z');
    expect(timeZoneMatches(now, SP, -180)).toBe(true);
    expect(timeZoneMatches(now, SP, 0)).toBe(false);
  });
});
