import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_alexa_repository.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/alexa.dart';
import 'package:organizacional/domain/wake_override.dart';
import 'package:organizacional/features/home/wake_plan_screen.dart';

import '../helpers.dart';

const _phone = Size(360, 900);
final _now = DateTime(2026, 9, 28, 10); // segunda-feira, 10:00
final _tomorrow = DateTime(2026, 9, 29);

const _aula = WakePlan(
  id: 'p1', label: 'Aula cedo', days: [1, 2, 3, 4, 5], hour: 7, minute: 0, echoDeviceId: 'E',
);
const _fim = WakePlan(
  id: 'p2', label: 'Fim de semana', days: [6, 7], hour: 9, minute: 30, echoDeviceId: 'E',
);

MemoryAlexaRepository _alexa({List<WakePlan> plans = const [_aula], List<WakeOverride> overrides = const []}) {
  final repo = MemoryAlexaRepository(plans: plans);
  for (final o in overrides) {
    repo.setOverride(o);
  }
  return repo;
}

/// Id do despertar aberto no editor (`push` não muda a URL do roteador nos testes).
String? _editorPlanId(WidgetTester tester) =>
    find.byType(WakePlanScreen).evaluate().map((e) => (e.widget as WakePlanScreen).planId).firstOrNull;

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _pump(WidgetTester tester, MemoryAlexaRepository alexa, {Size size = _phone}) =>
    pumpApp(tester, MemoryRepository(), now: _now, size: size, alexa: alexa);

Finder _inCard(Finder f) => find.descendant(of: find.byKey(const Key('wake-card')), matching: f);

