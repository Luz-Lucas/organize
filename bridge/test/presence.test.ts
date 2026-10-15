import { describe, expect, it } from 'vitest';
import { evaluatePresence, haversineM } from '../src/presence.js';

const now = new Date('2026-10-12T09:00:00Z');
const home = { lat: -19.9320, lon: -43.9380, radiusM: 50 }; // Belo Horizonte
const M_PER_DEG = (6371000 * Math.PI) / 180;

/** Ponto a `meters` metros ao norte de `p`. */
const northOf = (p: { lat: number; lon: number }, meters: number) => ({ lat: p.lat + meters / M_PER_DEG, lon: p.lon });
const minutesAgo = (m: number) => new Date(now.getTime() - m * 60000);

const loc = (meters: number, accuracyM: number | null = null, reportedAt: Date = minutesAgo(1)) => ({
  ...northOf(home, meters), accuracyM, reportedAt,
});

describe('haversineM', () => {
  it('coordenadas idênticas dão 0 m', () => {
    expect(haversineM(home, { ...home })).toBe(0);
  });

  it('um grau de latitude vale cerca de 111 km', () => {
    const d = haversineM({ lat: 0, lon: 0 }, { lat: 1, lon: 0 });
    expect(d).toBeGreaterThan(111000);
    expect(d).toBeLessThan(111400);
  });

  it('é simétrica', () => {
    const sp = { lat: -23.5505, lon: -46.6333 };
    expect(haversineM(home, sp)).toBeCloseTo(haversineM(sp, home), 6);
  });
});

describe('evaluatePresence', () => {
  it('sem casa definida: não exigido', () => {
    expect(evaluatePresence({ home: null, requireHome: true, location: loc(5000), now }))
      .toEqual({ state: 'not_required', distanceM: null });
  });

  it('require_home desligado: não exigido', () => {
    expect(evaluatePresence({ home, requireHome: false, location: loc(5000), now }))
      .toEqual({ state: 'not_required', distanceM: null });
  });

  it('sem localização: desconhecido', () => {
    expect(evaluatePresence({ home, requireHome: true, location: null, now }))
      .toEqual({ state: 'unknown', distanceM: null });
  });

  it('localização de 46 min: desconhecido (limite padrão de 45)', () => {
    const r = evaluatePresence({ home, requireHome: true, location: loc(5000, 10, minutesAgo(46)), now });
    expect(r).toEqual({ state: 'unknown', distanceM: null });
  });

  it('localização de exatamente 45 min ainda vale', () => {
    const r = evaluatePresence({ home, requireHome: true, location: loc(5000, 10, minutesAgo(45)), now });
    expect(r.state).toBe('away');
  });

  it('maxAgeMin customizado', () => {
    const r = evaluatePresence({ home, requireHome: true, location: loc(10, null, minutesAgo(20)), now, maxAgeMin: 15 });
    expect(r.state).toBe('unknown');
  });

  it('data inválida na localização: desconhecido', () => {
    const r = evaluatePresence({ home, requireHome: true, location: loc(10, null, new Date('invalid')), now });
    expect(r).toEqual({ state: 'unknown', distanceM: null });
  });

  it('a 10 m: em casa', () => {
    const r = evaluatePresence({ home, requireHome: true, location: loc(10), now });
    expect(r.state).toBe('home');
    expect(r.distanceM).toBeCloseTo(10, 0);
  });

  it('a 70 m com precisão 30: em casa (70 - 25 = 45)', () => {
    const r = evaluatePresence({ home, requireHome: true, location: loc(70, 30), now });
    expect(r.state).toBe('home');
    expect(r.distanceM).toBeCloseTo(70, 0);
  });

  it('a 78 m com precisão 30: desconhecido (78 - 30 = 48 não passa de 50)', () => {
    const r = evaluatePresence({ home, requireHome: true, location: loc(78, 30), now });
    expect(r.state).toBe('unknown');
    expect(r.distanceM!).toBeCloseTo(78, 0);
  });

  it('a 90 m com precisão 30: fora (90 - 30 = 60 > 50)', () => {
    expect(evaluatePresence({ home, requireHome: true, location: loc(90, 30), now }).state).toBe('away');
  });

  it('a regra de "em casa" continua limitada a 25 m de margem', () => {
    expect(evaluatePresence({ home, requireHome: true, location: loc(80, 500), now }).state).not.toBe('home');
  });

  it('GPS fraco (precisão 300 m) a 120 m: não é fora', () => {
    expect(evaluatePresence({ home, requireHome: true, location: loc(120, 300), now }).state).toBe('unknown');
  });

  it('GPS fraco (precisão acima de 100 m) só é fora se a distância supera raio + precisão', () => {
    expect(evaluatePresence({ home, requireHome: true, location: loc(500, 150), now }).state).toBe('away');
    expect(evaluatePresence({ home, requireHome: true, location: loc(190, 150), now }).state).toBe('unknown');
  });

  it('precisão 20 m a 200 m: fora', () => {
    expect(evaluatePresence({ home, requireHome: true, location: loc(200, 20), now }).state).toBe('away');
  });

  it('sem precisão informada: perto da borda é desconhecido; longe (> 3x o raio) é fora; dentro é em casa', () => {
    expect(evaluatePresence({ home, requireHome: true, location: loc(70, null), now }).state).toBe('unknown');
    expect(evaluatePresence({ home, requireHome: true, location: loc(60, undefined as unknown as null), now }).state).toBe('unknown');
    expect(evaluatePresence({ home, requireHome: true, location: loc(400, null), now }).state).toBe('away');
    expect(evaluatePresence({ home, requireHome: true, location: loc(40, null), now }).state).toBe('home');
  });

  it('precisão negativa é tratada como 0', () => {
    expect(evaluatePresence({ home, requireHome: true, location: loc(60, -10), now }).state).toBe('away');
  });

  it('localização com carimbo até 2 min no futuro (relógio desalinhado) vale como recente', () => {
    const r = evaluatePresence({ home, requireHome: true, location: loc(10, null, minutesAgo(-2)), now });
    expect(r.state).toBe('home');
  });

  it('carimbo mais de 2 min no futuro: desconhecido', () => {
    const r = evaluatePresence({ home, requireHome: true, location: loc(5000, 10, minutesAgo(-3)), now });
    expect(r).toEqual({ state: 'unknown', distanceM: null });
    const far = evaluatePresence({ home, requireHome: true, location: loc(5000, 10, new Date(now.getTime() + 24 * 3600_000)), now });
    expect(far.state).toBe('unknown');
  });

  it('Belo Horizonte vs. São Paulo: fora, a cerca de 489 km', () => {
    const sp = { lat: -23.5505, lon: -46.6333, accuracyM: 20, reportedAt: minutesAgo(5) };
    const r = evaluatePresence({ home, requireHome: true, location: sp, now });
    expect(r.state).toBe('away');
    expect(r.distanceM!).toBeGreaterThan(480000);
    expect(r.distanceM!).toBeLessThan(500000);
  });

  it('coordenadas idênticas: em casa a 0 m', () => {
    const same = { ...home, accuracyM: 5, reportedAt: minutesAgo(1) };
    expect(evaluatePresence({ home, requireHome: true, location: same, now }))
      .toEqual({ state: 'home', distanceM: 0 });
  });
});
