import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/space.dart';
import 'package:organizacional/domain/task_item.dart';

import '../helpers.dart';

void main() {
  testWidgets('adiciona tarefa pelo campo rápido', (tester) async {
    final repo = MemoryRepository();
    await pumpApp(tester, repo, location: '/tarefas');
    await tester.enterText(find.byKey(const Key('quick-add-todo')), 'Lista de cálculo');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Lista de cálculo'), findsOneWidget);
    expect((await repo.watchTasks().first).single.title, 'Lista de cálculo');
  });

  testWidgets('texto em branco não cria tarefa', (tester) async {
    final repo = MemoryRepository();
    await pumpApp(tester, repo, location: '/tarefas');
    await tester.enterText(find.byKey(const Key('quick-add-todo')), '   ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(await repo.watchTasks().first, isEmpty);
  });

  testWidgets('falha ao adicionar mantém o texto no campo', (tester) async {
    final repo = MemoryRepository()..failWrites = true;
    await pumpApp(tester, repo, location: '/tarefas');
    await tester.enterText(find.byKey(const Key('quick-add-todo')), 'Resumo');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível adicionar. O texto continua no campo.'), findsOneWidget);
    expect(find.text('Resumo'), findsOneWidget);
  });

  testWidgets('desktop: três colunas com contagem e arrastar muda status e completedAt',
      (tester) async {
    final repo = MemoryRepository();
    await repo.upsertTask(const TaskItem(id: 'a', title: 'Relatório'));
    await repo.upsertTask(const TaskItem(id: 'b', title: 'Lista', status: TaskStatus.doing));
    await pumpApp(tester, repo, location: '/tarefas');
    expect(find.byKey(const ValueKey('column-todo')), findsOneWidget);
    expect(find.byKey(const ValueKey('column-doing')), findsOneWidget);
    expect(find.byKey(const ValueKey('column-done')), findsOneWidget);
    expect(find.text('A fazer'), findsOneWidget);

    Future<void> drag(String id, String column) async {
      final g = await tester.startGesture(tester.getCenter(find.byKey(ValueKey('task-card-$id'))));
      await tester.pump();
      final target = tester.getCenter(find.byKey(ValueKey(column)));
      await g.moveTo(target - const Offset(0, 50));
      await tester.pump();
      await g.moveTo(target);
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
    }

    await drag('a', 'column-done');
    var a = (await repo.watchTasks().first).firstWhere((t) => t.id == 'a');
    expect(a.status, TaskStatus.done);
    expect(a.completedAt, defaultNow);

    await drag('a', 'column-todo');
    a = (await repo.watchTasks().first).firstWhere((t) => t.id == 'a');
    expect(a.status, TaskStatus.todo);
    expect(a.completedAt, isNull);
  });

  testWidgets('celular: abas com contagem e long-press move pelo menu', (tester) async {
    final repo = MemoryRepository();
    await repo.upsertTask(const TaskItem(id: 'a', title: 'Relatório'));
    await repo.upsertTask(const TaskItem(id: 'b', title: 'Lista'));
    await pumpApp(tester, repo, location: '/tarefas', size: const Size(400, 800));
    expect(find.text('A fazer 2'), findsOneWidget);
    expect(find.text('Fazendo 0'), findsOneWidget);
    expect(find.text('Feito 0'), findsOneWidget);

    await tester.longPress(find.byKey(const ValueKey('task-card-a')));
    await tester.pumpAndSettle();
    expect(find.text('Mover para…'), findsOneWidget);
    await tester.tap(find.text('Fazendo'));
    await tester.pumpAndSettle();

    expect((await repo.watchTasks().first).firstWhere((t) => t.id == 'a').status,
        TaskStatus.doing);
    expect(find.text('A fazer 1'), findsOneWidget);
    expect(find.text('Fazendo 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('task-card-a')), findsOneWidget); // aba Fazendo ativa
  });

  testWidgets('adição rápida cria tarefa no status da coluna', (tester) async {
    final repo = MemoryRepository();
    await pumpApp(tester, repo, location: '/tarefas');
    await tester.enterText(find.byKey(const Key('quick-add-doing')), 'Em andamento');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final t = (await repo.watchTasks().first).single;
    expect(t.status, TaskStatus.doing);
    expect(find.text('Em andamento'), findsOneWidget);
  });

  testWidgets('tocar no cartão abre o diálogo e salvar atualiza', (tester) async {
    final repo = MemoryRepository();
    await repo.upsertTask(const TaskItem(id: 'a', title: 'Relatório'));
    await pumpApp(tester, repo, location: '/tarefas');
    await tester.tap(find.byKey(const ValueKey('task-card-a')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('task-title')), 'Relatório final');
    await tester.enterText(find.byKey(const Key('task-description')), 'Rever tudo');
    await tester.tap(find.byKey(const Key('task-save')));
    await tester.pumpAndSettle();
    final t = (await repo.watchTasks().first).single;
    expect(t.title, 'Relatório final');
    expect(t.description, 'Rever tudo');
    expect(find.text('Relatório final'), findsOneWidget);
  });

  testWidgets('excluir pelo diálogo remove a tarefa', (tester) async {
    final repo = MemoryRepository();
    await repo.upsertTask(const TaskItem(id: 'a', title: 'Relatório'));
    await pumpApp(tester, repo, location: '/tarefas');
    await tester.tap(find.byKey(const ValueKey('task-card-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('delete-task-a')));
    await tester.pumpAndSettle();
    expect(await repo.watchTasks().first, isEmpty);
  });

  testWidgets('prazo vencido aparece em destaque de atraso e feito vem riscado',
      (tester) async {
    final repo = MemoryRepository();
    await repo.upsertTask(TaskItem(id: 'a', title: 'Relatório', dueAt: DateTime(2026, 9, 27, 23, 59)));
    await repo.upsertTask(TaskItem(
      id: 'b',
      title: 'Antiga',
      status: TaskStatus.done,
      completedAt: DateTime(2026, 9, 20),
    ));
    await pumpApp(tester, repo, location: '/tarefas');
    expect(find.textContaining('27'), findsOneWidget);
    final done = tester.widget<Text>(find.text('Antiga'));
    expect(done.style?.decoration, TextDecoration.lineThrough);
  });

  testWidgets('sair da tela antes do salvamento terminar não gera erro (guarda mounted)',
      (tester) async {
    final repo = _GatedTaskRepository();
    await pumpApp(tester, repo, location: '/tarefas');
    await tester.enterText(find.byKey(const Key('quick-add-todo')), 'Tarefa lenta');
    final gate = repo.addGate();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(); // _add() começa e fica preso aguardando o portão

    // Sai da tela antes do upsertTask terminar.
    final context = tester.element(find.byType(Scaffold).first);
    GoRouter.of(context).go('/espacos');
    await tester.pumpAndSettle();

    // Só agora o salvamento termina, com a tela de tarefas já descartada.
    gate.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('filtro por espaço mostra só as tarefas dele', (tester) async {
    final repo = MemoryRepository();
    await repo.upsertSpace(const Space(id: 's1', name: 'Cálculo I', kind: SpaceKind.materia));
    await repo.upsertTask(const TaskItem(id: 'a', title: 'Lista 1', spaceId: 's1'));
    await repo.upsertTask(const TaskItem(id: 'b', title: 'Comprar cordas'));
    await pumpApp(tester, repo, location: '/tarefas');
    expect(find.text('Comprar cordas'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Cálculo I'));
    await tester.pumpAndSettle();
    expect(find.text('Lista 1'), findsOneWidget);
    expect(find.text('Comprar cordas'), findsNothing);
  });
}

/// Repositório de teste que atrasa upsertTask até o portão ser liberado, para
/// simular uma gravação em andamento quando a tela é descartada.
class _GatedTaskRepository extends MemoryRepository {
  final _gates = <Completer<void>>[];

  Completer<void> addGate() {
    final gate = Completer<void>();
    _gates.add(gate);
    return gate;
  }

  @override
  Future<void> upsertTask(TaskItem task) async {
    if (_gates.isNotEmpty) {
      await _gates.removeAt(0).future;
    }
    return super.upsertTask(task);
  }
}
