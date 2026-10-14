import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_alexa_repository.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/data/memory_settings_repository.dart';
import 'package:organizacional/domain/user_settings.dart';
import 'package:organizacional/ui/org_widgets.dart';
import 'package:organizacional/domain/alexa.dart';

import '../helpers.dart';

const _tall = Size(1000, 1800);
final _now = DateTime(2026, 9, 28, 10);
const _plan = WakePlan(
  id: 'p1',
  label: 'Aula cedo',
  days: [1, 2, 3, 4, 5],
  hour: 7,
  minute: 0,
  echoDeviceId: 'ECHO',
  spotifyQuery: 'lofi',
);

MemoryAlexaRepository _alexa({
  BridgeState state = BridgeState.ok,
  int minutesAgo = 0,
  List<WakePlan> plans = const [_plan],
  CommandStatus? respondWith = CommandStatus.done,
  String? respondResult = 'ok',
}) => MemoryAlexaRepository(
  status: BridgeStatus(
    state: state,
    lastSeen: _now.subtract(Duration(minutes: minutesAgo)),
  ),
  devices: const [
    AlexaDevice(id: 'ECHO', name: 'Echo do quarto', kind: 'echo'),
    AlexaDevice(id: 'ECHO2', name: 'Echo da sala', kind: 'echo'),
    AlexaDevice(id: 'luz1', name: 'Luz do quarto', kind: 'smart', operations: ['turnOn', 'turnOff', 'setBrightness']),
  ],
  routines: const [AlexaRoutine(id: 'r1', name: 'Boa noite')],
  plans: plans,
  respondWith: respondWith,
  respondResult: respondResult,
);

