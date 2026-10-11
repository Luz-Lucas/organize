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

/// O que vem depois da música (só vale com "música primeiro").
enum AfterMusic {
  briefing('Resumo do dia'),
  headlines('Só as manchetes'),
  end('Encerrar');

  const AfterMusic(this.label);

  final String label;

  static AfterMusic parse(Object? value) => AfterMusic.values.where((a) => a.name == value).firstOrNull ?? briefing;
}

const musicStopMinSec = 5;
const musicStopMaxSec = 600;
const briefingDelayMaxSec = 1800;

String _formatSeconds(int sec) => sec >= 60 && sec % 60 == 0 ? '${sec ~/ 60} min' : '$sec s';

/// O que fazer com um dispositivo no despertar.
enum WakeActionType {
  turnOn('Ligar'),
  turnOff('Desligar'),
  setBrightness('Brilho');

  const WakeActionType(this.label);

  final String label;

  static WakeActionType? parse(Object? value) => WakeActionType.values.where((a) => a.name == value).firstOrNull;
}

const maxWakeDeviceActions = 20;
const wakeDeviceDelayMaxMin = 30;

int _clampInt(num n, int min, int max) => n.toInt().clamp(min, max);

/// Uma ação sobre um dispositivo inteligente, executada [delayMin] minutos
/// depois do despertar começar.
class WakeDeviceAction {
  const WakeDeviceAction({
    required this.entityId,
    required this.name,
    required this.action,
    this.brightness,
    this.delayMin = 0,
  });

  final String entityId;
  final String name;
  final WakeActionType action;

  /// 0 a 100; só vale com [WakeActionType.setBrightness].
  final int? brightness;

  /// 0 a 30 minutos.
  final int delayMin;

  /// Lê uma ação do JSON do banco; devolve null para entradas inválidas
  /// (o restante da lista continua valendo).
  static WakeDeviceAction? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['entityId'];
    final action = WakeActionType.parse(raw['action']);
    if (id is! String || id.isEmpty || action == null) return null;
    final name = raw['name'];
    final brightness = raw['brightness'];
    final delay = raw['delayMin'];
    return WakeDeviceAction(
      entityId: id,
      name: name is String && name.isNotEmpty ? name : id,
      action: action,
      brightness: action == WakeActionType.setBrightness ? (brightness is num ? _clampInt(brightness, 0, 100) : 100) : null,
      delayMin: delay is num ? _clampInt(delay, 0, wakeDeviceDelayMaxMin) : 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'entityId': entityId,
        'name': name,
        'action': action.name,
        if (action == WakeActionType.setBrightness) 'brightness': brightness,
        'delayMin': delayMin,
      };

  WakeDeviceAction copyWith({String? entityId, WakeActionType? action, int? brightness, int? delayMin}) =>
      WakeDeviceAction(
        entityId: entityId ?? this.entityId,
        name: name,
        action: action ?? this.action,
        brightness: brightness ?? this.brightness,
        delayMin: delayMin ?? this.delayMin,
      );

  @override
  bool operator ==(Object other) =>
      other is WakeDeviceAction &&
      other.entityId == entityId &&
      other.name == name &&
      other.action == action &&
      other.brightness == brightness &&
      other.delayMin == delayMin;

  @override
  int get hashCode => Object.hash(entityId, name, action, brightness, delayMin);
}

/// Quando o celular toca um alarme próprio (Fase 2; ainda sem tela).
enum PhoneAlarm {
  never,
  fallback,
  always;

