import 'dart:async';

import '../domain/alexa.dart';

abstract interface class AlexaRepository {
  Stream<BridgeStatus?> watchStatus();
  Stream<List<AlexaDevice>> watchDevices();
  Stream<List<AlexaRoutine>> watchRoutines();
  Stream<List<WakePlan>> watchWakePlans();
  Future<void> upsertWakePlan(WakePlan plan);
  Future<void> deleteWakePlan(String id);

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
