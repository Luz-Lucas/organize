import 'dart:async';

import '../domain/alexa.dart';
import '../domain/ids.dart';
import '../domain/wake_override.dart';
import 'alexa_repository.dart';
import 'repository.dart';

/// Implementação em memória para testes; simula a ponte respondendo aos comandos.
class MemoryAlexaRepository implements AlexaRepository {
  MemoryAlexaRepository({
    this._status,
    List<AlexaDevice> devices = const [],
    List<AlexaRoutine> routines = const [],
    List<WakePlan> plans = const [],
    this.respondWith = CommandStatus.done,
    this.respondResult = 'ok',
  })  : _devices = [...devices],
        _routines = [...routines],
        _plans = {for (final p in plans) p.id: p};

  BridgeStatus? _status;
  final List<AlexaDevice> _devices;
  final List<AlexaRoutine> _routines;
  final Map<String, WakePlan> _plans;
  final Map<String, WakeOverride> _overrides = {}; // '<plano>|<data>'
  final CommandStatus? respondWith;
  final String? respondResult;
  final sent = <({String kind, Map<String, Object?> payload})>[];
  final _commands = <String, AlexaCommand>{};
  final _changes = StreamController<void>.broadcast(sync: true);
  bool failWrites = false;

  set status(BridgeStatus? value) {
    _status = value;
    _changes.add(null);
  }

  Stream<T> _watch<T>(T Function() snapshot) {
    StreamSubscription<void>? sub;
    late final StreamController<T> controller;
    controller = StreamController<T>(
      onListen: () {
        controller.add(snapshot());
        sub = _changes.stream.listen((_) => controller.add(snapshot()));
      },
      onCancel: () {
        sub?.cancel();
        controller.close();
      },
    );
    return controller.stream;
  }

  void _checkWrite() {
    if (failWrites) throw const RepositoryException('Sem conexão (simulado)');
  }

  @override
  Stream<BridgeStatus?> watchStatus() => _watch(() => _status);

  @override
  Stream<List<AlexaDevice>> watchDevices() => _watch(() => List.of(_devices));

  @override
  Stream<List<AlexaRoutine>> watchRoutines() => _watch(() => List.of(_routines));

  @override
  Stream<List<WakePlan>> watchWakePlans() => _watch(() => _plans.values.toList()
    ..sort((a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute)));

  @override
  Future<void> upsertWakePlan(WakePlan plan) async {
    _checkWrite();
    _plans[plan.id] = plan;
    _changes.add(null);
  }

  @override
  Future<void> deleteWakePlan(String id) async {
    _checkWrite();
    _plans.remove(id);
    _overrides.removeWhere((_, o) => o.planId == id); // como a cascata do banco
    _changes.add(null);
  }

  static String _overrideKey(String planId, DateTime date) => '$planId|${dateKey(date)}';

  @override
  Stream<List<WakeOverride>> watchOverrides() => _watch(() => _overrides.values.toList()
    ..sort((a, b) {
      final byDate = a.date.compareTo(b.date);
      return byDate != 0 ? byDate : a.planId.compareTo(b.planId);
    }));

  @override
  Future<void> setOverride(WakeOverride override) async {
    _checkWrite();
    _overrides[_overrideKey(override.planId, override.date)] = override;
    _changes.add(null);
  }

  @override
  Future<void> clearOverride(String planId, DateTime date) async {
    _checkWrite();
    _overrides.remove(_overrideKey(planId, date));
    _changes.add(null);
  }

  @override
  Future<String> sendCommand(String kind, Map<String, Object?> payload) async {
    _checkWrite();
    final id = newId();
    sent.add((kind: kind, payload: payload));
    _commands[id] = AlexaCommand(id: id, kind: kind, status: CommandStatus.pending);
    _changes.add(null);
    final respond = respondWith;
    if (respond != null) {
      scheduleMicrotask(() {
        _commands[id] = AlexaCommand(id: id, kind: kind, status: respond, result: respondResult);
        _changes.add(null);
      });
    }
    return id;
  }

  @override
  Stream<AlexaCommand> watchCommand(String id) =>
      _watch(() => _commands[id]).where((c) => c != null).cast<AlexaCommand>();
}
