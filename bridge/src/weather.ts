export interface Weather {
  tempC: number;
  code: number;
  maxC: number;
  minC: number;
  /** Probabilidade máxima de chuva do dia (0-100); null quando a previsão não informa. */
  rainProb: number | null;
}

export interface WeatherDeps {
  fetch: typeof fetch;
  /** Tempo limite por chamada (padrão 5 s). */
  timeoutMs?: number;
  /** Relógio injetável (ms), usado só pela expiração do cache de cidades. */
  now?: () => number;
}

const DEFAULT_TIMEOUT_MS = 5000;
const CITY_CACHE_TTL_MS = 24 * 3600 * 1000;
const RAIN_MIN_PROB = 20;
const USER_AGENT = 'organizacional-bridge/1.0';

const cityCache = new Map<string, { city: string; at: number }>();

/** Limpa o cache de cidades (testes). */
export function clearCityCache(): void {
  cityCache.clear();
}

const isNum = (v: unknown): v is number => typeof v === 'number' && Number.isFinite(v);
const isRecord = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null;
const roundInt = (n: number) => { const r = Math.round(n); return r === 0 ? 0 : r; };
const first = (v: unknown): unknown => (Array.isArray(v) ? v[0] : undefined);

async function getJson(url: string, deps: WeatherDeps, headers?: Record<string, string>): Promise<unknown> {
  const res = await deps.fetch(url, {
    signal: AbortSignal.timeout(deps.timeoutMs ?? DEFAULT_TIMEOUT_MS),
    ...(headers ? { headers } : {}),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return res.json();
}

/** Previsão atual + máxima/mínima/chuva do dia (Open-Meteo, sem chave). Qualquer falha -> null. */
export async function fetchWeather(lat: number, lon: number, deps: WeatherDeps): Promise<Weather | null> {
  if (!isNum(lat) || !isNum(lon) || Math.abs(lat) > 90 || Math.abs(lon) > 180) return null;
  try {
    const url = new URL('https://api.open-meteo.com/v1/forecast');
    url.searchParams.set('latitude', String(lat));
    url.searchParams.set('longitude', String(lon));
    url.searchParams.set('current', 'temperature_2m,weather_code');
    url.searchParams.set('daily', 'temperature_2m_max,temperature_2m_min,precipitation_probability_max');
    url.searchParams.set('timezone', 'America/Sao_Paulo');
    url.searchParams.set('forecast_days', '1');

    const body = await getJson(url.toString(), deps);
    if (!isRecord(body) || !isRecord(body.current) || !isRecord(body.daily)) return null;
    const { temperature_2m: temp, weather_code: code } = body.current;
    const max = first(body.daily.temperature_2m_max);
    const min = first(body.daily.temperature_2m_min);
    const rain = first(body.daily.precipitation_probability_max);
    if (!isNum(temp) || !isNum(code) || !isNum(max) || !isNum(min)) return null;
    return {
      tempC: roundInt(temp),
      code: Math.round(code),
      maxC: roundInt(max),
      minC: roundInt(min),
      rainProb: isNum(rain) ? roundInt(rain) : null,
    };
  } catch {
    return null;
  }
}

const round2 = (n: number) => { const r = Math.round(n * 100) / 100; return r === 0 ? 0 : r; };

/**
 * Nome da cidade via Nominatim, com cache em memória por coordenada arredondada a 2 casas
 * (24 h). Só coordenadas arredondadas saem da ponte. Falhas não entram no cache. Falha -> null.
 */
export async function reverseCity(lat: number, lon: number, deps: WeatherDeps): Promise<string | null> {
  if (!isNum(lat) || !isNum(lon) || Math.abs(lat) > 90 || Math.abs(lon) > 180) return null;
  const rLat = round2(lat).toFixed(2);
  const rLon = round2(lon).toFixed(2);
  const key = `${rLat},${rLon}`;
  const nowMs = (deps.now ?? Date.now)();

  const hit = cityCache.get(key);
  if (hit && nowMs - hit.at < CITY_CACHE_TTL_MS) return hit.city;

  try {
    const url = new URL('https://nominatim.openstreetmap.org/reverse');
    url.searchParams.set('lat', rLat);
    url.searchParams.set('lon', rLon);
    url.searchParams.set('format', 'jsonv2');
    url.searchParams.set('zoom', '10');
    url.searchParams.set('accept-language', 'pt-BR');

    const body = await getJson(url.toString(), deps, { 'User-Agent': USER_AGENT });
    if (!isRecord(body) || !isRecord(body.address)) return null;
    const a = body.address;
    for (const field of ['city', 'town', 'village', 'municipality', 'county']) {
      const v = a[field];
      if (typeof v === 'string' && v.trim()) {
        const city = v.trim();
        cityCache.set(key, { city, at: nowMs });
        return city;
      }
    }
    return null;
  } catch {
    return null;
  }
}

/** Código WMO -> descrição em pt-BR (null se desconhecido). */
export function wmoDescription(code: number): string | null {
  if (code === 0) return 'céu limpo';
  if (code === 1) return 'predominantemente limpo';
  if (code === 2) return 'parcialmente nublado';
  if (code === 3) return 'nublado';
  if (code === 45 || code === 48) return 'neblina';
  if (code >= 51 && code <= 57) return 'garoa';
  if (code >= 61 && code <= 67) return 'chuva';
  if (code >= 71 && code <= 77) return 'neve';
  if (code >= 80 && code <= 82) return 'pancadas de chuva';
  if (code === 85 || code === 86) return 'pancadas de neve';
  if (code >= 95 && code <= 99) return 'trovoadas';
  return null;
}

/** Número falado: negativos viram "menos N". */
const spoken = (n: number) => (n < 0 ? `menos ${-n}` : String(n));

/** Texto falado do clima, em pt-BR. */
export function weatherText(i: { city: string | null; w: Weather }): string {
  const { w } = i;
  const temp = roundInt(w.tempC);
  const unit = Math.abs(temp) === 1 ? 'grau' : 'graus';
  const desc = wmoDescription(w.code);
  const now = `${i.city ? `Em ${i.city} agora` : 'Agora'} faz ${spoken(temp)} ${unit}${desc ? `, ${desc}` : ''}.`;
  const rain = w.rainProb !== null && w.rainProb >= RAIN_MIN_PROB ? `, com ${w.rainProb}% de chance de chuva` : '';
  return `${now} Hoje a máxima é de ${spoken(roundInt(w.maxC))} e a mínima de ${spoken(roundInt(w.minC))}${rain}.`;
}
