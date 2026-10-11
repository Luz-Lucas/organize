import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import 'location_service.dart';

/// Acesso de baixo nível à plataforma (geolocator + permission_handler),
/// separado para que o mapeamento de estados seja testável sem canais nativos.
abstract interface class GeoPlatform {
  Future<bool> serviceEnabled();
  Future<LocationPermission> checkForeground();
  Future<LocationPermission> requestForeground();

  /// "Permitir o tempo todo" já concedida?
  Future<bool> backgroundGranted();

  /// Pede "o tempo todo". No Android 11+ o sistema abre as configurações do
  /// app; devolve se ficou concedida ao voltar.
  Future<bool> requestBackground();

  Future<GeoFix?> position(Duration timeout);
}

class PluginGeoPlatform implements GeoPlatform {
  const PluginGeoPlatform();

  @override
  Future<bool> serviceEnabled() => Geolocator.isLocationServiceEnabled();

  @override
  Future<LocationPermission> checkForeground() => Geolocator.checkPermission();

  @override
  Future<LocationPermission> requestForeground() => Geolocator.requestPermission();

  @override
  Future<bool> backgroundGranted() => ph.Permission.locationAlways.isGranted;

  @override
  Future<bool> requestBackground() async => (await ph.Permission.locationAlways.request()).isGranted;

  @override
  Future<GeoFix?> position(Duration timeout) async {
    final p = await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(accuracy: LocationAccuracy.best, timeLimit: timeout),
    );
    return GeoFix(lat: p.latitude, lon: p.longitude, accuracyM: p.accuracy);
  }
}

/// Implementação Android do [LocationService]. Nunca lança: qualquer falha
/// vira um nível de permissão ou `null`; coordenadas nunca vão para logs.
class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService({GeoPlatform platform = const PluginGeoPlatform()})
      : _p = platform;

  final GeoPlatform _p;

  @override
  Future<LocationPermissionLevel> permission() async {
    try {
      if (!await _p.serviceEnabled()) return LocationPermissionLevel.serviceDisabled;
      return await _level(await _p.checkForeground());
    } catch (_) {
      return LocationPermissionLevel.denied;
    }
  }

  Future<LocationPermissionLevel> _level(LocationPermission fg) async {
    switch (fg) {
      case LocationPermission.always:
        return LocationPermissionLevel.always;
      case LocationPermission.whileInUse:
        // O geolocator já diz "always" quando o Android concedeu o segundo
        // passo; confirma com o permission_handler sem deixar falha derrubar.
        try {
          if (await _p.backgroundGranted()) return LocationPermissionLevel.always;
        } catch (_) {}
        return LocationPermissionLevel.whileInUse;
      case LocationPermission.deniedForever:
        return LocationPermissionLevel.deniedForever;
      case LocationPermission.denied:
      case LocationPermission.unableToDetermine:
        return LocationPermissionLevel.denied;
    }
  }

  @override
  Future<LocationPermissionLevel> requestPermission({bool background = false}) async {
    try {
      if (!await _p.serviceEnabled()) return LocationPermissionLevel.serviceDisabled;
      var level = await _level(await _p.checkForeground());
      if (level == LocationPermissionLevel.denied) {
        level = await _level(await _p.requestForeground());
      }
      if (background && level == LocationPermissionLevel.whileInUse) {
        // Segundo passo, separado do primeiro (exigência do Android 10+).
        // No Android 11+ o sistema pode abrir as configurações; releia o
        // resultado depois, seja qual for o retorno.
        try {
          await _p.requestBackground();
        } catch (_) {}
        level = await _level(await _p.checkForeground());
      }
      return level;
    } catch (_) {
      return permission();
    }
  }

  @override
  Future<GeoFix?> currentFix({Duration timeout = const Duration(seconds: 25)}) async {
    try {
      return await _p.position(timeout);
    } catch (_) {
      return null;
    }
  }
}