void main() {
  group('cartão Despertares na Início', () {
    testWidgets('aparece logo depois de "Agora e a seguir" e resume o despertar', (tester) async {
      await _pump(tester, _alexa());
      final nowNext = tester.getTopLeft(find.byKey(const Key('card-now-next'))).dy;
      final wake = tester.getTopLeft(find.byKey(const Key('wake-card'))).dy;
      expect(wake, greaterThan(nowNext));
      // nada entre os dois: o cartão de tarefas fica depois
      expect(tester.getTopLeft(find.byKey(const Key('card-tasks'))).dy, greaterThan(wake));
      expect(_inCard(find.text('Aula cedo')), findsOneWidget);
      expect(_inCard(find.text('07:00 · Dias úteis')), findsOneWidget);
      expect(_inCard(find.text('Toca amanhã às 07:00 · em 21 h')), findsOneWidget);
      expect(tester.widget<Switch>(find.byKey(const Key('wake-toggle-p1'))).value, isTrue);
    });

    testWidgets('sem despertares: "Nenhum despertar" e botão para criar', (tester) async {
      await _pump(tester, _alexa(plans: const []));
      expect(_inCard(find.text('Nenhum despertar')), findsOneWidget);
      await _tap(tester, find.byKey(const Key('wake-new')));
      expect(_editorPlanId(tester), 'novo');
    });

    testWidgets('o botão "Novo despertar" também existe com despertares', (tester) async {
      await _pump(tester, _alexa());
      await _tap(tester, find.byKey(const Key('wake-new')));
      expect(_editorPlanId(tester), 'novo');
    });

    testWidgets('tocar na linha abre o editor do despertar', (tester) async {
      await _pump(tester, _alexa());
      await _tap(tester, _inCard(find.text('Aula cedo')));
      expect(_editorPlanId(tester), 'p1');
    });

    testWidgets('ligar e desligar grava enabled; desligado mostra "Desligado"', (tester) async {
      final alexa = _alexa();
      await _pump(tester, alexa);
      await _tap(tester, find.byKey(const Key('wake-toggle-p1')));
      expect((await alexa.watchWakePlans().first).single.enabled, isFalse);
      expect(_inCard(find.text('Desligado')), findsOneWidget);
      expect(_inCard(find.textContaining('Toca')), findsNothing);
      await _tap(tester, find.byKey(const Key('wake-toggle-p1')));
      expect((await alexa.watchWakePlans().first).single.enabled, isTrue);
      expect(_inCard(find.text('Toca amanhã às 07:00 · em 21 h')), findsOneWidget);
    });

    testWidgets('falha ao gravar o interruptor mostra aviso e não muda', (tester) async {
      final alexa = _alexa();
      await _pump(tester, alexa);
      alexa.failWrites = true;
      await _tap(tester, find.byKey(const Key('wake-toggle-p1')));
      expect(find.text('Não foi possível alterar o despertar.'), findsOneWidget);
      expect(tester.widget<Switch>(find.byKey(const Key('wake-toggle-p1'))).value, isTrue);
    });

    testWidgets('mostra até 4: ativos primeiro, pelo próximo toque; desligados no fim', (tester) async {
      const plans = [
        WakePlan(id: 'a', label: 'Tarde', days: [1, 2, 3, 4, 5, 6, 7], hour: 18, minute: 0, echoDeviceId: 'E'), // hoje 18:00
        WakePlan(id: 'b', label: 'Cedo', days: [1, 2, 3, 4, 5, 6, 7], hour: 6, minute: 0, echoDeviceId: 'E'), // amanhã 06:00
        WakePlan(id: 'c', label: 'Desligado1', days: [1, 2, 3, 4, 5, 6, 7], hour: 5, minute: 0, echoDeviceId: 'E', enabled: false),
        WakePlan(id: 'd', label: 'Meio', days: [1, 2, 3, 4, 5, 6, 7], hour: 12, minute: 0, echoDeviceId: 'E'), // hoje 12:00
        WakePlan(id: 'e', label: 'Quinto', days: [1, 2, 3, 4, 5, 6, 7], hour: 23, minute: 0, echoDeviceId: 'E'), // hoje 23:00
      ];
      await _pump(tester, _alexa(plans: plans), size: const Size(360, 1800));
      final tops = {
        for (final id in ['a', 'b', 'c', 'd', 'e'])
          id: find.byKey(Key('wake-toggle-$id')).evaluate().isEmpty
              ? null
              : tester.getTopLeft(find.byKey(Key('wake-toggle-$id'))).dy,
      };
      // ativos: d (12:00) < a (18:00) < e (23:00) < b (amanhã 06:00); c (desligado) não cabe nos 4
      expect(tops['c'], isNull);
      final order = ['d', 'a', 'e', 'b'];
      for (var i = 0; i < order.length - 1; i++) {
        expect(tops[order[i]], isNotNull, reason: order[i]);
        expect(tops[order[i]]!, lessThan(tops[order[i + 1]]!), reason: '${order[i]} antes de ${order[i + 1]}');
      }
    });

    testWidgets('desligados vêm depois dos ativos quando cabem', (tester) async {
      const off = WakePlan(id: 'c', label: 'Antigo', days: [1], hour: 5, minute: 0, echoDeviceId: 'E', enabled: false);
      await _pump(tester, _alexa(plans: const [off, _aula]), size: const Size(360, 1200));
      expect(tester.getTopLeft(find.byKey(const Key('wake-toggle-p1'))).dy,
          lessThan(tester.getTopLeft(find.byKey(const Key('wake-toggle-c'))).dy));
    });
  });

  group('"Só amanhã"', () {
    testWidgets('Não tocar amanhã grava o pulo da data de amanhã e mostra "Amanhã: pulado"', (tester) async {
      final alexa = _alexa();
      await _pump(tester, alexa);
      await _tap(tester, find.byKey(const Key('wake-tomorrow-p1')));
      expect(find.byKey(const Key('wake-tomorrow-reset')), findsNothing); // sem exceção ainda
      await _tap(tester, find.byKey(const Key('wake-tomorrow-skip')));
      expect(await alexa.watchOverrides().first, [WakeOverride.skip('p1', _tomorrow)]);
      expect(_inCard(find.text('Amanhã: pulado')), findsOneWidget);
    });

    testWidgets('Voltar ao normal limpa a exceção de amanhã', (tester) async {
      final alexa = _alexa(overrides: [WakeOverride.skip('p1', _tomorrow)]);
      await _pump(tester, alexa);
      expect(_inCard(find.text('Amanhã: pulado')), findsOneWidget);
      await _tap(tester, find.byKey(const Key('wake-tomorrow-p1')));
      await _tap(tester, find.byKey(const Key('wake-tomorrow-reset')));
      expect(await alexa.watchOverrides().first, isEmpty);
      expect(_inCard(find.text('Toca amanhã às 07:00 · em 21 h')), findsOneWidget);
    });

    testWidgets('exceção de horário aparece no horário e no texto de amanhã', (tester) async {
      final alexa = _alexa(overrides: [WakeOverride.at('p1', _tomorrow, 5, 30)]);
      await _pump(tester, alexa);
      expect(_inCard(find.text('07:00 · Dias úteis · amanhã 05:30')), findsOneWidget);
      expect(_inCard(find.text('Toca amanhã às 05:30 · em 19 h 30 min')), findsOneWidget);
    });

    testWidgets('Mudar horário só amanhã abre o relógio e grava o novo horário', (tester) async {
      final alexa = _alexa();
      await _pump(tester, alexa, size: const Size(800, 1000));
      await _tap(tester, find.byKey(const Key('wake-tomorrow-p1')));
      await _tap(tester, find.byKey(const Key('wake-tomorrow-time')));
      // modo teclado do seletor de horas
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await tester.pumpAndSettle();
      final fields = find.descendant(of: find.byType(Dialog), matching: find.byType(TextField));
      expect(fields, findsNWidgets(2));
      await tester.enterText(fields.at(0), '6');
      await tester.enterText(fields.at(1), '15');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(await alexa.watchOverrides().first, [WakeOverride.at('p1', _tomorrow, 6, 15)]);
      expect(_inCard(find.text('Toca amanhã às 06:15 · em 20 h 15 min')), findsOneWidget);
    });

    testWidgets('cancelar o relógio não grava nada', (tester) async {
      final alexa = _alexa();
      await _pump(tester, alexa);
      await _tap(tester, find.byKey(const Key('wake-tomorrow-p1')));
      await _tap(tester, find.byKey(const Key('wake-tomorrow-time')));
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(await alexa.watchOverrides().first, isEmpty);
    });

    testWidgets('despertar de fim de semana: amanhã (terça) pode ganhar um toque extra', (tester) async {
      final alexa = _alexa(plans: const [_fim], overrides: [WakeOverride.at('p2', _tomorrow, 8, 0)]);
      await _pump(tester, alexa);
      expect(_inCard(find.text('Toca amanhã às 08:00 · em 22 h')), findsOneWidget);
    });

    testWidgets('erro ao gravar a exceção avisa', (tester) async {
      final alexa = _alexa();
      await _pump(tester, alexa);
      alexa.failWrites = true;
      await _tap(tester, find.byKey(const Key('wake-tomorrow-p1')));
      await _tap(tester, find.byKey(const Key('wake-tomorrow-skip')));
      expect(find.text('Não foi possível gravar a exceção.'), findsOneWidget);
    });

    testWidgets('o editor mostra o próximo toque considerando a exceção', (tester) async {
      final alexa = _alexa(overrides: [WakeOverride.skip('p1', _tomorrow)]);
      await pumpApp(tester, MemoryRepository(), location: '/casa/despertar/p1', now: _now, alexa: alexa, size: _phone);
      expect(find.text('Toca em 1 d 21 h'), findsOneWidget); // quarta 07:00
    });
  });

  group('layout', () {
    for (final scale in [1.0, 1.3]) {
      testWidgets('360 dp com texto em ${scale}x, com 4 despertares e exceções, sem estouro', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        const plans = [
          WakePlan(id: 'a', label: 'Despertar com um nome bem comprido para quebrar linha', days: [1, 3, 5], hour: 6, minute: 45, echoDeviceId: 'E'),
          WakePlan(id: 'b', label: 'Cedo', days: [1, 2, 3, 4, 5, 6, 7], hour: 6, minute: 0, echoDeviceId: 'E'),
          WakePlan(id: 'c', label: 'Desligado', days: [6], hour: 5, minute: 0, echoDeviceId: 'E', enabled: false),
          WakePlan(id: 'd', label: 'Meio', days: [2, 4], hour: 12, minute: 0, echoDeviceId: 'E'),
        ];
        await _pump(tester, _alexa(plans: plans, overrides: [
          WakeOverride.skip('a', _tomorrow),
          WakeOverride.at('b', _tomorrow, 5, 5),
        ]), size: const Size(360, 2400));
        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.byKey(const Key('wake-card'))).width, lessThanOrEqualTo(360));
        for (final id in ['a', 'b', 'c', 'd']) {
          expect(find.byKey(Key('wake-toggle-$id')), findsOneWidget);
          final rect = tester.getRect(find.byKey(Key('wake-tomorrow-$id')));
          expect(rect.height, greaterThanOrEqualTo(48), reason: 'área de toque de $id');
          expect(rect.right, lessThanOrEqualTo(360));
        }
      });
    }

    testWidgets('no desktop vai para a coluna da esquerda, junto de "Agora e a seguir"', (tester) async {
      await _pump(tester, _alexa(), size: const Size(1200, 900));
      final left = tester.getTopLeft(find.byKey(const Key('card-now-next'))).dx;
      expect(tester.getTopLeft(find.byKey(const Key('wake-card'))).dx, left);
    });
  });
}
