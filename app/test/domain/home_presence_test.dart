import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/location_repository.dart';
import 'package:organizacional/domain/home_presence.dart';
import 'package:organizacional/location/location_service.dart';

final _now = DateTime.utc(2026, 10, 12, 9);
const _home = GeoPoint(-19.9320, -43.9380); // Belo Horizonte
const _radius = 50;
const _mPerDeg = 6371000 * math.pi / 180;

GeoPoint _northOf(GeoPoint p, double meters) => GeoPoint(p.lat + meters / _mPerDeg, p.lon);
DateTime _minutesAgo(num m) => _now.subtract(Duration(milliseconds: (m * 60000).round()));

LocationReport _loc(double meters, {double? acc, DateTime? at}) {
  final p = _northOf(_home, meters);
  return LocationReport(fix: GeoFix(lat: p.lat, lon: p.lon, accuracyM: acc), reportedAt: at ?? _minutesAgo(1));
}

PresenceStatus _eval(LocationReport? last, {GeoPoint? home = _home, bool requireHome = true}) =>
    presenceStatus(home: home, radiusM: _radius, requireHome: requireHome, last: last, now: _now);

void main() {
  group('distanceMeters', () {
    test('coordenadas idênticas dão 0 m', () {
      expect(distanceMeters(_home, const GeoPoint(-19.9320, -43.9380)), 0);
    });
    test('um grau de latitude vale cerca de 111 km', () {
      final d = distanceMeters(const GeoPoint(0, 0), const GeoPoint(1, 0));
      expect(d, greaterThan(111000));
      expect(d, lessThan(111400));
    });
    test('é simétrica', () {
      const sp = GeoPoint(-23.5505, -46.6333);
      expect(distanceMeters(_home, sp), closeTo(distanceMeters(sp, _home), 1e-6));
    });
  });

  group('presenceStatus (mesma regra da ponte)', () {
    test('sem casa definida: não exigido', () {
      final r = _eval(_loc(5000), home: null);
      expect(r.state, PresenceState.notRequired);
      expect(r.distanceM, isNull);
    });
    test('require_home desligado: não exigido', () {
      expect(_eval(_loc(5000), requireHome: false).state, PresenceState.notRequired);
    });
    test('sem localização: desconhecido', () {
      final r = _eval(null);
      expect(r.state, PresenceState.unknown);
      expect(r.distanceM, isNull);
    });
    test('localização de 46 min: desconhecido; de 45 min ainda vale', () {
      final old = _eval(_loc(5000, acc: 10, at: _minutesAgo(46)));
      expect(old.state, PresenceState.unknown);
      expect(old.distanceM, isNull);
      expect(_eval(_loc(5000, acc: 10, at: _minutesAgo(45))).state, PresenceState.away);
    });
    test('a 10 m: em casa', () {
      final r = _eval(_loc(10));
      expect(r.state, PresenceState.home);
      expect(r.distanceM, closeTo(10, 0.5));
    });
    test('a 70 m com precisão 30: em casa (70 - 25 = 45)', () {
      final r = _eval(_loc(70, acc: 30));
      expect(r.state, PresenceState.home);
      expect(r.distanceM, closeTo(70, 0.5));
    });
    test('a 78 m com precisão 30: desconhecido', () {
      final r = _eval(_loc(78, acc: 30));
      expect(r.state, PresenceState.unknown);
      expect(r.distanceM, closeTo(78, 0.5));
    });
    test('a 90 m com precisão 30: fora', () {
      expect(_eval(_loc(90, acc: 30)).state, PresenceState.away);
    });
    test('margem de "em casa" limitada a 25 m', () {
      expect(_eval(_loc(80, acc: 500)).state, isNot(PresenceState.home));
    });
    test('GPS fraco: 120 m com precisão 300 não é fora', () {
      expect(_eval(_loc(120, acc: 300)).state, PresenceState.unknown);
    });
    test('precisão acima de 100 m só é fora se a distância supera raio + precisão', () {
      expect(_eval(_loc(500, acc: 150)).state, PresenceState.away);
      expect(_eval(_loc(190, acc: 150)).state, PresenceState.unknown);
    });
    test('precisão 20 m a 200 m: fora', () {
      expect(_eval(_loc(200, acc: 20)).state, PresenceState.away);
    });
    test('sem precisão: borda é desconhecida, longe (> 3x o raio) é fora, dentro é em casa', () {
      expect(_eval(_loc(70)).state, PresenceState.unknown);
      expect(_eval(_loc(60)).state, PresenceState.unknown);
      expect(_eval(_loc(400)).state, PresenceState.away);
      expect(_eval(_loc(40)).state, PresenceState.home);
    });
    test('precisão negativa vale como 0', () {
      expect(_eval(_loc(60, acc: -10)).state, PresenceState.away);
    });
    test('carimbo até 2 min no futuro vale; mais que isso é desconhecido', () {
      expect(_eval(_loc(10, at: _minutesAgo(-2))).state, PresenceState.home);
      final far = _eval(_loc(5000, acc: 10, at: _minutesAgo(-3)));
      expect(far.state, PresenceState.unknown);
      expect(far.distanceM, isNull);
      expect(_eval(_loc(5000, acc: 10, at: _now.add(const Duration(hours: 24)))).state, PresenceState.unknown);
    });
    test('Belo Horizonte vs. São Paulo: fora, a cerca de 489 km', () {
      final r = _eval(LocationReport(
        fix: const GeoFix(lat: -23.5505, lon: -46.6333, accuracyM: 20),
        reportedAt: _minutesAgo(5),
      ));
      expect(r.state, PresenceState.away);
      expect(r.distanceM, allOf(greaterThan(480000), lessThan(500000)));
    });
    test('coordenadas idênticas: em casa a 0 m', () {
      final r = _eval(LocationReport(
        fix: const GeoFix(lat: -19.9320, lon: -43.9380, accuracyM: 5),
        reportedAt: _minutesAgo(1),
      ));
      expect(r.state, PresenceState.home);
      expect(r.distanceM, 0);
    });
    test('coordenadas não finitas: desconhecido', () {
      final r = _eval(LocationReport(
        fix: const GeoFix(lat: double.nan, lon: 0, accuracyM: 5),
        reportedAt: _minutesAgo(1),
      ));
      expect(r.state, PresenceState.unknown);
    });
  });

  group('formatDistance', () {
    test('metros abaixo de 1 km, km com vírgula acima', () {
      expect(formatDistance(850), '850 m');
      expect(formatDistance(2300), '2,3 km');
      expect(formatDistance(173000), '173 km');
      expect(formatDistance(999.6), '1,0 km');
    });
  });
}
