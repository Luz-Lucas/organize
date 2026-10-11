import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Posição obtida do GPS do aparelho.
class GeoFix {
  const GeoFix({required this.lat, required this.lon, this.accuracyM});

  final double lat;
  final double lon;

  /// Precisão estimada em metros (quanto menor, melhor).
  final double? accuracyM;
}

enum LocationPermissionLevel {
  /// Negada (ainda dá para pedir de novo).
  denied,

  /// Negada de vez: só nas configurações do Android.
  deniedForever,

  /// Só com o app aberto.
  whileInUse,

  /// "Permitir o tempo todo" (necessário para reportar em segundo plano).
  always,

  /// GPS/serviço de localização desligado no aparelho.
  serviceDisabled,
}

/// Acesso à localização do aparelho. A implementação real (geolocator) só
/// existe no Android; nos testes e nas outras plataformas vale a [NoopLocationService].
abstract interface class LocationService {
  Future<LocationPermissionLevel> permission();

  /// Pede a permissão. Com [background] = true pede também "o tempo todo"
  /// (o Android exige esse segundo passo separado do primeiro).
  Future<LocationPermissionLevel> requestPermission({bool background = false});

  /// Posição atual com alta precisão; null se não foi possível (sem
  /// permissão, GPS desligado ou tempo esgotado).
  Future<GeoFix?> currentFix({Duration timeout = const Duration(seconds: 25)});
}

class NoopLocationService implements LocationService {
  const NoopLocationService();

  @override
  Future<LocationPermissionLevel> permission() async => LocationPermissionLevel.denied;

  @override
  Future<LocationPermissionLevel> requestPermission({bool background = false}) async =>
      LocationPermissionLevel.denied;

  @override
  Future<GeoFix?> currentFix({Duration timeout = const Duration(seconds: 25)}) async => null;
}

/// Sobrescrito em `main.dart` (Android) com a implementação do geolocator.
final locationServiceProvider = Provider<LocationService>((ref) => const NoopLocationService());
