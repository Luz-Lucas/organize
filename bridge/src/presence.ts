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
/** Margem máxima que a precisão do GPS pode abater da distância (cobre o erro dentro de casa). */
const MAX_ACCURACY_MARGIN_M = 25;

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
 * sem localização recente -> `unknown` (o chamador deve tocar mesmo assim).
 */
export function evaluatePresence(i: PresenceInput): PresenceResult {
  if (!i.home || !i.requireHome) return { state: 'not_required', distanceM: null };

  const loc = i.location;
  const maxAgeMs = (i.maxAgeMin ?? DEFAULT_MAX_AGE_MIN) * 60000;
  const ageMs = loc ? i.now.getTime() - loc.reportedAt.getTime() : Number.NaN;
  if (!loc || Number.isNaN(ageMs) || ageMs > maxAgeMs) return { state: 'unknown', distanceM: null };

  const distanceM = haversineM(i.home, loc);
  const margin = Math.min(Math.max(loc.accuracyM ?? 0, 0), MAX_ACCURACY_MARGIN_M);
  return { state: distanceM - margin <= i.home.radiusM ? 'home' : 'away', distanceM };
}