  static PhoneAlarm parse(Object? value) => PhoneAlarm.values.where((a) => a.name == value).firstOrNull ?? fallback;
}

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
    this.briefingDelaySec,
    this.musicStopAfterSec,
    this.afterMusic = AfterMusic.briefing,
    this.volume = 30,
    this.fallbackAlarm = true,
    this.enabled = true,
    this.includeWeather = true,
    this.deviceActions = const [],
    this.phoneAlarm = PhoneAlarm.fallback,
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

  /// Espera, em segundos, entre a música começar e o resumo falado (null = usa
  /// [briefingDelayMin], legado). Ignorada quando [musicStopAfterSec] está preenchido.
  final int? briefingDelaySec;

  /// Atraso efetivo do resumo, em segundos.
  int get effectiveBriefingDelaySec => briefingDelaySec ?? briefingDelayMin * 60;

  /// Para a música depois de N segundos (null = não para). Exige [spotifyQuery].
  final int? musicStopAfterSec;

  /// O que vem depois da música (só com [musicFirst]).
  final AfterMusic afterMusic;
  final int volume;
  final bool fallbackAlarm;
  final bool enabled;

  /// Fala a previsão do tempo no despertar.
  final bool includeWeather;

  /// Dispositivos a ligar/desligar/ajustar durante o despertar.
  final List<WakeDeviceAction> deviceActions;

  /// Alarme no celular (Fase 2; sem tela ainda).
  final PhoneAlarm phoneAlarm;

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
      briefingDelaySec: (m['briefing_delay_sec'] as num?)?.toInt(),
      musicStopAfterSec: (m['music_stop_after_sec'] as num?)?.toInt(),
      afterMusic: AfterMusic.parse(m['after_music']),
      volume: (m['volume'] as num?)?.toInt() ?? 30,
      fallbackAlarm: (m['fallback_alarm'] as bool?) ?? true,
      enabled: (m['enabled'] as bool?) ?? true,
      includeWeather: (m['include_weather'] as bool?) ?? true,
      deviceActions: [
        if (m['device_actions'] case final List raw)
          for (final entry in raw)
            ?WakeDeviceAction.tryParse(entry),
      ],
      phoneAlarm: PhoneAlarm.parse(m['phone_alarm']),
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
      'briefing_delay_sec': briefingDelaySec,
      'music_stop_after_sec': musicStopAfterSec,
      'after_music': afterMusic.name,
      'volume': volume,
      'fallback_alarm': fallbackAlarm,
      'enabled': enabled,
      'include_weather': includeWeather,
      'device_actions': [for (final a in deviceActions) a.toMap()],
      'phone_alarm': phoneAlarm.name,
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
    int? briefingDelaySec,
    bool clearBriefingDelay = false,
    int? musicStopAfterSec,
    bool clearMusicStop = false,
    AfterMusic? afterMusic,
    int? volume,
    bool? fallbackAlarm,
    bool? enabled,
    bool? includeWeather,
    List<WakeDeviceAction>? deviceActions,
    PhoneAlarm? phoneAlarm,
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
        briefingDelaySec: clearBriefingDelay ? null : (briefingDelaySec ?? this.briefingDelaySec),
        musicStopAfterSec: clearMusicStop ? null : (musicStopAfterSec ?? this.musicStopAfterSec),
        afterMusic: afterMusic ?? this.afterMusic,
        volume: volume ?? this.volume,
        fallbackAlarm: fallbackAlarm ?? this.fallbackAlarm,
        enabled: enabled ?? this.enabled,
        includeWeather: includeWeather ?? this.includeWeather,
        deviceActions: deviceActions ?? this.deviceActions,
        phoneAlarm: phoneAlarm ?? this.phoneAlarm,
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
      other.briefingDelaySec == briefingDelaySec &&
      other.musicStopAfterSec == musicStopAfterSec &&
      other.afterMusic == afterMusic &&
      other.volume == volume &&
      other.fallbackAlarm == fallbackAlarm &&
      other.enabled == enabled &&
      other.includeWeather == includeWeather &&
      listEquals(other.deviceActions, deviceActions) &&
      other.phoneAlarm == phoneAlarm;

  @override
  int get hashCode => Object.hash(id, label, Object.hashAll(days), hour, minute, echoDeviceId,
      spotifyQuery, musicFirst, briefingDelayMin, briefingDelaySec, musicStopAfterSec, afterMusic, volume, fallbackAlarm, enabled,
      includeWeather, Object.hashAll(deviceActions), phoneAlarm);
}

String? validateWakePlan(WakePlan p) {
  if (p.label.trim().isEmpty) return 'Dê um nome ao despertar.';
  if (p.days.isEmpty) return 'Escolha pelo menos um dia.';
  if (p.echoDeviceId.isEmpty) return 'Escolha em qual Echo tocar.';
  final delay = p.briefingDelaySec;
  if (delay != null && (delay < 0 || delay > briefingDelayMaxSec)) {
    return 'O tempo para falar o resumo deve ficar entre 0 s e 30 min.';
  }
  final stop = p.musicStopAfterSec;
  if (stop != null) {
    if (stop < musicStopMinSec || stop > musicStopMaxSec) {
      return 'O tempo para parar a música deve ficar entre 5 s e 10 min.';
    }
    if ((p.spotifyQuery?.trim() ?? '').isEmpty) return 'Para parar a música, escolha uma busca do Spotify.';
  }
  // "Encerrar" só vale depois de uma música que tocou; sem busca ninguém falaria nada ao despertar.
  if (p.afterMusic == AfterMusic.end && (p.spotifyQuery?.trim() ?? '').isEmpty) {
    return 'Para encerrar depois da música, escolha uma busca do Spotify.';
  }
  final actions = p.deviceActions;
  if (actions.length > maxWakeDeviceActions) return 'No máximo $maxWakeDeviceActions dispositivos por despertar.';
  if (actions.any((a) => a.entityId.isEmpty)) return 'Escolha o dispositivo de cada ação.';
  if (actions.map((a) => a.entityId).toSet().length != actions.length) {
    return 'Cada dispositivo só pode aparecer uma vez no despertar.';
  }
  if (actions.any((a) => a.delayMin < 0 || a.delayMin > wakeDeviceDelayMaxMin)) {
    return 'O atraso de cada dispositivo deve ficar entre 0 e $wakeDeviceDelayMaxMin min.';
  }
  if (actions.any((a) => a.action == WakeActionType.setBrightness && (a.brightness == null || a.brightness! < 0 || a.brightness! > 100))) {
    return 'O brilho deve ficar entre 0 e 100%.';
  }
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
    if (query.isNotEmpty)
      'Spotify: $query${p.musicStopAfterSec != null ? ' (para após ${_formatSeconds(p.musicStopAfterSec!)})' : ''}',
    if (p.briefingDelaySec != null && p.musicFirst && p.musicStopAfterSec == null)
      'fala após ${_formatSeconds(p.briefingDelaySec!)}',
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
