import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_alexa_repository.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/alexa.dart';

import '../helpers.dart';

final _now = DateTime(2026, 9, 28, 10); // segunda, 10:00
// Tudo no padrão de um despertar novo: "Avançado" nasce fechado.
const _plain = WakePlan(
  id: 'p1', label: 'Aula cedo', days: [1, 2, 3, 4, 5], hour: 7, minute: 0,
  echoDeviceId: 'ECHO', spotifyQuery: 'lofi', briefingDelaySec: 10,
);

MemoryAlexaRepository _alexa({List<WakePlan> plans = const [_plain]}) => MemoryAlexaRepository(
      status: BridgeStatus(state: BridgeState.ok, lastSeen: _now),
      devices: const [
        AlexaDevice(id: 'ECHO', name: 'Echo do quarto', kind: 'echo'),
        AlexaDevice(id: 'luz1', name: 'Luz do quarto', kind: 'smart', operations: ['turnOn', 'turnOff', 'setBrightness']),
      ],
      plans: plans,
    );

Future<void> _open(WidgetTester tester, MemoryAlexaRepository alexa,
        {String id = 'p1', Size size = const Size(360, 1600)}) =>
    pumpApp(tester, MemoryRepository(), location: '/casa/despertar/$id', now: _now, alexa: alexa, size: size);

bool _expanded(WidgetTester tester) =>
    find.byKey(const Key('wake-fallback')).evaluate().isNotEmpty;

void main() {
  group('barra de salvar fixa', () {
    testWidgets('Salvar fica na barra inferior, largura total, mesmo com a lista rolada', (tester) async {
      await _open(tester, _alexa(), size: const Size(360, 640));
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).last);
      expect(scaffold.bottomNavigationBar, isNotNull);
      final bar = find.descendant(of: find.byWidget(scaffold.bottomNavigationBar!), matching: find.byKey(const Key('wake-save')));
      expect(bar, findsOneWidget);
      final rect = tester.getRect(find.byKey(const Key('wake-save')));
      expect(rect.width, 360 - 32);
      expect(rect.bottom, lessThanOrEqualTo(640));

      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(const Key('wake-save'))), rect);
    });

    testWidgets('salvar continua gravando o plano', (tester) async {
      final alexa = _alexa();
      await _open(tester, alexa);
      await tester.tap(find.byKey(const Key('wake-save')));
      await tester.pumpAndSettle();
      expect((await alexa.watchWakePlans().first).single, _plain);
    });

    testWidgets('"Testar agora" desabilitado explica "Salve para testar"', (tester) async {
      await _open(tester, _alexa());
      expect(find.text('Salve para testar'), findsNothing);
      expect(tester.widget<OutlinedButton>(find.byKey(const Key('wake-test'))).onPressed, isNotNull);
      await tester.enterText(find.byKey(const Key('wake-label')), 'Aula tarde');
      await tester.pump();
      expect(tester.widget<OutlinedButton>(find.byKey(const Key('wake-test'))).onPressed, isNull);
      expect(find.text('Salve para testar'), findsOneWidget);
    });
  });

  group('Avançado', () {
    testWidgets('despertar novo: topo visível e avançado fechado', (tester) async {
      await _open(tester, _alexa(plans: const []), id: 'novo');
      for (final k in ['wake-label', 'wake-time', 'day-1', 'wake-spotify']) {
        expect(find.byKey(Key(k)).evaluate().isNotEmpty || find.byKey(ValueKey(k)).evaluate().isNotEmpty, isTrue, reason: k);
      }
      expect(find.byKey(const ValueKey('echo-ECHO')), findsOneWidget);
      expect(find.text('Avançado'), findsOneWidget);
      expect(_expanded(tester), isFalse);
      expect(find.byKey(const Key('weather-switch')), findsNothing);
      expect(find.byKey(const Key('briefing-delay-10')), findsNothing);
    });

    testWidgets('plano padrão abre fechado; tocar abre todos os controles avançados', (tester) async {
      await _open(tester, _alexa());
      expect(_expanded(tester), isFalse);
      await tester.tap(find.byKey(const Key('wake-advanced')));
      await tester.pumpAndSettle();
      for (final k in ['music-stop-none', 'after-music-briefing', 'briefing-delay-10', 'wake-fallback', 'weather-switch', 'device-action-add']) {
        await tester.ensureVisible(find.byKey(Key(k)));
        expect(find.byKey(Key(k)), findsOneWidget, reason: k);
      }
      expect(find.textContaining('Volume'), findsOneWidget);
    });

    testWidgets('plano com valor fora do padrão abre expandido', (tester) async {
      await _open(tester, _alexa(plans: [_plain.copyWith(volume: 60)]));
      expect(_expanded(tester), isTrue);
      await _open(tester, _alexa(plans: [_plain.copyWith(includeWeather: false)]));
      expect(_expanded(tester), isTrue);
      await _open(tester, _alexa(plans: [_plain.copyWith(musicStopAfterSec: 30)]));
      expect(_expanded(tester), isTrue);
    });

    testWidgets('erro de validação de campo avançado reabre a seção', (tester) async {
      const a = WakeDeviceAction(entityId: 'luz1', name: 'Luz do quarto', action: WakeActionType.turnOn);
      await _open(tester, _alexa(plans: [_plain.copyWith(deviceActions: const [a, a])]));
      expect(_expanded(tester), isTrue);
      await tester.ensureVisible(find.byKey(const Key('wake-advanced')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Avançado')); // fecha à mão
      await tester.pumpAndSettle();
      expect(_expanded(tester), isFalse);

      await tester.tap(find.byKey(const Key('wake-save')));
      await tester.pumpAndSettle();
      expect(find.text('Cada dispositivo só pode aparecer uma vez no despertar.'), findsOneWidget);
      expect(_expanded(tester), isTrue);
    });

    testWidgets('erro de nome não abre o avançado', (tester) async {
      await _open(tester, _alexa());
      await tester.enterText(find.byKey(const Key('wake-label')), '  ');
      await tester.tap(find.byKey(const Key('wake-save')));
      await tester.pumpAndSettle();
      expect(find.text('Dê um nome ao despertar.'), findsOneWidget);
      expect(_expanded(tester), isFalse);
    });
  });

  group('"Toca em…"', () {
    testWidgets('mostra o tempo até a próxima vez e some sem dias', (tester) async {
      await _open(tester, _alexa());
      expect(find.byKey(const Key('wake-next')), findsOneWidget);
      expect(find.text('Toca em 21 h'), findsOneWidget); // terça, 7:00
      for (var d = 1; d <= 5; d++) {
        await tester.tap(find.byKey(ValueKey('day-$d')));
      }
      await tester.pump();
      expect(find.byKey(const Key('wake-next')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('day-1')));
      await tester.pump();
      expect(find.text('Toca em 6 d 21 h'), findsOneWidget);
    });
  });

  group('fonte grande em 360 dp', () {
    testWidgets('editor sem estouro com 1,3x, fechado e aberto', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      const a = WakeDeviceAction(entityId: 'luz1', name: 'Luz do quarto', action: WakeActionType.setBrightness, brightness: 40);
      final plan = _plain.copyWith(
        volume: 60,
        musicStopAfterSec: null,
        afterMusic: AfterMusic.headlines,
        deviceActions: const [a],
      );
      await _open(tester, _alexa(plans: [plan]), size: const Size(360, 3600));
      expect(_expanded(tester), isTrue);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('wake-advanced')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
