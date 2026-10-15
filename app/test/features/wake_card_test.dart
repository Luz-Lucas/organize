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


Future<void> _enterTime(WidgetTester tester, int h, int m) async {
  await tester.tap(find.byIcon(Icons.keyboard_outlined));
  await tester.pumpAndSettle();
  final fields = find.descendant(of: find.byType(Dialog), matching: find.byType(TextField));
  await tester.enterText(fields.at(0), '$h');
  await tester.enterText(fields.at(1), '$m');
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

Future<WakePlan> _plan(MemoryAlexaRepository alexa, [String id = 'p1']) async =>
    (await alexa.watchWakePlans().first).firstWhere((p) => p.id == id);

Future<void> _menu(WidgetTester tester, String planId, String itemKey) async {
  await _tap(tester, find.byKey(Key('wake-menu-$planId')));
  await tester.tap(find.byKey(Key(itemKey)));
  await tester.pumpAndSettle();
}

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
      expect(_inCard(find.text('07:00')), findsOneWidget);
      expect(_inCard(find.text('Dias úteis')), findsOneWidget);
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
      expect(_inCard(find.text('07:00')), findsOneWidget);
      expect(_inCard(find.text('Dias úteis')), findsOneWidget);
      expect(_inCard(find.text('amanhã 05:30')), findsOneWidget);
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

    testWidgets('de madrugada, o "Só …" edita o toque de hoje, não o de amanhã', (tester) async {
      final alexa = _alexa();
      final dawn = DateTime(2026, 9, 29, 2); // terça, 02:00; Aula cedo toca às 07:00
      await pumpApp(tester, MemoryRepository(), now: dawn, size: _phone, alexa: alexa);
      expect(_inCard(find.text('Só hoje')), findsOneWidget);
      await _tap(tester, find.byKey(const Key('wake-tomorrow-p1')));
      expect(find.text('Não tocar hoje'), findsOneWidget);
      await _tap(tester, find.byKey(const Key('wake-tomorrow-skip')));
      expect(await alexa.watchOverrides().first, [WakeOverride.skip('p1', DateTime(2026, 9, 29))]);
      expect(_inCard(find.text('Hoje: pulado')), findsOneWidget);
    });

    testWidgets('o editor mostra o próximo toque considerando a exceção', (tester) async {
      final alexa = _alexa(overrides: [WakeOverride.skip('p1', _tomorrow)]);
      await pumpApp(tester, MemoryRepository(), location: '/casa/despertar/p1', now: _now, alexa: alexa, size: _phone);
      expect(find.text('Toca em 1 d 21 h'), findsOneWidget); // quarta 07:00
    });
  });


  group('editar o despertar direto no cartão', () {
    testWidgets('tocar no horário grava o novo horário padrão e oferece Desfazer', (tester) async {
      final alexa = _alexa();
      await _pump(tester, alexa, size: const Size(800, 1000));
      await _tap(tester, find.byKey(const Key('wake-time-p1')));
      await _enterTime(tester, 6, 15);
      final p = await _plan(alexa);
      expect((p.hour, p.minute), (6, 15));
      expect(p.days, [1, 2, 3, 4, 5]);
      expect(find.text('Despertar às 06:15'), findsOneWidget);
      await tester.tap(find.text('Desfazer'));
      await tester.pumpAndSettle();
      final back = await _plan(alexa);
      expect((back.hour, back.minute), (7, 0));
    });

    testWidgets('mudar o horário mantém a exceção "só amanhã" com horário', (tester) async {
      final alexa = _alexa(overrides: [WakeOverride.at('p1', _tomorrow, 5, 30)]);
      await _pump(tester, alexa, size: const Size(800, 1000));
      await _tap(tester, find.byKey(const Key('wake-time-p1')));
      await _enterTime(tester, 6, 15);
      expect(await alexa.watchOverrides().first, [WakeOverride.at('p1', _tomorrow, 5, 30)]);
      expect(_inCard(find.text('amanhã 05:30')), findsOneWidget);
    });

    testWidgets('cancelar o seletor de hora não grava nada', (tester) async {
      final alexa = _alexa();
      await _pump(tester, alexa);
      await _tap(tester, find.byKey(const Key('wake-time-p1')));
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect((await _plan(alexa)).hour, 7);
      expect(find.textContaining('Despertar às'), findsNothing);
    });

    testWidgets('falha na validação mostra a mensagem e não grava', (tester) async {
      const semEcho = WakePlan(id: 'x', label: 'Sem Echo', days: [1], hour: 7, minute: 0, echoDeviceId: '');
      final alexa = _alexa(plans: const [semEcho]);
      await _pump(tester, alexa, size: const Size(800, 1000));
      await _tap(tester, find.byKey(const Key('wake-time-x')));
      await _enterTime(tester, 6, 15);
      expect(find.text('Escolha em qual Echo tocar.'), findsOneWidget);
      expect((await _plan(alexa, 'x')).hour, 7);
    });

    testWidgets('erro de gravação ao mudar o horário avisa', (tester) async {
      final alexa = _alexa();
      await _pump(tester, alexa, size: const Size(800, 1000));
      alexa.failWrites = true;
      await _tap(tester, find.byKey(const Key('wake-time-p1')));
      await _enterTime(tester, 6, 15);
      expect(find.text('Não foi possível alterar o despertar.'), findsOneWidget);
      expect((await _plan(alexa)).hour, 7);
    });

    testWidgets('tocar nos dias abre chips Dom…Sáb e Salvar grava os dias', (tester) async {
      final alexa = _alexa();
      await _pump(tester, alexa);
      await _tap(tester, find.byKey(const Key('wake-days-p1')));
      final chips = [for (var d = 1; d <= 7; d++) find.byKey(Key('wake-days-chip-$d'))];
      for (final c in chips) {
        expect(c, findsOneWidget);
      }
      // a semana começa no domingo
      expect(tester.getTopLeft(chips[6]).dx, lessThan(tester.getTopLeft(chips[0]).dx));
      expect(tester.getTopLeft(chips[0]).dx, lessThan(tester.getTopLeft(chips[1]).dx));
      expect(find.descendant(of: chips[6], matching: find.text('Dom')), findsOneWidget);
      expect(tester.widget<FilterChip>(chips[0]).selected, isTrue);
      expect(tester.widget<FilterChip>(chips[5]).selected, isFalse);
      await _tap(tester, chips[5]); // Sáb
      await _tap(tester, find.byKey(const Key('wake-days-save')));
      expect((await _plan(alexa)).days, [1, 2, 3, 4, 5, 6]);
      expect(_inCard(find.text('Seg, Ter, Qua, Qui, Sex, Sáb')), findsOneWidget);
    });

    testWidgets('Cancelar na folha de dias não grava', (tester) async {
      final alexa = _alexa();
      await _pump(tester, alexa);
      await _tap(tester, find.byKey(const Key('wake-days-p1')));
      await _tap(tester, find.byKey(const Key('wake-days-chip-6')));
      await _tap(tester, find.byKey(const Key('wake-days-cancel')));
      expect((await _plan(alexa)).days, [1, 2, 3, 4, 5]);
      expect(find.byKey(const Key('wake-days-save')), findsNothing);
    });

    testWidgets('sem nenhum dia: "Escolha pelo menos um dia", folha continua e nada grava', (tester) async {
      final alexa = _alexa(plans: const [WakePlan(id: 'q', label: 'Um dia', days: [3], hour: 7, minute: 0, echoDeviceId: 'E')]);
      await _pump(tester, alexa);
      await _tap(tester, find.byKey(const Key('wake-days-q')));
      await _tap(tester, find.byKey(const Key('wake-days-chip-3')));
      await _tap(tester, find.byKey(const Key('wake-days-save')));
      expect(find.text('Escolha pelo menos um dia'), findsOneWidget);
      expect(find.byKey(const Key('wake-days-save')), findsOneWidget);
      expect((await _plan(alexa, 'q')).days, [3]);
    });

    testWidgets('menu: "Editar tudo…" abre o editor completo', (tester) async {
      await _pump(tester, _alexa());
      await _menu(tester, 'p1', 'wake-menu-edit');
      expect(_editorPlanId(tester), 'p1');
    });

    testWidgets('menu: "Só amanhã…" abre a folha existente', (tester) async {
      await _pump(tester, _alexa());
      await _menu(tester, 'p1', 'wake-menu-tomorrow');
      expect(find.byKey(const Key('wake-tomorrow-skip')), findsOneWidget);
    });

    testWidgets('menu: "Duplicar" cria "<nome> (cópia)" desligada, mantendo o original', (tester) async {
      final alexa = _alexa();
      await _pump(tester, alexa, size: const Size(360, 1200));
      await _menu(tester, 'p1', 'wake-menu-duplicate');
      final plans = await alexa.watchWakePlans().first;
      expect(plans, hasLength(2));
      final copy = plans.firstWhere((p) => p.id != 'p1');
      expect(copy.label, 'Aula cedo (cópia)');
      expect(copy.enabled, isFalse);
      expect((copy.hour, copy.minute, copy.echoDeviceId), (7, 0, 'E'));
      expect(copy.days, [1, 2, 3, 4, 5]);
      expect((await _plan(alexa)).enabled, isTrue);
      expect(_inCard(find.text('Aula cedo (cópia)')), findsOneWidget);
    });

    testWidgets('menu: "Excluir" pede confirmação; cancelar não exclui', (tester) async {
      final alexa = _alexa();
      await _pump(tester, alexa);
      await _menu(tester, 'p1', 'wake-menu-delete');
      expect(find.text('Excluir despertar?'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(await alexa.watchWakePlans().first, hasLength(1));
    });

    testWidgets('menu: "Excluir" confirmado remove e Desfazer devolve o despertar e suas exceções', (tester) async {
      final alexa = _alexa(overrides: [WakeOverride.skip('p1', _tomorrow)]);
      await _pump(tester, alexa);
      await _menu(tester, 'p1', 'wake-menu-delete');
      await tester.tap(find.byKey(const Key('wake-delete-confirm')));
      await tester.pumpAndSettle();
      expect(await alexa.watchWakePlans().first, isEmpty);
      expect(await alexa.watchOverrides().first, isEmpty);
      expect(_inCard(find.text('Nenhum despertar')), findsOneWidget);
      await tester.tap(find.text('Desfazer'));
      await tester.pumpAndSettle();
      expect((await _plan(alexa)).label, 'Aula cedo');
      expect(await alexa.watchOverrides().first, [WakeOverride.skip('p1', _tomorrow)]);
    });

    testWidgets('erro ao excluir avisa e mantém o despertar', (tester) async {
      final alexa = _alexa();
      await _pump(tester, alexa);
      await _menu(tester, 'p1', 'wake-menu-delete');
      alexa.failWrites = true;
      await tester.tap(find.byKey(const Key('wake-delete-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('Não foi possível excluir o despertar.'), findsOneWidget);
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


    for (final scale in [1.0, 1.3]) {
      testWidgets('alvos de toque de horário, dias e menu têm 48 dp a 360 dp com ${scale}x', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        const plans = [
          WakePlan(id: 'a', label: 'Despertar com um nome bem comprido para quebrar linha', days: [1, 2, 3, 4, 5, 6], hour: 6, minute: 45, echoDeviceId: 'E'),
          WakePlan(id: 'b', label: 'Cedo', days: [1, 2, 3, 4, 5, 6, 7], hour: 6, minute: 0, echoDeviceId: 'E'),
        ];
        await _pump(tester, _alexa(plans: plans, overrides: [WakeOverride.at('b', _tomorrow, 5, 5)]),
            size: const Size(360, 2400));
        expect(tester.takeException(), isNull);
        for (final id in ['a', 'b']) {
          for (final k in ['wake-time', 'wake-days', 'wake-menu']) {
            final rect = tester.getRect(find.byKey(Key('$k-$id')));
            expect(rect.height, greaterThanOrEqualTo(48), reason: '$k-$id altura');
            expect(rect.width, greaterThanOrEqualTo(48), reason: '$k-$id largura');
            expect(rect.right, lessThanOrEqualTo(360), reason: '$k-$id dentro da tela');
          }
        }
      });
    }

    testWidgets('no desktop vai para a coluna da esquerda, junto de "Agora e a seguir"', (tester) async {
      await _pump(tester, _alexa(), size: const Size(1200, 900));
      final left = tester.getTopLeft(find.byKey(const Key('card-now-next'))).dx;
      expect(tester.getTopLeft(find.byKey(const Key('wake-card'))).dx, left);
    });
  });

  testWidgets('dias no editor do despertar começam pelo domingo', (tester) async {
    await pumpApp(tester, MemoryRepository(), location: '/casa/despertar/p1', now: _now, alexa: _alexa(), size: _phone);
    final dom = tester.getTopLeft(find.byKey(const ValueKey('day-7')));
    final seg = tester.getTopLeft(find.byKey(const ValueKey('day-1')));
    expect(dom.dx, lessThan(seg.dx));
  });
}
