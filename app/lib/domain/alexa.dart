import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import 'json.dart';

enum BridgeState { ok, authRequired, error }

class BridgeStatus {
  const BridgeStatus({required this.state, required this.lastSeen, this.message});

  final BridgeState state;
  final DateTime lastSeen;
  final String? message;

  factory BridgeStatus.fromMap(Map<String, dynamic> m) => BridgeStatus(
        state: switch (m['state']) {
          'auth_required' => BridgeState.authRequired,
          'error' => BridgeState.error,
          _ => BridgeState.ok,
        },
        lastSeen: parseDate(m['last_seen'])!,
        message: m['message'] as String?,
      );
}

enum BridgeHealth { unknown, online, offline, authRequired, error }

const bridgeOfflineAfter = Duration(minutes: 3);

BridgeHealth bridgeHealth(BridgeStatus? s, DateTime now) {
  if (s == null) return BridgeHealth.unknown;
  if (now.difference(s.lastSeen) > bridgeOfflineAfter) return BridgeHealth.offline;
  return switch (s.state) {
    BridgeState.ok => BridgeHealth.online,
    BridgeState.authRequired => BridgeHealth.authRequired,
    BridgeState.error => BridgeHealth.error,
  };
}

String? bridgeBanner(BridgeStatus? s, DateTime now) => switch (bridgeHealth(s, now)) {
      BridgeHealth.online => null,
      BridgeHealth.unknown => 'A ponte da Alexa ainda não se conectou.',
      BridgeHealth.offline =>
        'A ponte da Alexa está offline desde ${DateFormat('HH:mm, dd/MM', 'pt_BR').format(s!.lastSeen)}. '
            'Os despertares vão usar só o alarme reserva.',
      BridgeHealth.authRequired =>
        'O login da Alexa expirou. Refaça o login na ponte (README, seção Alexa).',
      BridgeHealth.error => 'Erro na ponte da Alexa: ${s!.message ?? 'desconhecido'}',
    };

String? bridgeWarning(BridgeStatus? s, List<WakePlan> plans, DateTime now) =>
    plans.any((p) => p.enabled) ? bridgeBanner(s, now) : null;

class AlexaDevice {
  const AlexaDevice({
    required this.id,
    required this.name,
    required this.kind,
    this.operations = const [],
    this.online = true,
  });

  final String id;
  final String name;
  final String kind;
  final List<String> operations;
  final bool online;

  bool supports(String op) => operations.contains(op);

  factory AlexaDevice.fromMap(Map<String, dynamic> m) => AlexaDevice(
        id: m['id'] as String,
        name: m['name'] as String,
        kind: m['kind'] as String,
        operations: ((m['operations'] as List?) ?? const []).cast<String>(),
        online: (m['online'] as bool?) ?? true,
      );
}

class AlexaRoutine {
  const AlexaRoutine({required this.id, required this.name});

  final String id;
  final String name;

  factory AlexaRoutine.fromMap(Map<String, dynamic> m) =>
      AlexaRoutine(id: m['id'] as String, name: m['name'] as String);
}

const weekdayShort = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];

String twoDigits(int n) => n.toString().padLeft(2, '0');

class WakePlan {
  const WakePlan({
    required this.id,
    required this.label,
    required this.days,
    required this.hour,
    required this.minute,
    required this.echoDeviceId,
    this.spotifyQuery,
    this.musicFirst = true,
    this.briefingDelayMin = 3,
    this.volume = 30,
    this.fallbackAlarm = true,
    this.enabled = true,
  });

  final String id;
  final String label;
  final List<int> days;
  final int hour;
  final int minute;
  final String echoDeviceId;
  final String? spotifyQuery;
  final bool musicFirst;
  final int briefingDelayMin;
  final int volume;
  final bool fallbackAlarm;
  final bool enabled;

