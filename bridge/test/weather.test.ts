import { beforeEach, describe, expect, it } from 'vitest';
import { clearCityCache, fetchWeather, reverseCity, weatherText, wmoDescription, type Weather } from '../src/weather.js';

const json = (body: unknown, status = 200): Response =>
  new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });

interface Call { url: string; init: RequestInit | undefined }

function fakeFetch(handler: (url: string, init?: RequestInit) => Response | Promise<Response>) {
  const calls: Call[] = [];
  const fn = (async (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input);
    calls.push({ url, init });
    return handler(url, init);
  }) as typeof fetch;
  return { fetch: fn, calls };
}

const forecast = (over: Record<string, unknown> = {}) => ({
  current: { temperature_2m: 21.6, weather_code: 2 },
  daily: { temperature_2m_max: [27.8], temperature_2m_min: [16.5], precipitation_probability_max: [40] },
  ...over,
});

const w = (over: Partial<Weather> = {}): Weather => ({ tempC: 22, code: 2, maxC: 28, minC: 17, rainProb: 40, ...over });

describe('fetchWeather', () => {
  it('lê a previsão do Open-Meteo e arredonda', async () => {
    const f = fakeFetch(() => json(forecast()));
    const r = await fetchWeather(-19.9320, -43.9380, { fetch: f.fetch });
    expect(r).toEqual({ tempC: 22, code: 2, maxC: 28, minC: 17, rainProb: 40 });
    const url = new URL(f.calls[0].url);
    expect(url.origin + url.pathname).toBe('https://api.open-meteo.com/v1/forecast');
    expect(url.searchParams.get('latitude')).toBe('-19.93');
    expect(url.searchParams.get('longitude')).toBe('-43.94');
    expect(url.searchParams.get('current')).toBe('temperature_2m,weather_code');
    expect(url.searchParams.get('daily')).toBe('temperature_2m_max,temperature_2m_min,precipitation_probability_max');
    expect(url.searchParams.get('timezone')).toBe('America/Sao_Paulo');
    expect(url.searchParams.get('forecast_days')).toBe('1');
    expect(f.calls[0].init?.signal).toBeInstanceOf(AbortSignal);
  });

  it('só coordenadas arredondadas a 2 casas (~1 km) saem para o Open-Meteo', async () => {
    const f = fakeFetch(() => json(forecast()));
    await fetchWeather(-19.93249, -43.93799, { fetch: f.fetch });
    await fetchWeather(10.005, 0, { fetch: f.fetch });
    const first = new URL(f.calls[0].url);
    expect(first.searchParams.get('latitude')).toBe('-19.93');
    expect(first.searchParams.get('longitude')).toBe('-43.94');
    expect(f.calls[0].url).not.toMatch(/\d\.\d{3}/);
    expect(new URL(f.calls[1].url).searchParams.get('longitude')).toBe('0.00');
  });

  it('usa o fuso informado; o padrão é America/Sao_Paulo', async () => {
    const f = fakeFetch(() => json(forecast()));
    await fetchWeather(-19.93, -43.94, { fetch: f.fetch }, 'America/Manaus');
    await fetchWeather(-19.93, -43.94, { fetch: f.fetch });
    expect(new URL(f.calls[0].url).searchParams.get('timezone')).toBe('America/Manaus');
    expect(new URL(f.calls[1].url).searchParams.get('timezone')).toBe('America/Sao_Paulo');
  });

  it('probabilidade de chuva ausente vira null', async () => {
    const f = fakeFetch(() => json(forecast({
      daily: { temperature_2m_max: [27.8], temperature_2m_min: [16.5], precipitation_probability_max: [null] },
    })));
    const r = await fetchWeather(-19.93, -43.94, { fetch: f.fetch });
    expect(r).toEqual({ tempC: 22, code: 2, maxC: 28, minC: 17, rainProb: null });
  });

  it('HTTP 500 dá null', async () => {
    const f = fakeFetch(() => json({ error: true }, 500));
    expect(await fetchWeather(-19.93, -43.94, { fetch: f.fetch })).toBeNull();
  });

  it('JSON inválido ou campos faltando dão null', async () => {
    expect(await fetchWeather(1, 1, { fetch: fakeFetch(() => new Response('<html>')).fetch })).toBeNull();
    expect(await fetchWeather(1, 1, { fetch: fakeFetch(() => json({})).fetch })).toBeNull();
    expect(await fetchWeather(1, 1, { fetch: fakeFetch(() => json(forecast({ current: { temperature_2m: 'x', weather_code: 1 } }))).fetch })).toBeNull();
    expect(await fetchWeather(1, 1, { fetch: fakeFetch(() => json(forecast({ daily: { temperature_2m_max: [], temperature_2m_min: [], precipitation_probability_max: [] } }))).fetch })).toBeNull();
    expect(await fetchWeather(1, 1, { fetch: fakeFetch(() => json(null)).fetch })).toBeNull();
  });

  it('erro de rede dá null', async () => {
    const f = fakeFetch(() => { throw new TypeError('fetch failed'); });
    expect(await fetchWeather(1, 1, { fetch: f.fetch })).toBeNull();
  });

  it('estouro do tempo limite dá null', async () => {
    const f = fakeFetch((_url, init) => new Promise<Response>((_res, rej) => {
      init?.signal?.addEventListener('abort', () => rej(init.signal!.reason));
    }));
    expect(await fetchWeather(1, 1, { fetch: f.fetch, timeoutMs: 20 })).toBeNull();
  });

  it('coordenadas inválidas dão null sem chamar a rede', async () => {
    const f = fakeFetch(() => json(forecast()));
    expect(await fetchWeather(Number.NaN, 1, { fetch: f.fetch })).toBeNull();
    expect(await fetchWeather(91, 1, { fetch: f.fetch })).toBeNull();
    expect(await fetchWeather(1, 181, { fetch: f.fetch })).toBeNull();
    expect(f.calls).toHaveLength(0);
  });
});

