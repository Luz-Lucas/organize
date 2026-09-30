import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/domain/alexa.dart';

void main() {
  final now = DateTime(2026, 9, 28, 7);
  BridgeStatus status(BridgeState s, {int minutesAgo = 0, String? message}) =>
      BridgeStatus(state: s, lastSeen: now.subtract(Duration(minutes: minutesAgo)), message: message);
  const plan = WakePlan(
    id: 'p1', label: 'Aula cedo', days: [1, 2, 3, 4, 5], hour: 7, minute: 0,
    echoDeviceId: 'ECHO', spotifyQuery: 'lofi',
  );

  test('bridgeHealth', () {
    expect(bridgeHealth(null, now), BridgeHealth.unknown);
    expect(bridgeHealth(status(BridgeState.ok, minutesAgo: 1), now), BridgeHealth.online);
    expect(bridgeHealth(status(BridgeState.ok, minutesAgo: 4), now), BridgeHealth.offline);
    expect(bridgeHealth(status(BridgeState.authRequired), now), BridgeHealth.authRequired);
    expect(bridgeHealth(status(BridgeState.error, message: 'x'), now), BridgeHealth.error);
  });

  test('bridgeWarning só aparece com despertar ativo', () {
    final expired = status(BridgeState.authRequired);
    expect(bridgeWarning(expired, const [], now), isNull);
    expect(bridgeWarning(expired, [plan.copyWith(enabled: false)], now), isNull);
    expect(bridgeWarning(expired, const [plan], now), startsWith('O login da Alexa expirou'));
    expect(bridgeWarning(status(BridgeState.ok), const [plan], now), isNull);
    expect(bridgeBanner(status(BridgeState.ok, minutesAgo: 10), now),
        'A ponte da Alexa está offline desde 06:50, 28/09. Os despertares vão usar só o alarme reserva.');
  });

  test('formatDays', () {
    expect(formatDays([1, 2, 3, 4, 5]), 'Dias úteis');
    expect(formatDays([7, 6]), 'Fim de semana');
    expect(formatDays([1, 2, 3, 4, 5, 6, 7]), 'Todos os dias');
    expect(formatDays([5, 1, 3]), 'Seg, Qua, Sex');
    expect(formatDays(const []), 'Nenhum dia');
  });

  test('validateWakePlan', () {
    expect(validateWakePlan(plan), isNull);
    expect(validateWakePlan(plan.copyWith(label: '  ')), 'Dê um nome ao despertar.');
    expect(validateWakePlan(plan.copyWith(days: const [])), 'Escolha pelo menos um dia.');
    expect(validateWakePlan(plan.copyWith(echoDeviceId: '')), 'Escolha em qual Echo tocar.');
  });

  test('WakePlan lê o time do Postgres e grava HH:MM; busca vazia vira null', () {
    final read = WakePlan.fromMap({
      'id': 'p1', 'label': 'Aula cedo', 'days': [1, 2, 3, 4, 5], 'time': '07:00:00',
      'echo_device_id': 'ECHO', 'spotify_query': 'lofi', 'music_first': true,
      'briefing_delay_min': 3, 'volume': 30, 'fallback_alarm': true, 'enabled': true,
    });
    expect(read, plan);
    expect(plan.toMap()['time'], '07:00');
    expect(plan.copyWith(spotifyQuery: '').toMap()['spotify_query'], isNull);
  });

  test('wakeSummary', () {
    expect(wakeSummary(plan, {'ECHO': 'Echo do quarto'}), '07:00 · Dias úteis · Echo do quarto · Spotify: lofi');
  });

  test('commandOutcome', () {
    expect(commandOutcome(const AlexaCommand(id: 'c', kind: 'x', status: CommandStatus.done)), 'Feito.');
    expect(commandOutcome(const AlexaCommand(id: 'c', kind: 'x', status: CommandStatus.failed, result: 'sem Spotify')),
        'Falhou: sem Spotify');
    expect(commandOutcome(const AlexaCommand(id: 'c', kind: 'x', status: CommandStatus.expired)),
        'A ponte demorou demais; comando descartado.');
    expect(commandOutcome(null), 'Sem resposta da ponte da Alexa.');
  });
}
