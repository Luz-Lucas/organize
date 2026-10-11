import 'dart:math' as math;

import '../data/location_repository.dart';

/// Ponto geográfico em graus decimais.
class GeoPoint {
  const GeoPoint(this.lat, this.lon);

  final double lat;
  final double lon;

  @override
  bool operator ==(Object other) => other is GeoPoint && other.lat == lat && other.lon == lon;

  @override
  int get hashCode => Object.hash(lat, lon);
}

const _earthRadiusM = 6371000.0;

/// Margem máxima que a precisão do GPS pode abater da distância para dizer "em casa".
const _maxAccuracyMarginM = 25.0;

/// Idade máxima da localização (a ponte usa os mesmos 45 min).
const presenceMaxAge = Duration(minutes: 45);

/// Carimbos mais de 2 min no futuro são suspeitos (relógio desalinhado).
const _maxFutureSkew = Duration(minutes: 2);

/// Sem precisão informada, só vale "fora" acima de 3x o raio.
const _noAccuracyAwayFactor = 3;

double _rad(double deg) => deg * math.pi / 180;

/// Distância em metros entre dois pontos (haversine).
double distanceMeters(GeoPoint a, GeoPoint b) {
  final dLat = _rad(b.lat - a.lat);
  final dLon = _rad(b.lon - a.lon);
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(_rad(a.lat)) * math.cos(_rad(b.lat)) * math.pow(math.sin(dLon / 2), 2);
  return 2 * _earthRadiusM * math.asin(math.min(1.0, math.sqrt(h)));
}

enum PresenceState { home, away, unknown, notRequired }

class PresenceStatus {
  const PresenceStatus(this.state, [this.distanceM]);

  final PresenceState state;

  /// Distância até a casa, em metros (null quando não foi calculada).
  final double? distanceM;
}

/// Decide se o usuário está em casa, com EXATAMENTE a regra da ponte
/// (`bridge/src/presence.ts`): só devolve [PresenceState.away] com certeza;
/// qualquer dúvida é [PresenceState.unknown] (o despertar toca mesmo assim).
PresenceStatus presenceStatus({
  required GeoPoint? home,
  int radiusM = 50,
  required bool requireHome,
  required LocationReport? last,
  required DateTime now,
}) {
  if (home == null || !requireHome) return const PresenceStatus(PresenceState.notRequired);
  if (last == null) return const PresenceStatus(PresenceState.unknown);

  final age = now.difference(last.reportedAt);
  if (age > presenceMaxAge || age < -_maxFutureSkew) return const PresenceStatus(PresenceState.unknown);

  final fix = last.fix;
  if (!fix.lat.isFinite || !fix.lon.isFinite) return const PresenceStatus(PresenceState.unknown);
  final d = distanceMeters(home, GeoPoint(fix.lat, fix.lon));
  final raw = fix.accuracyM;
  final acc = raw != null && raw.isFinite ? math.max(raw, 0.0) : null;

  if (d - math.min(acc ?? 0, _maxAccuracyMarginM) <= radiusM) {
    return PresenceStatus(PresenceState.home, d);
  }
  final away = acc == null ? d > radiusM * _noAccuracyAwayFactor : d - acc > radiusM;
  return PresenceStatus(away ? PresenceState.away : PresenceState.unknown, d);
}

/// "850 m", "2,3 km", "173 km".
String formatDistance(double meters) {
  if (meters < 999.5) return '${meters.round()} m';
  final km = meters / 1000;
  if (km >= 100) return '${km.round()} km';
  return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
}
