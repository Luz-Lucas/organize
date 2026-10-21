import 'dart:async';

import '../domain/alexa.dart';
import '../domain/wake_override.dart';
import '../sync/local_store.dart';
import 'alexa_repository.dart';

const _plans = 'wake_plans';
const _overrides = 'wake_overrides';

/// `id` local da exceção: `wake_overrides` não tem coluna `id` (a chave é plano + data); este `id`
/// sintético existe só no aparelho e a camada de envio o troca pela chave composta.
String overrideRowId(String planId, DateTime date) => '$planId|${dateKey(date)}';

/// Alexa: os despertares (planos e exceções) são local-primeiro; dispositivos, rotinas, status da ponte
/// e comandos continuam online ([_online]) porque dependem da ponte e da internet por natureza.
class LocalFirstAlexaRepository implements AlexaRepository {
  LocalFirstAlexaRepository(this._store, this._online);

  final LocalStore _store;
  final AlexaRepository _online;

  @override
  Stream<BridgeStatus?> watchStatus() => _online.watchStatus();

  @override
  Stream<List<AlexaDevice>> watchDevices() => _online.watchDevices();

  @override
  Stream<List<AlexaRoutine>> watchRoutines() => _online.watchRoutines();

  @override
  Future<String> sendCommand(String kind, Map<String, Object?> payload) => _online.sendCommand(kind, payload);

  @override
  Stream<AlexaCommand> watchCommand(String id) => _online.watchCommand(id);

  // ---------------------------------------------------------------- despertares

  @override
  Stream<List<WakePlan>> watchWakePlans() => _store.watch(_plans).map((rows) => [for (final r in rows) WakePlan.fromMap(r)]
    ..sort((a, b) {
      final byTime = (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    }));

  @override
  Future<void> upsertWakePlan(WakePlan plan) => _store.put(_plans, plan.toMap());

  /// Como a cascata do banco: as exceções do despertar somem junto (enfileiradas antes, para a nuvem
  /// apagar na mesma ordem).
  @override
  Future<void> deleteWakePlan(String id) async {
    final doomed = [
      for (final r in await _store.all(_overrides))
        if (r['plan_id'] == id) r['id'] as String,
    ];
    await _store.removeMany(_overrides, doomed);
    await _store.remove(_plans, id);
  }

  @override
  Stream<List<WakeOverride>> watchOverrides() =>
      _store.watch(_overrides).map((rows) => [for (final r in rows) WakeOverride.fromMap(r)]
        ..sort((a, b) {
          final byDate = a.date.compareTo(b.date);
          return byDate != 0 ? byDate : a.planId.compareTo(b.planId);
        }));

  @override
  Future<void> setOverride(WakeOverride override) =>
      _store.put(_overrides, {...override.toMap(), 'id': overrideRowId(override.planId, override.date)});

  @override
  Future<void> clearOverride(String planId, DateTime date) =>
      _store.remove(_overrides, overrideRowId(planId, date));
}