describe('reverseCity', () => {
  beforeEach(() => clearCityCache());

  it('usa city, com User-Agent e coordenadas arredondadas', async () => {
    const f = fakeFetch(() => json({ address: { city: 'Belo Horizonte', state: 'Minas Gerais' } }));
    expect(await reverseCity(-19.9320, -43.9380, { fetch: f.fetch })).toBe('Belo Horizonte');
    const url = new URL(f.calls[0].url);
    expect(url.origin + url.pathname).toBe('https://nominatim.openstreetmap.org/reverse');
    expect(url.searchParams.get('lat')).toBe('-19.93');
    expect(url.searchParams.get('lon')).toBe('-43.94');
    expect(url.searchParams.get('format')).toBe('jsonv2');
    expect(url.searchParams.get('zoom')).toBe('10');
    expect(url.searchParams.get('accept-language')).toBe('pt-BR');
    expect((f.calls[0].init?.headers as Record<string, string>)['User-Agent']).toBe('organizacional-bridge/1.0');
    expect(f.calls[0].init?.signal).toBeInstanceOf(AbortSignal);
  });

  it.each([
    ['town', { town: 'Nova Lima' }, 'Nova Lima'],
    ['village', { village: 'Macacos' }, 'Macacos'],
    ['municipality', { municipality: 'Betim' }, 'Betim'],
    ['county', { county: 'Região Metropolitana' }, 'Região Metropolitana'],
  ])('cai para %s', async (_name, address, expected) => {
    const f = fakeFetch(() => json({ address }));
    expect(await reverseCity(-19.8, -44.1, { fetch: f.fetch })).toBe(expected);
  });

  it('prefere city a town', async () => {
    const f = fakeFetch(() => json({ address: { town: 'A', city: 'B' } }));
    expect(await reverseCity(-19.8, -44.1, { fetch: f.fetch })).toBe('B');
  });

  it('sem nome utilizável, HTTP ruim, JSON ruim ou erro de rede dão null', async () => {
    expect(await reverseCity(1, 1, { fetch: fakeFetch(() => json({ address: { state: 'MG' } })).fetch })).toBeNull();
    expect(await reverseCity(1, 1, { fetch: fakeFetch(() => json({})).fetch })).toBeNull();
    expect(await reverseCity(1, 1, { fetch: fakeFetch(() => json({ address: { city: '  ' } })).fetch })).toBeNull();
    expect(await reverseCity(1, 1, { fetch: fakeFetch(() => json({}, 429)).fetch })).toBeNull();
    expect(await reverseCity(1, 1, { fetch: fakeFetch(() => new Response('oops')).fetch })).toBeNull();
    expect(await reverseCity(1, 1, { fetch: fakeFetch(() => { throw new Error('boom'); }).fetch })).toBeNull();
  });

  it('estouro do tempo limite dá null', async () => {
    const f = fakeFetch((_url, init) => new Promise<Response>((_res, rej) => {
      init?.signal?.addEventListener('abort', () => rej(init.signal!.reason));
    }));
    expect(await reverseCity(1, 1, { fetch: f.fetch, timeoutMs: 20 })).toBeNull();
  });

  it('cache: a 2ª chamada na mesma coordenada arredondada não usa a rede', async () => {
    const f = fakeFetch(() => json({ address: { city: 'Belo Horizonte' } }));
    expect(await reverseCity(-19.9320, -43.9380, { fetch: f.fetch })).toBe('Belo Horizonte');
    expect(await reverseCity(-19.9349, -43.9401, { fetch: f.fetch })).toBe('Belo Horizonte');
    expect(f.calls).toHaveLength(1);
  });

  it('cache: coordenada arredondada diferente consulta de novo', async () => {
    const f = fakeFetch(() => json({ address: { city: 'X' } }));
    await reverseCity(-19.93, -43.94, { fetch: f.fetch });
    await reverseCity(-23.55, -46.63, { fetch: f.fetch });
    expect(f.calls).toHaveLength(2);
  });

  it('cache: falhas não são guardadas', async () => {
    let n = 0;
    const f = fakeFetch(() => (n++ === 0 ? json({}, 500) : json({ address: { city: 'Y' } })));
    expect(await reverseCity(-19.93, -43.94, { fetch: f.fetch })).toBeNull();
    expect(await reverseCity(-19.93, -43.94, { fetch: f.fetch })).toBe('Y');
    expect(f.calls).toHaveLength(2);
  });

  it('cache expira depois de 24 h', async () => {
    let t = Date.parse('2026-10-12T09:00:00Z');
    const f = fakeFetch(() => json({ address: { city: 'Z' } }));
    const deps = { fetch: f.fetch, now: () => t };
    await reverseCity(-19.93, -43.94, deps);
    t += 23 * 3600_000;
    await reverseCity(-19.93, -43.94, deps);
    expect(f.calls).toHaveLength(1);
    t += 2 * 3600_000;
    await reverseCity(-19.93, -43.94, deps);
    expect(f.calls).toHaveLength(2);
  });
});

