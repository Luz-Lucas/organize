import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/location/location_service.dart';
import 'package:organizacional/location/report_policy.dart';

void main() {
  const home = HomeReportConfig(homeLat: -19.93, homeLon: -43.94, requireHome: true);
  const levels = LocationPermissionLevel.values;

  group('shouldReportInBackground', () {
    test('com casa, require_home ligado e permissão "o tempo todo" reporta', () {
      expect(shouldReportInBackground(home, LocationPermissionLevel.always), isTrue);
    });

    test('qualquer outra permissão não reporta', () {
      for (final l in levels.where((l) => l != LocationPermissionLevel.always)) {
        expect(shouldReportInBackground(home, l), isFalse, reason: '$l');
      }
    });

    test('sem casa, com só uma coordenada, ou sem ajustes não reporta', () {
      expect(shouldReportInBackground(const HomeReportConfig(), LocationPermissionLevel.always), isFalse);
      expect(
          shouldReportInBackground(
              const HomeReportConfig(homeLat: -19.9), LocationPermissionLevel.always),
          isFalse);
      expect(shouldReportInBackground(null, LocationPermissionLevel.always), isFalse);
    });

    test('require_home desligado não reporta', () {
      const off = HomeReportConfig(homeLat: -19.93, homeLon: -43.94, requireHome: false);
      expect(shouldReportInBackground(off, LocationPermissionLevel.always), isFalse);
    });
  });

  group('shouldReportInForeground', () {
    test('aceita enquanto em uso e o tempo todo', () {
      expect(shouldReportInForeground(home, LocationPermissionLevel.whileInUse), isTrue);
      expect(shouldReportInForeground(home, LocationPermissionLevel.always), isTrue);
    });

    test('não aceita negada, negada de vez nem GPS desligado', () {
      for (final l in [
        LocationPermissionLevel.denied,
        LocationPermissionLevel.deniedForever,
        LocationPermissionLevel.serviceDisabled,
      ]) {
        expect(shouldReportInForeground(home, l), isFalse, reason: '$l');
      }
    });

    test('sem casa ou require_home desligado não reporta', () {
      expect(shouldReportInForeground(const HomeReportConfig(), LocationPermissionLevel.always), isFalse);
      expect(
          shouldReportInForeground(
              const HomeReportConfig(homeLat: 1, homeLon: 2, requireHome: false),
              LocationPermissionLevel.always),
          isFalse);
    });
  });

  test('HomeReportConfig tem igualdade por valor', () {
    expect(home, const HomeReportConfig(homeLat: -19.93, homeLon: -43.94));
    expect(home == const HomeReportConfig(homeLat: -19.93, homeLon: -43.94, requireHome: false), isFalse);
  });
}