  factory WakePlan.fromMap(Map<String, dynamic> m) {
    final time = (m['time'] as String).split(':');
    return WakePlan(
      id: m['id'] as String,
      label: m['label'] as String,
      days: ((m['days'] as List?) ?? const []).map((d) => (d as num).toInt()).toList(),
      hour: int.parse(time[0]),
      minute: int.parse(time[1]),
      echoDeviceId: m['echo_device_id'] as String,
      spotifyQuery: m['spotify_query'] as String?,
      musicFirst: (m['music_first'] as bool?) ?? true,
      briefingDelayMin: (m['briefing_delay_min'] as num?)?.toInt() ?? 3,
      volume: (m['volume'] as num?)?.toInt() ?? 30,
      fallbackAlarm: (m['fallback_alarm'] as bool?) ?? true,
      enabled: (m['enabled'] as bool?) ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    final query = spotifyQuery?.trim();
    return {
      'id': id,
      'label': label,
      'days': days,
      'time': '${twoDigits(hour)}:${twoDigits(minute)}',
      'echo_device_id': echoDeviceId,
      'spotify_query': (query == null || query.isEmpty) ? null : query,
      'music_first': musicFirst,
      'briefing_delay_min': briefingDelayMin,
      'volume': volume,
      'fallback_alarm': fallbackAlarm,
      'enabled': enabled,
    };
  }

  WakePlan copyWith({
    String? label,
    List<int>? days,
    int? hour,
    int? minute,
    String? echoDeviceId,
    String? spotifyQuery,
    bool? musicFirst,
    int? briefingDelayMin,
    int? volume,
    bool? fallbackAlarm,
    bool? enabled,
  }) =>
      WakePlan(
        id: id,
        label: label ?? this.label,
        days: days ?? this.days,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        echoDeviceId: echoDeviceId ?? this.echoDeviceId,
        spotifyQuery: spotifyQuery ?? this.spotifyQuery,
        musicFirst: musicFirst ?? this.musicFirst,
        briefingDelayMin: briefingDelayMin ?? this.briefingDelayMin,
        volume: volume ?? this.volume,
        fallbackAlarm: fallbackAlarm ?? this.fallbackAlarm,
        enabled: enabled ?? this.enabled,
      );

  @override
  bool operator ==(Object other) =>
      other is WakePlan &&
      other.id == id &&
      other.label == label &&
      listEquals(other.days, days) &&
      other.hour == hour &&
      other.minute == minute &&
      other.echoDeviceId == echoDeviceId &&
      other.spotifyQuery == spotifyQuery &&
      other.musicFirst == musicFirst &&
      other.briefingDelayMin == briefingDelayMin &&
      other.volume == volume &&
      other.fallbackAlarm == fallbackAlarm &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(id, label, Object.hashAll(days), hour, minute, echoDeviceId,
      spotifyQuery, musicFirst, briefingDelayMin, volume, fallbackAlarm, enabled);
}

String? validateWakePlan(WakePlan p) {
  if (p.label.trim().isEmpty) return 'Dê um nome ao despertar.';
  if (p.days.isEmpty) return 'Escolha pelo menos um dia.';
  if (p.echoDeviceId.isEmpty) return 'Escolha em qual Echo tocar.';
  return null;
}

String formatDays(List<int> days) {
  final set = days.toSet();
  if (set.isEmpty) return 'Nenhum dia';
  if (set.length == 7) return 'Todos os dias';
  if (setEquals(set, {1, 2, 3, 4, 5})) return 'Dias úteis';
  if (setEquals(set, {6, 7})) return 'Fim de semana';
  return (set.toList()..sort()).map((d) => weekdayShort[d - 1]).join(', ');
}

String wakeSummary(WakePlan p, Map<String, String> echoNames) {
  final query = p.spotifyQuery?.trim() ?? '';
  return [
    '${twoDigits(p.hour)}:${twoDigits(p.minute)}',
    formatDays(p.days),
    if (echoNames[p.echoDeviceId] != null) echoNames[p.echoDeviceId]!,
    if (query.isNotEmpty) 'Spotify: $query',
  ].join(' · ');
}

enum CommandStatus { pending, running, done, failed, expired }

class AlexaCommand {
  const AlexaCommand({required this.id, required this.kind, required this.status, this.result});

  final String id;
  final String kind;
  final CommandStatus status;
  final String? result;

  bool get isFinal =>
      status == CommandStatus.done || status == CommandStatus.failed || status == CommandStatus.expired;

  factory AlexaCommand.fromMap(Map<String, dynamic> m) => AlexaCommand(
        id: m['id'] as String,
        kind: m['kind'] as String,
        status: CommandStatus.values.byName(m['status'] as String),
        result: m['result'] as String?,
      );
}

String commandOutcome(AlexaCommand? c) => switch (c?.status) {
      CommandStatus.done => 'Feito.',
      CommandStatus.failed => 'Falhou: ${c!.result ?? 'erro desconhecido'}',
      CommandStatus.expired => 'A ponte demorou demais; comando descartado.',
      _ => 'Sem resposta da ponte da Alexa.',
    };
