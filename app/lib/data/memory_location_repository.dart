import 'dart:async';

import '../location/location_service.dart';
import 'location_repository.dart';
import 'repository.dart';

/// Implementação em memória usada nos testes.
class MemoryLocationRepository implements LocationRepository {
  MemoryLocationRepository({LocationReport? initial, this.failWrites = false}) : _current = initial;

  LocationReport? _current;
  final _changes = StreamController<void>.broadcast(sync: true);

  /// Quando true, toda escrita falha, simulando uma queda de conexão.
  bool failWrites;

  /// Cada chamada de [report] com sucesso, na ordem (apoio para os testes).
  final List<LocationReport> reports = [];

  @override
  Stream<LocationReport?> watchLocation() {
    StreamSubscription<void>? sub;
    late final StreamController<LocationReport?> controller;
    controller = StreamController<LocationReport?>(
      onListen: () {
        controller.add(_current);
        sub = _changes.stream.listen((_) => controller.add(_current));
      },
      onCancel: () {
        sub?.cancel();
        controller.close();
      },
    );
    return controller.stream;
  }

  @override
  Future<void> report(GeoFix fix, DateTime at) async {
    if (failWrites) throw const RepositoryException('Sem conexão (simulado)');
    _current = LocationReport(fix: fix, reportedAt: at);
    reports.add(_current!);
    _changes.add(null);
  }
}
