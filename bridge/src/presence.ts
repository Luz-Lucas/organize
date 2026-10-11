export interface GeoPoint { lat: number; lon: number }
export interface HomePoint extends GeoPoint { radiusM: number }
export interface LocationFix extends GeoPoint { accuracyM: number | null; reportedAt: Date }

export type PresenceState = 'not_required' | 'home' | 'away' | 'unknown';
export interface PresenceResult { state: PresenceState; distanceM: number | null }

export interface PresenceInput {
  home: HomePoint | null;
  requireHome: boolean;
  location: LocationFix | null;
  now: Date;
  /** Idade máxima da localização, em minutos (padrão 45). Mais velha que isso = desconhecida. */
  maxAgeMin?: number;
}

const EARTH_RADIUS_M = 6371000;
const DEFAULT_MAX_AGE_MIN = 45;
/** Margem máxima que a precisão do GPS pode abater da distância para dizer "em casa" (cobre o erro dentro de casa). */
const MAX_ACCURACY_MARGIN_M = 25;
/** Tolerância a relógios desalinhados: carimbos mais de 2 min no futuro são suspeitos. */
const MAX_FUTURE_SKEW_MS = 2 * 60000;
/** Sem precisão informada, só vale "fora" quando a distância passa de 3x o raio. */
const NO_ACCURACY_AWAY_FACTOR = 3;

const toRad = (deg: number) => (deg * Math.PI) / 180;

/** Distância em metros entre dois pontos (fórmula de haversine). */
export function haversineM(a: GeoPoint, b: GeoPoint): number {
  const dLat = toRad(b.lat - a.lat);
  const dLon = toRad(b.lon - a.lon);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLon / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.min(1, Math.sqrt(h)));
}

/**
 * Decide se o usuário está em casa na hora do despertar.
 * Só devolve `away` quando há certeza: sem casa/exigência -> `not_required`;
 * sem localização recente (ou com carimbo no futuro) -> `unknown` (o chamador toca mesmo assim).
 * `away` exige distância menos a precisão COMPLETA do GPS acima do raio; sem precisão informada,
 * exige distância acima de 3x o raio. Qualquer dúvida é `unknown`.
 */
export function evaluatePresence(i: PresenceInput): PresenceResult {
  if (!i.home || !i.requireHome) return { state: 'not_required', distanceM: null };

  const loc = i.location;
  const maxAgeMs = (i.maxAgeMin ?? DEFAULT_MAX_AGE_MIN) * 60000;
  const ageMs = loc ? i.now.getTime() - loc.reportedAt.getTime() : Number.NaN;
  if (!loc || Number.isNaN(ageMs) || ageMs > maxAgeMs || ageMs < -MAX_FUTURE_SKEW_MS) return { state: 'unknown', distanceM: null };

  const distanceM = haversineM(i.home, loc);
  const radius = i.home.radiusM;
  const acc = typeof loc.accuracyM === 'number' && Number.isFinite(loc.accuracyM) ? Math.max(loc.accuracyM, 0) : null;

  if (distanceM - Math.min(acc ?? 0, MAX_ACCURACY_MARGIN_M) <= radius) return { state: 'home', distanceM };
  const away = acc === null ? distanceM > radius * NO_ACCURACY_AWAY_FACTOR : distanceM - acc > radius;
  return { state: away ? 'away' : 'unknown', distanceM };
}