describe('wmoDescription', () => {
  it.each([
    [0, 'céu limpo'], [1, 'predominantemente limpo'], [2, 'parcialmente nublado'], [3, 'nublado'],
    [45, 'neblina'], [48, 'neblina'], [51, 'garoa'], [55, 'garoa'], [57, 'garoa'],
    [61, 'chuva'], [65, 'chuva'], [67, 'chuva'], [71, 'neve'], [77, 'neve'],
    [80, 'pancadas de chuva'], [82, 'pancadas de chuva'], [85, 'pancadas de neve'], [86, 'pancadas de neve'],
    [95, 'trovoadas'], [96, 'trovoadas'], [99, 'trovoadas'],
  ])('código %i', (code, text) => {
    expect(wmoDescription(code)).toBe(text);
  });

  it('código desconhecido dá null', () => {
    expect(wmoDescription(4)).toBeNull();
    expect(wmoDescription(-1)).toBeNull();
    expect(wmoDescription(1000)).toBeNull();
  });
});

describe('weatherText', () => {
  it('texto completo', () => {
    expect(weatherText({ city: 'Belo Horizonte', w: w() })).toBe(
      'Em Belo Horizonte agora faz 22 graus, parcialmente nublado. ' +
      'Hoje a máxima é de 28 e a mínima de 17, com 40% de chance de chuva.',
    );
  });

  it('sem cidade', () => {
    expect(weatherText({ city: null, w: w() })).toBe(
      'Agora faz 22 graus, parcialmente nublado. Hoje a máxima é de 28 e a mínima de 17, com 40% de chance de chuva.',
    );
  });

  it('chance de chuva abaixo de 20% é omitida; 20% entra', () => {
    expect(weatherText({ city: null, w: w({ rainProb: 19 }) })).toBe(
      'Agora faz 22 graus, parcialmente nublado. Hoje a máxima é de 28 e a mínima de 17.',
    );
    expect(weatherText({ city: null, w: w({ rainProb: null }) })).not.toContain('chuva');
    expect(weatherText({ city: null, w: w({ rainProb: 20 }) })).toContain('com 20% de chance de chuva.');
  });

  it('singular: 1 grau', () => {
    expect(weatherText({ city: null, w: w({ tempC: 1 }) })).toContain('Agora faz 1 grau,');
  });

  it('zero grau', () => {
    expect(weatherText({ city: null, w: w({ tempC: 0 }) })).toContain('Agora faz 0 graus,');
  });

  it('temperatura negativa é falada como "menos"', () => {
    const t = weatherText({ city: null, w: w({ tempC: -1, maxC: 3, minC: -4, code: 71 }) });
    expect(t).toBe('Agora faz menos 1 grau, neve. Hoje a máxima é de 3 e a mínima de menos 4, com 40% de chance de chuva.');
    expect(weatherText({ city: null, w: w({ tempC: -2 }) })).toContain('menos 2 graus');
  });

  it('código desconhecido: omite a descrição', () => {
    expect(weatherText({ city: 'Lavras', w: w({ code: 42, rainProb: 0 }) })).toBe(
      'Em Lavras agora faz 22 graus. Hoje a máxima é de 28 e a mínima de 17.',
    );
  });

  it('nunca produz "-0"', () => {
    expect(weatherText({ city: null, w: w({ tempC: -0 }) })).toContain('Agora faz 0 graus,');
  });
});
