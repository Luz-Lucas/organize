import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:organizacional/location/geolocator_location_service.dart';
import 'package:organizacional/location/location_service.dart';

class FakePlatform implements GeoPlatform {
  FakePlatform({
    this.enabled = true,
    this.foreground = LocationPermission.denied,
    this.afterRequest = LocationPermission.whileInUse,
    this.background = false,
    this.backgroundAfterRequest = true,
    this.fix,
    this.throwEverything = false,
  });

  bool enabled;
  LocationPermission foreground;
  LocationPermission afterRequest;
  bool background;
  bool backgroundAfterRequest;
  GeoFix? fix;
  bool throwEverything;
  int foregroundRequests = 0;
  int backgroundRequests = 0;
  Duration? lastTimeout;

  void _maybeThrow() {
    if (throwEverything) throw Exception('plataforma indisponível');
  }

  @override
  Future<bool> serviceEnabled() async {
    _maybeThrow();
    return enabled;
  }

  @override
  Future<LocationPermission> checkForeground() async {
    _maybeThrow();
    return foreground;
  }

  @override
  Future<LocationPermission> requestForeground() async {
    _maybeThrow();
    foregroundRequests++;
    foreground = afterRequest;
    return foreground;
  }

  @override
  Future<bool> backgroundGranted() async {
    _maybeThrow();
    return background;
  }

  @override
  Future<bool> requestBackground() async {
    _maybeThrow();
    backgroundRequests++;
    background = backgroundAfterRequest;
    return background;
  }

  @override
  Future<GeoFix?> position(Duration timeout) async {
    _maybeThrow();
    lastTimeout = timeout;
    return fix;
  }
}

void main() {
  group('permission()', () {
    Future<LocationPermissionLevel> level(FakePlatform p) => GeolocatorLocationService(platform: p).permission();

    test('GPS desligado tem prioridade', () async {
      expect(await level(FakePlatform(enabled: false, foreground: LocationPermission.always)),
          LocationPermissionLevel.serviceDisabled);
    });

    test('mapeia negada, negada de vez e indeterminada', () async {
      expect(await level(FakePlatform(foreground: LocationPermission.denied)), LocationPermissionLevel.denied);
      expect(await level(FakePlatform(foreground: LocationPermission.unableToDetermine)),
          LocationPermissionLevel.denied);
      expect(await level(FakePlatform(foreground: LocationPermission.deniedForever)),
          LocationPermissionLevel.deniedForever);
    });

    test('whileInUse sem o segundo passo; always com ele', () async {
      expect(await level(FakePlatform(foreground: LocationPermission.whileInUse)),
          LocationPermissionLevel.whileInUse);
      expect(await level(FakePlatform(foreground: LocationPermission.whileInUse, background: true)),
          LocationPermissionLevel.always);
      expect(await level(FakePlatform(foreground: LocationPermission.always)), LocationPermissionLevel.always);
    });

    test('falha da plataforma vira denied, sem lançar', () async {
      expect(await level(FakePlatform(throwEverything: true)), LocationPermissionLevel.denied);
    });
  });

  group('requestPermission()', () {
    test('pede o primeiro passo e para em whileInUse sem background', () async {
      final p = FakePlatform();
      final r = await GeolocatorLocationService(platform: p).requestPermission();
      expect(r, LocationPermissionLevel.whileInUse);
      expect(p.foregroundRequests, 1);
      expect(p.backgroundRequests, 0);
    });

    test('com background pede o segundo passo depois do primeiro', () async {
      final p = FakePlatform();
      final r = await GeolocatorLocationService(platform: p).requestPermission(background: true);
      expect(r, LocationPermissionLevel.always);
      expect(p.foregroundRequests, 1);
      expect(p.backgroundRequests, 1);
    });

    test('negada no primeiro passo não pede o segundo', () async {
      final p = FakePlatform(afterRequest: LocationPermission.deniedForever);
      final r = await GeolocatorLocationService(platform: p).requestPermission(background: true);
      expect(r, LocationPermissionLevel.deniedForever);
      expect(p.backgroundRequests, 0);
    });

    test('segundo passo recusado devolve whileInUse', () async {
      final p = FakePlatform(foreground: LocationPermission.whileInUse, backgroundAfterRequest: false);
      final r = await GeolocatorLocationService(platform: p).requestPermission(background: true);
      expect(r, LocationPermissionLevel.whileInUse);
      expect(p.foregroundRequests, 0);
      expect(p.backgroundRequests, 1);
    });

    test('já em always não pede nada', () async {
      final p = FakePlatform(foreground: LocationPermission.always);
      final r = await GeolocatorLocationService(platform: p).requestPermission(background: true);
      expect(r, LocationPermissionLevel.always);
      expect(p.foregroundRequests + p.backgroundRequests, 0);
    });

    test('GPS desligado não pede permissão', () async {
      final p = FakePlatform(enabled: false);
      expect(await GeolocatorLocationService(platform: p).requestPermission(),
          LocationPermissionLevel.serviceDisabled);
      expect(p.foregroundRequests, 0);
    });

    test('nunca lança', () async {
      expect(await GeolocatorLocationService(platform: FakePlatform(throwEverything: true)).requestPermission(background: true),
          LocationPermissionLevel.denied);
    });
  });

  group('currentFix()', () {
    test('devolve a posição e repassa o tempo limite', () async {
      final p = FakePlatform(fix: const GeoFix(lat: -19.9167, lon: -45.7, accuracyM: 8));
      final f = await GeolocatorLocationService(platform: p).currentFix(timeout: const Duration(seconds: 30));
      expect(f?.accuracyM, 8);
      expect(p.lastTimeout, const Duration(seconds: 30));
    });

    test('qualquer falha vira null', () async {
      expect(await GeolocatorLocationService(platform: FakePlatform(throwEverything: true)).currentFix(), isNull);
    });
  });
}
