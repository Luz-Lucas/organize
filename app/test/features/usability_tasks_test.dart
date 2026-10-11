import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/space.dart';
import 'package:organizacional/domain/task_item.dart';

import '../helpers.dart';

const _phone = Size(400, 800);

Future<TaskItem> _task(MemoryRepository repo, String id) async =>
    (await repo.watchTasks().first).firstWhere((t) => t.id == id);

void main() {
  group('concluir com um toque', () {
    testWidgets('conclui, avisa e Desfazer restaura o status anterior', (tester) async {
      final repo = MemoryRepository();
      await repo.upsertTask(const TaskItem(id: 'a', title: 'Relatório', status: TaskStatus.doing));
      await pumpApp(tester, repo, location: '/tarefas', size: _phone);
      await tester.tap(find.text('Fazendo 1'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('task-done-a')));
      await tester.pumpAndSettle();
      final done = await _task(repo, 'a');
      expect(done.status, TaskStatus.done);
      expect(done.completedAt, defaultNow);
      expect(find.text('Tarefa concluída'), findsOneWidget);

      await tester.tap(find.text('Desfazer'));
      await tester.pumpAndSettle();
      final back = await _task(repo, 'a');
      expect(back.status, TaskStatus.doing);
      expect(back.completedAt, isNull);
    });

    testWidgets('em "Feito" o botão reabre a tarefa (volta para A fazer)', (tester) async {
      final repo = MemoryRepository();
      await repo.upsertTask(TaskItem(
        id: 'b',
        title: 'Antiga',
        status: TaskStatus.done,
        completedAt: DateTime(2026, 9, 20),
      ));
      await pumpApp(tester, repo, location: '/tarefas', size: _phone);
      await tester.tap(find.text('Feito 1'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_circle), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('task-done-b')));
      await tester.pumpAndSettle();
      final t = await _task(repo, 'b');
      expect([t.status, t.completedAt], [TaskStatus.todo, isNull]);
    });

    testWidgets('o botão tem 48 dp no celular', (tester) async {
      final repo = MemoryRepository();
      await repo.upsertTask(const TaskItem(id: 'a', title: 'Relatório'));
      await pumpApp(tester, repo, location: '/tarefas', size: const Size(360, 700));
      final size = tester.getSize(find.byKey(const ValueKey('task-done-a')));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    });

    testWidgets('cartão concluído usa tachado e cor apagada, sem Opacity', (tester) async {
      final repo = MemoryRepository();
      await repo.upsertTask(TaskItem(
        id: 'b',
        title: 'Antiga',
        status: TaskStatus.done,
        completedAt: DateTime(2026, 9, 20),
      ));
      await pumpApp(tester, repo, location: '/tarefas');
      expect(
        find.descendant(of: find.byKey(const ValueKey('task-card-b')), matching: find.byType(Opacity)),
        findsNothing,
      );
      final text = tester.widget<Text>(find.text('Antiga'));
      expect(text.style?.decoration, TextDecoration.lineThrough);
    });
  });

  group('desfazer exclusão', () {
    testWidgets('excluir pelo diálogo mostra "Tarefa excluída" e Desfazer recria', (tester) async {
      final repo = MemoryRepository();
      const original = TaskItem(id: 'a', title: 'Relatório', priority: TaskPriority.alta);
      await repo.upsertTask(original);
      await pumpApp(tester, repo, location: '/tarefas');
      await tester.tap(find.byKey(const ValueKey('task-card-a')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('delete-task-a')));
      await tester.pumpAndSettle();
      expect(await repo.watchTasks().first, isEmpty);
      expect(find.text('Tarefa excluída'), findsOneWidget);

      await tester.tap(find.text('Desfazer'));
      await tester.pumpAndSettle();
      expect(await repo.watchTasks().first, [original]);
    });
  });

  group('prazo rápido', () {
    Future<void> choose(WidgetTester tester, String item) async {
      await tester.tap(find.byKey(const Key('quick-due-todo')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item));
      await tester.pumpAndSettle();
    }

    Finder label(String text) =>
        find.descendant(of: find.byKey(const Key('quick-due-todo')), matching: find.text(text));

    testWidgets('menu oferece Hoje, Amanhã, Próxima segunda e Escolher data…', (tester) async {
      await pumpApp(tester, MemoryRepository(), location: '/tarefas');
      await tester.tap(find.byKey(const Key('quick-due-todo')));
      await tester.pumpAndSettle();
      for (final t in ['Hoje', 'Amanhã', 'Próxima segunda', 'Escolher data…']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
    });

    testWidgets('Hoje, Amanhã e Próxima segunda definem o prazo às 23:59', (tester) async {
      final repo = MemoryRepository();
      await pumpApp(tester, repo, location: '/tarefas'); // segunda, 28/09
      await choose(tester, 'Hoje');
      expect(label('hoje'), findsOneWidget);
      await choose(tester, 'Amanhã');
      expect(label('amanhã'), findsOneWidget);
      await choose(tester, 'Próxima segunda');
      expect(label('5 out'), findsOneWidget); // hoje é segunda: a próxima é daqui a 7 dias
      await tester.enterText(find.byKey(const Key('quick-add-todo')), 'Entrega');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect((await repo.watchTasks().first).single.dueAt, DateTime(2026, 10, 5, 23, 59));
      expect(label('Sem prazo'), findsOneWidget);
    });
  });

  group('celular x computador', () {
    testWidgets('subtítulo muda conforme a largura', (tester) async {
      await pumpApp(tester, MemoryRepository(), location: '/tarefas', size: _phone);
      expect(find.text('Segure um cartão para mover'), findsOneWidget);
      expect(find.text('Arraste os cartões entre as colunas'), findsNothing);
    });

    testWidgets('computador mantém "Arraste…"', (tester) async {
      await pumpApp(tester, MemoryRepository(), location: '/tarefas');
      expect(find.text('Arraste os cartões entre as colunas'), findsOneWidget);
    });

    testWidgets('editar no celular abre folha de baixo com status; no computador, diálogo', (tester) async {
      final repo = MemoryRepository();
      await repo.upsertTask(const TaskItem(id: 'a', title: 'Relatório'));
      await pumpApp(tester, repo, location: '/tarefas', size: _phone);
      await tester.tap(find.byKey(const ValueKey('task-card-a')));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(const Key('task-status-doing')), findsOneWidget);

      await tester.tap(find.byKey(const Key('task-status-done')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('task-save')));
      await tester.pumpAndSettle();
      final t = await _task(repo, 'a');
      expect([t.status, t.completedAt], [TaskStatus.done, defaultNow]);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('criar no celular (Mais opções) usa a folha de baixo', (tester) async {
      final repo = MemoryRepository();
      await pumpApp(tester, repo, location: '/tarefas', size: _phone);
      await tester.tap(find.byKey(const Key('quick-more-todo')));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('Nova tarefa'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('task-title')), 'Projeto');
      await tester.tap(find.byKey(const Key('task-save')));
      await tester.pumpAndSettle();
      expect((await repo.watchTasks().first).single.title, 'Projeto');
    });

    testWidgets('computador abre diálogo, sem seletor de status', (tester) async {
      final repo = MemoryRepository();
      await repo.upsertTask(const TaskItem(id: 'a', title: 'Relatório'));
      await pumpApp(tester, repo, location: '/tarefas');
      await tester.tap(find.byKey(const ValueKey('task-card-a')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byKey(const Key('task-status-done')), findsNothing);
    });

    testWidgets('alvos de toque do campo rápido têm 48 dp no celular', (tester) async {
      await pumpApp(tester, MemoryRepository(), location: '/tarefas', size: const Size(360, 700));
      for (final k in ['quick-priority-todo', 'quick-due-todo', 'quick-more-todo']) {
        expect(tester.getSize(find.byKey(Key(k))).height, greaterThanOrEqualTo(48), reason: k);
      }
    });

    testWidgets('no computador os chips continuam compactos', (tester) async {
      await pumpApp(tester, MemoryRepository(), location: '/tarefas');
      expect(tester.getSize(find.byKey(const Key('quick-due-todo'))).height, lessThan(48));
    });

    testWidgets('segurar o cartão avisa com vibração e abre "Mover para…"', (tester) async {
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') calls.add('${call.arguments}');
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      final repo = MemoryRepository();
      await repo.upsertTask(const TaskItem(id: 'a', title: 'Relatório'));
      await pumpApp(tester, repo, location: '/tarefas', size: _phone);
      await tester.longPress(find.byKey(const ValueKey('task-card-a')));
      await tester.pumpAndSettle();
      expect(find.text('Mover para…'), findsOneWidget);
      expect(calls, contains('HapticFeedbackType.mediumImpact'));
    });
  });

  group('filtro de espaço', () {
    testWidgets('sobrevive à troca de aba e rola na horizontal', (tester) async {
      final repo = MemoryRepository();
      await repo.upsertSpace(const Space(id: 's1', name: 'Cálculo I', kind: SpaceKind.materia));
      await repo.upsertSpace(const Space(id: 's2', name: 'Redes de computadores', kind: SpaceKind.materia, position: 1));
      await repo.upsertTask(const TaskItem(id: 'a', title: 'Lista 1', spaceId: 's1'));
      await repo.upsertTask(const TaskItem(id: 'b', title: 'Comprar cordas'));
      await pumpApp(tester, repo, location: '/tarefas', size: const Size(360, 700));
      final row = tester.widget<SingleChildScrollView>(find.byKey(const Key('space-filter')));
      expect(row.scrollDirection, Axis.horizontal);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Cálculo I'));
      await tester.pumpAndSettle();
      expect(find.text('Comprar cordas'), findsNothing);

      GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/agenda');
      await tester.pumpAndSettle();
      GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/tarefas');
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Cálculo I')).selected, isTrue);
      expect(find.text('Lista 1'), findsOneWidget);
      expect(find.text('Comprar cordas'), findsNothing);
    });
  });

  group('textos longos e fonte grande', () {
    testWidgets('cartão com título longo, selos e fonte 1,3x cabe em 360 dp', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final repo = MemoryRepository();
      await repo.upsertSpace(const Space(id: 's1', name: 'Redes de computadores', kind: SpaceKind.materia));
      await repo.upsertTask(TaskItem(
        id: 'a',
        title: 'Estudar para a prova de redes de computadores incluindo camadas de enlace, rede e transporte e revisar todas as listas',
        priority: TaskPriority.alta,
        spaceId: 's1',
        noteId: 'n1',
        dueAt: DateTime(2026, 9, 27, 23, 59),
      ));
      await pumpApp(tester, repo, location: '/tarefas', size: const Size(360, 700));
      expect(tester.takeException(), isNull);
      final title = tester.widget<Text>(find.textContaining('Estudar para a prova'));
      expect(title.maxLines, 3);
      expect(title.overflow, TextOverflow.ellipsis);
      expect(find.text('atrasada · 1 d'), findsOneWidget);
    });
  });
}
