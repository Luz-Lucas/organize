import 'dart:async';

import '../domain/alexa.dart';
import '../domain/wake_override.dart';

abstract interface class AlexaRepository {
  Stream<BridgeStatus?> watchStatus();
  Stream<List<AlexaDevice>> watchDevices();
  Stream<List<AlexaRoutine>> watchRoutines();
  Stream<List<WakePlan>> watchWakePlans();
  Future<void> upsertWakePlan(WakePlan plan);
  Future<void> deleteWakePlan(String id);

  /// Exceções de um dia só dos despertares ("só amanhã"), ordenadas por data.
  Stream<List<WakeOverride>> watchOverrides();

  /// Grava a exceção do dia; substitui a que já existir para o mesmo plano e data.
  Future<void> setOverride(WakeOverride override);

  /// Volta o despertar ao normal naquele dia (sem erro se não havia exceção).
  Future<void> clearOverride(String planId, DateTime date);

  /// Enfileira um comando para a ponte e devolve o id.
  Future<String> sendCommand(String kind, Map<String, Object?> payload);
  Stream<AlexaCommand> watchCommand(String id);
}

/// Envia o comando e espera a ponte concluir; devolve uma frase para o usuário.
Future<String> runCommand(
  AlexaRepository repo,
  String kind,
  Map<String, Object?> payload, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final id = await repo.sendCommand(kind, payload);
  try {
    final cmd = await repo.watchCommand(id).firstWhere((c) => c.isFinal).timeout(timeout);
    return commandOutcome(cmd);
  } on TimeoutException {
    return commandOutcome(null);
  }
}
