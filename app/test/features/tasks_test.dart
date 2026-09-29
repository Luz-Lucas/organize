import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/space.dart';
import 'package:organizacional/domain/task_item.dart';

import '../helpers.dart';

void main() {
  testWidgets('adiciona tarefa pelo campo rápido', (tester) async {
    final repo = MemoryRepository();
    await pumpApp(tester, repo, location: '/tarefas');
    await tester.enterText(find.byKey(const Key('quick-add')), 'Lista de cálculo');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Sem data'), findsOneWidget);
    expect(find.text('Lista de cálculo'), findsOneWidget);
    expect((await repo.watchTasks().first).single.title, 'Lista de cálculo');
  });

  testWidgets('texto em branco não cria tarefa', (tester) async {
    final repo = MemoryRepository();
    await pumpApp(tester, repo, location: '/tarefas');
    await tester.enterText(find.byKey(const Key('quick-add')), '   ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(await repo.watchTasks().first, isEmpty);
  });

  testWidgets('falha ao adicionar mantém o texto no campo', (tester) async {
    final repo = MemoryRepository()..failWrites = true;
    await pumpApp(tester, repo, location: '/tarefas');
    await tester.enterText(find.byKey(const Key('quick-add')), 'Resumo');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível adicionar. O texto continua no campo.'), findsOneWidget);
    expect(find.text('Resumo'), findsOneWidget);
  });

  testWidgets('agrupa atrasadas, esconde concluídas e conclui pela caixa', (tester) async {
    final repo = MemoryRepository();
    await repo.upsertTask(TaskItem(id: 'a', title: 'Relatório', dueAt: DateTime(2026, 9, 27, 23, 59)));
    await repo.upsertTask(TaskItem(
      id: 'b',
      title: 'Antiga',
      status: TaskStatus.done,
      completedAt: DateTime(2026, 9, 20),
    ));
    await pumpApp(tester, repo, location: '/tarefas');
    expect(find.text('Atrasadas'), findsOneWidget);
    expect(find.text('Relatório'), findsOneWidget);
    expect(find.text('Antiga'), findsNothing);

    await tester.tap(find.byKey(const Key('show-done')));
    await tester.pumpAndSettle();
    expect(find.text('Antiga'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('task-check-a')));
    await tester.pumpAndSettle();
    expect(find.text('Atrasadas'), findsNothing);
    expect(find.text('Concluídas'), findsOneWidget);
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
