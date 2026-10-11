import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../location/location_service.dart';

/// Última localização reportada pelo celular (a ponte lê esta mesma linha).
class LocationReport {
  const LocationReport({required this.fix, required this.reportedAt});

  final GeoFix fix;
  final DateTime reportedAt;
}

abstract interface class LocationRepository {
  /// Última localização reportada (null se nunca reportou).
  Stream<LocationReport?> watchLocation();

  /// Grava (substitui) a última localização do usuário.
  Future<void> report(GeoFix fix, DateTime at);
}

final locationRepositoryProvider = Provider<LocationRepository>(
  (ref) => throw UnimplementedError('locationRepositoryProvider precisa de override'),
);

final lastLocationProvider =
    StreamProvider<LocationReport?>((ref) => ref.watch(locationRepositoryProvider).watchLocation());
