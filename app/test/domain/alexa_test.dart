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
    expect(wakeSummary(plan.copyWith(musicStopAfterSec: 30), {'ECHO': 'Echo do quarto'}),
        '07:00 · Dias úteis · Echo do quarto · Spotify: lofi (para após 30 s)');
    expect(wakeSummary(plan.copyWith(musicStopAfterSec: 120), const {}),
        '07:00 · Dias úteis · Spotify: lofi (para após 2 min)');
  });

  group('atraso do resumo em segundos', () {
    test('padrão nulo usa os minutos legados; ida e volta com briefing_delay_sec', () {
      expect(plan.briefingDelaySec, isNull);
      expect(plan.effectiveBriefingDelaySec, 180);
      expect(plan.toMap()['briefing_delay_sec'], isNull);
      final p = plan.copyWith(briefingDelaySec: 10);
      expect(p.effectiveBriefingDelaySec, 10);
      expect(p.toMap()['briefing_delay_sec'], 10);
      final read = WakePlan.fromMap({...p.toMap(), 'time': '07:00:00'});
      expect(read, p);
      expect(read.hashCode, p.hashCode);
      expect(read, isNot(plan));
      expect(WakePlan.fromMap({...plan.toMap(), 'time': '07:00:00'}).briefingDelaySec, isNull);
    });

    test('copyWith limpa com clearBriefingDelay', () {
      final p = plan.copyWith(briefingDelaySec: 10);
      expect(p.copyWith(label: 'x').briefingDelaySec, 10);
      expect(p.copyWith(clearBriefingDelay: true).briefingDelaySec, isNull);
    });

    test('validateWakePlan: 0 a 1800 s', () {
      expect(validateWakePlan(plan.copyWith(briefingDelaySec: 0)), isNull);
      expect(validateWakePlan(plan.copyWith(briefingDelaySec: 1800)), isNull);
      const msg = 'O tempo para falar o resumo deve ficar entre 0 s e 30 min.';
      expect(validateWakePlan(plan.copyWith(briefingDelaySec: -1)), msg);
      expect(validateWakePlan(plan.copyWith(briefingDelaySec: 1801)), msg);
    });

    test('wakeSummary mostra "fala após" só sem parada e com música primeiro', () {
      expect(wakeSummary(plan.copyWith(briefingDelaySec: 10), {'ECHO': 'Echo do quarto'}),
          '07:00 · Dias úteis · Echo do quarto · Spotify: lofi · fala após 10 s');
      expect(wakeSummary(plan.copyWith(briefingDelaySec: 120), const {}),
          '07:00 · Dias úteis · Spotify: lofi · fala após 2 min');
      expect(wakeSummary(plan.copyWith(briefingDelaySec: 10, musicStopAfterSec: 30), const {}),
          '07:00 · Dias úteis · Spotify: lofi (para após 30 s)');
      expect(wakeSummary(plan.copyWith(briefingDelaySec: 10, musicFirst: false), const {}),
          '07:00 · Dias úteis · Spotify: lofi');
    });
  });

  group('parar a música', () {
    test('padrões: não para e segue com o resumo', () {
      expect(plan.musicStopAfterSec, isNull);
      expect(plan.afterMusic, AfterMusic.briefing);
      expect(plan.toMap()['music_stop_after_sec'], isNull);
      expect(plan.toMap()['after_music'], 'briefing');
    });

    test('fromMap tolera ausência e valores desconhecidos', () {
      Map<String, dynamic> base() => {
            'id': 'p1', 'label': 'Aula cedo', 'days': [1, 2, 3, 4, 5], 'time': '07:00:00',
            'echo_device_id': 'ECHO', 'spotify_query': 'lofi',
          };
      final bare = WakePlan.fromMap(base());
      expect(bare.musicStopAfterSec, isNull);
      expect(bare.afterMusic, AfterMusic.briefing);
      final nulls = WakePlan.fromMap({...base(), 'music_stop_after_sec': null, 'after_music': null});
      expect(nulls.musicStopAfterSec, isNull);
      expect(nulls.afterMusic, AfterMusic.briefing);
      expect(WakePlan.fromMap({...base(), 'after_music': 'x'}).afterMusic, AfterMusic.briefing);
    });

    test('ida e volta', () {
      final p = plan.copyWith(musicStopAfterSec: 30, afterMusic: AfterMusic.headlines);
      final map = p.toMap();
      expect(map['music_stop_after_sec'], 30);
      expect(map['after_music'], 'headlines');
      final read = WakePlan.fromMap({...map, 'time': '07:00:00'});
      expect(read, p);
      expect(read.hashCode, p.hashCode);
      expect(read, isNot(plan));
      expect(plan.copyWith(afterMusic: AfterMusic.end).toMap()['after_music'], 'end');
      expect(WakePlan.fromMap({...plan.toMap(), 'time': '07:00:00', 'music_stop_after_sec': 45.0}).musicStopAfterSec, 45);
    });

    test('copyWith limpa o tempo de parada com clearMusicStop', () {
      final p = plan.copyWith(musicStopAfterSec: 30);
      expect(p.copyWith(label: 'x').musicStopAfterSec, 30);
      expect(p.copyWith(clearMusicStop: true).musicStopAfterSec, isNull);
    });

    test('AfterMusic.label', () {
      expect(AfterMusic.briefing.label, 'Resumo do dia');
      expect(AfterMusic.headlines.label, 'Só as manchetes');
      expect(AfterMusic.end.label, 'Encerrar');
    });

    test('validateWakePlan: 5 a 600 s e exige busca do Spotify', () {
      expect(validateWakePlan(plan.copyWith(musicStopAfterSec: 5)), isNull);
      expect(validateWakePlan(plan.copyWith(musicStopAfterSec: 600)), isNull);
      expect(validateWakePlan(plan.copyWith(musicStopAfterSec: 4)), 'O tempo para parar a música deve ficar entre 5 s e 10 min.');
      expect(validateWakePlan(plan.copyWith(musicStopAfterSec: 601)), 'O tempo para parar a música deve ficar entre 5 s e 10 min.');
      const noQuery = WakePlan(
        id: 'p2', label: 'x', days: [1], hour: 7, minute: 0, echoDeviceId: 'ECHO', musicStopAfterSec: 30,
      );
      const stop = 'Para parar a música, escolha uma busca do Spotify.';
      expect(validateWakePlan(noQuery), stop);
      expect(validateWakePlan(noQuery.copyWith(spotifyQuery: '   ')), stop);
      expect(validateWakePlan(noQuery.copyWith(clearMusicStop: true)), isNull);
    });
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