void main() {
  testWidgets('Casa lista despertares, rotinas e dispositivos; sem aviso com a ponte online', (tester) async {
    await pumpApp(tester, MemoryRepository(), location: '/casa', now: _now, alexa: _alexa(), size: _tall);
    expect(find.text('Aula cedo'), findsOneWidget);
    expect(find.text('07:00 · Dias úteis · Echo do quarto · Spotify: lofi'), findsOneWidget);
    expect(find.text('Boa noite'), findsOneWidget);
    expect(find.text('Luz do quarto'), findsOneWidget);
    expect(find.byKey(const Key('bridge-banner')), findsNothing);
  });

  testWidgets('ponte offline mostra aviso em Casa', (tester) async {
    await pumpApp(tester, MemoryRepository(), location: '/casa', now: _now, alexa: _alexa(minutesAgo: 10), size: _tall);
    expect(find.byKey(const Key('bridge-banner')), findsOneWidget);
    expect(find.textContaining('offline desde 09:50'), findsOneWidget);
  });

  testWidgets('executar rotina envia o Echo escolhido e mostra o resultado', (tester) async {
    final alexa = _alexa();
    await pumpApp(tester, MemoryRepository(), location: '/casa', now: _now, alexa: alexa, size: _tall);
    await tester.tap(find.byKey(const ValueKey('run-routine-r1')));
    await tester.pumpAndSettle();
    expect(alexa.sent.single.kind, 'routine');
    expect(alexa.sent.single.payload, {'routineId': 'r1', 'echoDeviceId': 'ECHO'});
    expect(find.text('Feito.'), findsOneWidget);
  });

  testWidgets('falha da ponte aparece para o usuário', (tester) async {
    final alexa = _alexa(respondWith: CommandStatus.failed, respondResult: 'rotina não encontrada');
    await pumpApp(tester, MemoryRepository(), location: '/casa', now: _now, alexa: alexa, size: _tall);
    await tester.tap(find.byKey(const ValueKey('run-routine-r1')));
    await tester.pumpAndSettle();
    expect(find.text('Falhou: rotina não encontrada'), findsOneWidget);
  });

  testWidgets('ligar dispositivo e falar no Echo', (tester) async {
    final alexa = _alexa();
    await pumpApp(tester, MemoryRepository(), location: '/casa', now: _now, alexa: alexa, size: _tall);
    await tester.tap(find.byKey(const ValueKey('on-luz1')));
    await tester.pumpAndSettle();
    expect(alexa.sent.last.payload, {'entityId': 'luz1', 'action': 'turnOn'});
    await tester.enterText(find.byKey(const Key('speak-text')), 'o jantar está pronto');
    await tester.tap(find.byKey(const Key('speak-send')));
    await tester.pumpAndSettle();
    expect(alexa.sent.last.kind, 'speak');
    expect(alexa.sent.last.payload, {'echoDeviceId': 'ECHO', 'text': 'o jantar está pronto'});
  });

  testWidgets('desativar despertar pelo switch', (tester) async {
    final alexa = _alexa();
    await pumpApp(tester, MemoryRepository(), location: '/casa', now: _now, alexa: alexa, size: _tall);
    await tester.tap(find.byKey(const ValueKey('wake-enabled-p1')));
    await tester.pumpAndSettle();
    expect((await alexa.watchWakePlans().first).single.enabled, isFalse);
  });

  testWidgets('novo despertar valida dias e salva', (tester) async {
    final alexa = _alexa(plans: const []);
    await pumpApp(tester, MemoryRepository(), location: '/casa/despertar/novo', now: _now, alexa: alexa, size: _tall);
    await tester.enterText(find.byKey(const Key('wake-label')), 'Academia');
    for (var d = 1; d <= 5; d++) {
      await tester.tap(find.byKey(ValueKey('day-$d')));
    }
    await tester.pump();
    await tester.tap(find.byKey(const Key('wake-save')));
    await tester.pump();
    expect(find.text('Escolha pelo menos um dia.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('day-6')));
    await tester.enterText(find.byKey(const Key('wake-spotify')), 'rock');
    await tester.tap(find.byKey(const Key('wake-save')));
    await tester.pumpAndSettle();
    final saved = (await alexa.watchWakePlans().first).single;
    expect(saved.label, 'Academia');
    expect(saved.days, [6]);
    expect(saved.echoDeviceId, 'ECHO');
    expect(saved.spotifyQuery, 'rock');
    expect(find.text('Academia'), findsOneWidget); // voltou para Casa
  });

  group('atraso do resumo em segundos', () {
    bool selected(WidgetTester tester, String key) => tester.widget<ChoiceChip>(find.byKey(Key(key))).selected;

    testWidgets('despertar novo começa em 10 s e salva a escolha de 20 s', (tester) async {
      final alexa = _alexa(plans: const []);
      await pumpApp(tester, MemoryRepository(), location: '/casa/despertar/novo', now: _now, alexa: alexa, size: _tall);
      expect(find.byKey(const Key('briefing-delay-10')), findsNothing); // "Avançado" fechado
      await expandAdvanced(tester);
      expect(find.text('Falar o resumo após'), findsOneWidget);
      expect(find.text('A música toca primeiro para você acordar de verdade.'), findsOneWidget);
      expect(selected(tester, 'briefing-delay-10'), isTrue);
      await tester.tap(find.byKey(const Key('briefing-delay-20')));
      await tester.pump();
      expect(selected(tester, 'briefing-delay-20'), isTrue);
      expect(selected(tester, 'briefing-delay-10'), isFalse);
      await tester.tap(find.byKey(const Key('wake-save')));
      await tester.pumpAndSettle();
      expect((await alexa.watchWakePlans().first).single.briefingDelaySec, 20);
    });

    testWidgets('despertar novo salvo sem mexer grava 10 s', (tester) async {
      final alexa = _alexa(plans: const []);
      await pumpApp(tester, MemoryRepository(), location: '/casa/despertar/novo', now: _now, alexa: alexa, size: _tall);
      await tester.tap(find.byKey(const Key('wake-save')));
      await tester.pumpAndSettle();
      expect((await alexa.watchWakePlans().first).single.briefingDelaySec, 10);
    });

    testWidgets('despertar antigo mostra os minutos convertidos e não perde o valor', (tester) async {
      final alexa = _alexa(); // briefingDelayMin 3, sem segundos
      await pumpApp(tester, MemoryRepository(), location: '/casa/despertar/p1', now: _now, alexa: alexa, size: _tall);
      expect(selected(tester, 'briefing-delay-180'), isTrue);
      expect(find.byKey(const Key('briefing-delay-custom')), findsNothing);
      await tester.tap(find.byKey(const Key('wake-save')));
      await tester.pumpAndSettle();
      expect((await alexa.watchWakePlans().first).single.briefingDelaySec, isNull);
    });

    testWidgets('legado sem opção equivalente vira Personalizado até escolher outra', (tester) async {
      final alexa = _alexa(plans: const [
        WakePlan(
          id: 'p1', label: 'Aula cedo', days: [1, 2, 3, 4, 5], hour: 7, minute: 0,
          echoDeviceId: 'ECHO', spotifyQuery: 'lofi', briefingDelayMin: 5,
        ),
      ]);
      await pumpApp(tester, MemoryRepository(), location: '/casa/despertar/p1', now: _now, alexa: alexa, size: _tall);
      expect(find.text('Personalizado (5 min)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('briefing-delay-30')));
      await tester.pump();
      expect(find.byKey(const Key('briefing-delay-custom')), findsNothing);
      await tester.tap(find.byKey(const Key('wake-save')));
      await tester.pumpAndSettle();
      expect((await alexa.watchWakePlans().first).single.briefingDelaySec, 30);
    });

    testWidgets('escolher um tempo de parada esconde o seletor de atraso', (tester) async {
      await pumpApp(tester, MemoryRepository(), location: '/casa/despertar/p1', now: _now, alexa: _alexa(), size: _tall);
      expect(find.text('Falar o resumo após'), findsOneWidget);
      await tester.tap(find.byKey(const Key('music-stop-30')));
      await tester.pump();
      expect(find.text('Falar o resumo após'), findsNothing);
      expect(find.byKey(const Key('briefing-delay-10')), findsNothing);
    });
  });

  group('parar a música', () {
    testWidgets('escolher 30 s e "Só as manchetes" e salvar grava os campos', (tester) async {
      final alexa = _alexa();
      await pumpApp(tester, MemoryRepository(), location: '/casa/despertar/p1', now: _now, alexa: alexa, size: _tall);
      expect(find.text('Parar a música após'), findsOneWidget);
      expect(find.text('Depois da música'), findsOneWidget);
      await tester.tap(find.byKey(const Key('music-stop-30')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('after-music-headlines')));
      await tester.pump();
      expect(find.text('O resumo começa assim que a música parar.'), findsOneWidget);
      expect(find.byKey(const Key('briefing-delay-180')), findsNothing);
      await tester.tap(find.byKey(const Key('wake-save')));
      await tester.pumpAndSettle();
      final saved = (await alexa.watchWakePlans().first).single;
      expect(saved.musicStopAfterSec, 30);
      expect(saved.afterMusic, AfterMusic.headlines);
    });

    testWidgets('"Não parar" volta ao atraso do resumo e limpa o tempo', (tester) async {
      final alexa = _alexa(plans: const [
        WakePlan(
          id: 'p1', label: 'Aula cedo', days: [1, 2, 3, 4, 5], hour: 7, minute: 0,
          echoDeviceId: 'ECHO', spotifyQuery: 'lofi', musicStopAfterSec: 60, afterMusic: AfterMusic.end,
        ),
      ]);
      await pumpApp(tester, MemoryRepository(), location: '/casa/despertar/p1', now: _now, alexa: alexa, size: _tall);
      expect(tester.widget<ChoiceChip>(find.byKey(const Key('music-stop-60'))).selected, isTrue);
      expect(tester.widget<SegmentedButton<AfterMusic>>(find.byType(SegmentedButton<AfterMusic>)).selected, {AfterMusic.end});
      await tester.tap(find.byKey(const Key('music-stop-none')));
      await tester.pump();
      expect(find.byKey(const Key('briefing-delay-180')), findsOneWidget);
      expect(find.text('O resumo começa assim que a música parar.'), findsNothing);
      await tester.tap(find.byKey(const Key('wake-save')));
      await tester.pumpAndSettle();
      final saved = (await alexa.watchWakePlans().first).single;
      expect(saved.musicStopAfterSec, isNull);
      expect(saved.afterMusic, AfterMusic.end);
    });

    testWidgets('sem busca do Spotify o seletor de parada não aparece', (tester) async {
      final alexa = _alexa(plans: const []);
      await pumpApp(tester, MemoryRepository(), location: '/casa/despertar/novo', now: _now, alexa: alexa, size: _tall);
      await expandAdvanced(tester);
      expect(find.text('Parar a música após'), findsNothing);
      expect(find.byKey(const Key('music-stop-30')), findsNothing);
      await tester.enterText(find.byKey(const Key('wake-spotify')), 'rock');
      await tester.pump();
      expect(find.text('Parar a música após'), findsOneWidget);
      expect(find.byKey(const Key('music-stop-none')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('wake-spotify')), '  ');
      await tester.pump();
      expect(find.text('Parar a música após'), findsNothing);
    });

    testWidgets('sem busca do Spotify a opção "Encerrar" fica desabilitada; com busca, habilitada', (tester) async {
      final alexa = _alexa(plans: const []);
      await pumpApp(tester, MemoryRepository(), location: '/casa/despertar/novo', now: _now, alexa: alexa, size: _tall);
      await expandAdvanced(tester);
      bool endEnabled() => tester
          .widget<SegmentedButton<AfterMusic>>(find.byType(SegmentedButton<AfterMusic>))
          .segments
          .firstWhere((s) => s.value == AfterMusic.end)
          .enabled;
      expect(find.byKey(const Key('after-music-headlines')), findsOneWidget);
      expect(endEnabled(), isFalse);
      await tester.enterText(find.byKey(const Key('wake-spotify')), 'rock');
      await tester.pump();
      expect(endEnabled(), isTrue);
    });

    testWidgets('escolher "Encerrar" mostra o aviso de que não haverá resumo falado', (tester) async {
      await pumpApp(tester, MemoryRepository(), location: '/casa/despertar/p1', now: _now, alexa: _alexa(), size: _tall);
      const hint = 'Depois da música não haverá resumo falado.';
      expect(find.text(hint), findsNothing);
      await tester.tap(find.byKey(const Key('after-music-end')));
      await tester.pump();
      expect(find.text(hint), findsOneWidget);
      await tester.tap(find.byKey(const Key('after-music-headlines')));
      await tester.pump();
      expect(find.text(hint), findsNothing);
    });

    testWidgets('apagar a busca com "Encerrar" escolhido volta para o resumo do dia', (tester) async {
      final alexa = _alexa();
      await pumpApp(tester, MemoryRepository(), location: '/casa/despertar/p1', now: _now, alexa: alexa, size: _tall);
      await tester.tap(find.byKey(const Key('after-music-end')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('wake-spotify')), '');
      await tester.pump();
      expect(tester.widget<SegmentedButton<AfterMusic>>(find.byType(SegmentedButton<AfterMusic>)).selected, {AfterMusic.briefing});
      await tester.tap(find.byKey(const Key('wake-save')));
      await tester.pumpAndSettle();
      expect((await alexa.watchWakePlans().first).single.afterMusic, AfterMusic.briefing);
    });

    testWidgets('despertar antigo com "Encerrar" e sem busca não salva e explica o motivo', (tester) async {
      final alexa = _alexa(plans: const [
        WakePlan(
          id: 'p1', label: 'Aula cedo', days: [1, 2, 3, 4, 5], hour: 7, minute: 0,
          echoDeviceId: 'ECHO', afterMusic: AfterMusic.end,
        ),
      ]);
      await pumpApp(tester, MemoryRepository(), location: '/casa/despertar/p1', now: _now, alexa: alexa, size: _tall);
      await tester.tap(find.byKey(const Key('wake-save')));
      await tester.pumpAndSettle();
      expect(find.text('Para encerrar depois da música, escolha uma busca do Spotify.'), findsOneWidget);
      expect((await alexa.watchWakePlans().first).single.afterMusic, AfterMusic.end);
    });

    testWidgets('apagar a busca descarta o tempo de parada ao salvar', (tester) async {
      final alexa = _alexa();
      await pumpApp(tester, MemoryRepository(), location: '/casa/despertar/p1', now: _now, alexa: alexa, size: _tall);
      await tester.tap(find.byKey(const Key('music-stop-30')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('wake-spotify')), '');
      await tester.tap(find.byKey(const Key('wake-save')));
      await tester.pumpAndSettle();
      final saved = (await alexa.watchWakePlans().first).single;
      expect(saved.toMap()['spotify_query'], isNull);
      expect(saved.musicStopAfterSec, isNull);
    });

    testWidgets('com "Música primeiro" desligada o seletor "Depois da música" some', (tester) async {
      await pumpApp(tester, MemoryRepository(), location: '/casa/despertar/p1', now: _now, alexa: _alexa(), size: _tall);
      expect(find.text('Depois da música'), findsOneWidget);
      await tester.tap(find.text('Música antes do resumo'));
      await tester.pump();
      expect(find.text('Depois da música'), findsNothing);
      expect(find.byKey(const Key('after-music-end')), findsNothing);
      expect(find.byKey(const Key('briefing-delay-180')), findsNothing);
    });
  });

  testWidgets('Hoje avisa login expirado quando há despertar ativo e abre Casa', (tester) async {
    await pumpApp(
      tester,
      MemoryRepository(),
      now: _now,
      alexa: _alexa(state: BridgeState.authRequired),
    );
    expect(find.byKey(const ValueKey('system-notice-bridge')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('system-notice-bridge')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(PageHeader, 'Casa'), findsOneWidget);
  });

  testWidgets('Hoje sem despertar ativo não mostra aviso', (tester) async {
    await pumpApp(
      tester,
      MemoryRepository(),
      now: _now,
      alexa: _alexa(state: BridgeState.authRequired, plans: const []),
    );
    expect(find.byKey(const ValueKey('system-notice-bridge')), findsNothing);
  });

  testWidgets('excluir despertar confirma no diálogo e apaga o plano', (tester) async {
    final alexa = _alexa();
    await pumpApp(tester, MemoryRepository(), location: '/casa/despertar/p1', now: _now, alexa: alexa, size: _tall);
    await tester.tap(find.byKey(const Key('wake-delete')));
    await tester.pumpAndSettle();
    expect(find.text('Excluir despertar?'), findsOneWidget);
    await tester.tap(find.text('Excluir'));
    await tester.pumpAndSettle();
    expect(await alexa.watchWakePlans().first, isEmpty);
    expect(find.widgetWithText(PageHeader, 'Casa'), findsOneWidget);
  });

  testWidgets('testar despertar mostra erro quando o envio falha', (tester) async {
    final alexa = _alexa()..failWrites = true;
    await pumpApp(tester, MemoryRepository(), location: '/casa/despertar/p1', now: _now, alexa: alexa, size: _tall);
    await tester.tap(find.byKey(const Key('wake-test')));
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível enviar o comando.'), findsOneWidget);
  });

  testWidgets('Testar agora fica desabilitado com alterações não salvas', (tester) async {
    await pumpApp(tester, MemoryRepository(), location: '/casa/despertar/p1', now: _now, alexa: _alexa(), size: _tall);
    OutlinedButton btn() => tester.widget<OutlinedButton>(find.byKey(const Key('wake-test')));
    expect(btn().onPressed, isNotNull);
    await tester.enterText(find.byKey(const Key('wake-label')), 'Outro');
    await tester.pump();
    expect(btn().onPressed, isNull);
  });

  group('ocultar e remover dispositivos', () {
    Future<void> openMenu(WidgetTester tester, String id, String item) async {
      await tester.tap(find.byKey(ValueKey('device-menu-$id')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item));
      await tester.pumpAndSettle();
    }

    testWidgets('ocultar grava o ajuste, some da lista e Mostrar desfaz', (tester) async {
      final settings = MemorySettingsRepository();
      await pumpApp(
        tester,
        MemoryRepository(),
        location: '/casa',
        now: _now,
        alexa: _alexa(),
        size: _tall,
        settings: settings,
      );
      await openMenu(tester, 'luz1', 'Ocultar do app');
      expect((await settings.watchSettings().first).hiddenAlexaDevices, ['luz1']);
      expect(find.byKey(const ValueKey('device-luz1')), findsNothing);
      expect(find.byKey(const Key('hidden-devices')), findsOneWidget);
      expect(find.text('Ocultos (1)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('show-luz1')));
      await tester.pumpAndSettle();
      expect((await settings.watchSettings().first).hiddenAlexaDevices, isEmpty);
      expect(find.byKey(const ValueKey('device-luz1')), findsOneWidget);
      expect(find.byKey(const Key('hidden-devices')), findsNothing);
    });

    testWidgets('remover da Alexa pede confirmação e envia delete_device', (tester) async {
      final alexa = _alexa();
      await pumpApp(tester, MemoryRepository(), location: '/casa', now: _now, alexa: alexa, size: _tall);
      await openMenu(tester, 'luz1', 'Remover da Alexa');
      expect(
        find.text('Isso apaga “Luz do quarto” da sua conta Amazon. Não dá para desfazer pelo app.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('remove-cancel')));
      await tester.pumpAndSettle();
      expect(alexa.sent, isEmpty);
      await openMenu(tester, 'luz1', 'Remover da Alexa');
      await tester.tap(find.byKey(const Key('remove-confirm')));
      await tester.pumpAndSettle();
      expect(alexa.sent.single.kind, 'delete_device');
      expect(alexa.sent.single.payload, {'entityId': 'luz1'});
      expect(find.text('Feito.'), findsOneWidget);
    });

    testWidgets('Echo oculto some dos chips Tocar em; Echo não tem Remover da Alexa', (tester) async {
      final settings = MemorySettingsRepository(initial: const UserSettings(hiddenAlexaDevices: ['ECHO2']));
      await pumpApp(
        tester,
        MemoryRepository(),
        location: '/casa',
        now: _now,
        alexa: _alexa(),
        size: _tall,
        settings: settings,
      );
      expect(find.byKey(const ValueKey('echo-ECHO')), findsOneWidget);
      expect(find.byKey(const ValueKey('echo-ECHO2')), findsNothing);
      expect(find.text('Ocultos (1)'), findsOneWidget);
      // Echo não aparece como dispositivo com menu; só smart tem menu.
      expect(find.byKey(const ValueKey('device-menu-ECHO')), findsNothing);
    });

    testWidgets('falha ao salvar ajustes avisa e mantém o dispositivo', (tester) async {
      final settings = MemorySettingsRepository(failWrites: true);
      await pumpApp(
        tester,
        MemoryRepository(),
        location: '/casa',
        now: _now,
        alexa: _alexa(),
        size: _tall,
        settings: settings,
      );
      await openMenu(tester, 'luz1', 'Ocultar do app');
      expect(find.text('Não foi possível ocultar o dispositivo.'), findsOneWidget);
      expect(find.byKey(const ValueKey('device-luz1')), findsOneWidget);
    });
  });
}

/// "Avançado" começa fechado em despertares com valores padrão: abre antes de mexer nos controles.
Future<void> expandAdvanced(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('wake-advanced')));
  await tester.tap(find.byKey(const Key('wake-advanced')));
  await tester.pumpAndSettle();
}
