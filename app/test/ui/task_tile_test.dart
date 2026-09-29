import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/app/providers.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/task_item.dart';
import 'package:organizacional/ui/task_tile.dart';

void main() {
  const task = TaskItem(id: 't1', title: 'Lista 1');
  final now = DateTime(2026, 9, 28, 10);

  Future<MemoryRepository> pump(WidgetTester tester) async {
    final repo = MemoryRepository();
    await repo.upsertTask(task);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        clockProvider.overrideWithValue(() => now),
      ],
      child: const MaterialApp(home: Scaffold(body: TaskTile(task: task))),
    ));
    return repo;
  }

  testWidgets('marcar a caixa conclui a tarefa com a hora atual', (tester) async {
    final repo = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('task-check-t1')));
    await tester.pump();
    final saved = (await repo.watchTasks().first).single;
    expect(saved.isDone, isTrue);
    expect(saved.completedAt, now);
  });

  testWidgets('falha ao salvar mostra aviso', (tester) async {
    final repo = await pump(tester);
    repo.failWrites = true;
    await tester.tap(find.byKey(const ValueKey('task-check-t1')));
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível atualizar a tarefa.'), findsOneWidget);
  });

  testWidgets('botão de excluir remove a tarefa', (tester) async {
    final repo = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('delete-task-t1')));
    await tester.pumpAndSettle();
    expect(await repo.watchTasks().first, isEmpty);
  });

  testWidgets('falha ao excluir mostra aviso em pt-BR', (tester) async {
    final repo = await pump(tester);
    repo.failWrites = true;
    await tester.tap(find.byKey(const ValueKey('delete-task-t1')));
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível excluir a tarefa.'), findsOneWidget);
    expect(await repo.watchTasks().first, hasLength(1));
  });
}
