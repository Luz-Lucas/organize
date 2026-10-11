import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/space.dart';
import 'package:organizacional/domain/task_item.dart';
import 'package:organizacional/ui/org_widgets.dart';

import '../helpers.dart';

void main() {
  _tasksPriorityTests();

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

  testWidgets('desktop: três colunas com contagem e arrastar muda status e completedAt', (
    tester,
  ) async {
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

    expect((await repo.watchTasks().first).firstWhere((t) => t.id == 'a').status, TaskStatus.doing);
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

  testWidgets('prazo vencido aparece em destaque de atraso e feito vem riscado', (tester) async {
    final repo = MemoryRepository();
    await repo.upsertTask(
      TaskItem(id: 'a', title: 'Relatório', dueAt: DateTime(2026, 9, 27, 23, 59)),
    );
    await repo.upsertTask(
      TaskItem(
        id: 'b',
        title: 'Antiga',
        status: TaskStatus.done,
        completedAt: DateTime(2026, 9, 20),
      ),
    );
    await pumpApp(tester, repo, location: '/tarefas');
    expect(find.text('atrasada · 1 d'), findsOneWidget);
    final done = tester.widget<Text>(find.text('Antiga'));
    expect(done.style?.decoration, TextDecoration.lineThrough);
  });

  testWidgets('sair da tela antes do salvamento terminar não gera erro (guarda mounted)', (
    tester,
  ) async {
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

Future<void> _pickDay(WidgetTester tester, String key, int day) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('$key-pick')));
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(of: find.byType(DatePickerDialog), matching: find.text('$day')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

Future<void> _pickPriority(WidgetTester tester, String status, TaskPriority p) async {
  await tester.tap(find.byKey(Key('quick-priority-$status')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('quick-priority-$status-${p.name}')));
  await tester.pumpAndSettle();
}

Finder _in(String key, String text) =>
    find.descendant(of: find.byKey(Key(key)), matching: find.text(text));

void _tasksPriorityTests() {
  group('adição rápida com prioridade e prazo', () {
    testWidgets('começa em "Média" e "Sem prazo"', (tester) async {
      await pumpApp(tester, MemoryRepository(), location: '/tarefas');
      for (final s in ['todo', 'doing', 'done']) {
        expect(_in('quick-priority-$s', 'Média'), findsOneWidget);
        expect(_in('quick-due-$s', 'Sem prazo'), findsOneWidget);
        expect(find.byKey(Key('quick-more-$s')), findsOneWidget);
      }
    });

    testWidgets('salva prioridade e prazo (23:59) escolhidos e zera os chips', (tester) async {
      final repo = MemoryRepository();
      await pumpApp(tester, repo, location: '/tarefas');
      await _pickPriority(tester, 'todo', TaskPriority.alta);
      expect(_in('quick-priority-todo', 'Alta'), findsOneWidget);
      await _pickDay(tester, 'quick-due-todo', 30);
      expect(_in('quick-due-todo', 'qua'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('quick-add-todo')), 'Prova de cálculo');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final t = (await repo.watchTasks().first).single;
      expect(t.title, 'Prova de cálculo');
      expect(t.priority, TaskPriority.alta);
      expect(t.dueAt, DateTime(2026, 9, 30, 23, 59));
      expect(_in('quick-priority-todo', 'Média'), findsOneWidget);
      expect(_in('quick-due-todo', 'Sem prazo'), findsOneWidget);
    });

    testWidgets('prazo mostra "hoje" e "amanhã" e pode ser removido', (tester) async {
      await pumpApp(tester, MemoryRepository(), location: '/tarefas');
      expect(find.byKey(const Key('quick-due-clear-todo')), findsNothing);
      await _pickDay(tester, 'quick-due-todo', 28);
      expect(_in('quick-due-todo', 'hoje'), findsOneWidget);
      await _pickDay(tester, 'quick-due-todo', 29);
      expect(_in('quick-due-todo', 'amanhã'), findsOneWidget);
      await tester.tap(find.byKey(const Key('quick-due-clear-todo')));
      await tester.pumpAndSettle();
      expect(_in('quick-due-todo', 'Sem prazo'), findsOneWidget);
      expect(find.byKey(const Key('quick-due-clear-todo')), findsNothing);
    });

    testWidgets('cada coluna tem seus próprios chips e cria no seu status', (tester) async {
      final repo = MemoryRepository();
      await pumpApp(tester, repo, location: '/tarefas');
      await _pickPriority(tester, 'doing', TaskPriority.baixa);
      expect(_in('quick-priority-todo', 'Média'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('quick-add-doing')), 'Devagar');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      final t = (await repo.watchTasks().first).single;
      expect([t.status, t.priority, t.dueAt], [TaskStatus.doing, TaskPriority.baixa, null]);
    });

    testWidgets('texto em branco com chips escolhidos não cria nada', (tester) async {
      final repo = MemoryRepository();
      await pumpApp(tester, repo, location: '/tarefas');
      await _pickPriority(tester, 'todo', TaskPriority.alta);
      await tester.enterText(find.byKey(const Key('quick-add-todo')), '  ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(await repo.watchTasks().first, isEmpty);
      expect(_in('quick-priority-todo', 'Alta'), findsOneWidget);
    });

    testWidgets('falha ao gravar mantém texto, prioridade e prazo', (tester) async {
      final repo = MemoryRepository()..failWrites = true;
      await pumpApp(tester, repo, location: '/tarefas');
      await _pickPriority(tester, 'todo', TaskPriority.alta);
      await _pickDay(tester, 'quick-due-todo', 30);
      await tester.enterText(find.byKey(const Key('quick-add-todo')), 'Resumo');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('Não foi possível adicionar. O texto continua no campo.'), findsOneWidget);
      expect(find.text('Resumo'), findsOneWidget);
      expect(_in('quick-priority-todo', 'Alta'), findsOneWidget);
      expect(_in('quick-due-todo', 'qua'), findsOneWidget);
    });

    testWidgets('celular: chips cabem na tela e criam com prioridade e prazo', (tester) async {
      final repo = MemoryRepository();
      await pumpApp(tester, repo, location: '/tarefas', size: const Size(360, 700));
      await _pickPriority(tester, 'todo', TaskPriority.alta);
      await _pickDay(tester, 'quick-due-todo', 29);
      await tester.enterText(find.byKey(const Key('quick-add-todo')), 'No celular');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final t = (await repo.watchTasks().first).single;
      expect([t.priority, t.dueAt], [TaskPriority.alta, DateTime(2026, 9, 29, 23, 59)]);
    });
  });

  group('mais opções (diálogo de criação)', () {
    testWidgets('abre vazio no status da coluna, sem botão de excluir, e cria', (tester) async {
      final repo = MemoryRepository();
      await repo.upsertSpace(const Space(id: 's1', name: 'Cálculo I', kind: SpaceKind.materia));
      await pumpApp(tester, repo, location: '/tarefas');
      await tester.tap(find.byKey(const Key('quick-more-doing')));
      await tester.pumpAndSettle();
      expect(find.text('Nova tarefa'), findsOneWidget);
      expect(find.textContaining('Excluir'), findsNothing);
      await tester.enterText(find.byKey(const Key('task-title')), 'Projeto final');
      await tester.enterText(find.byKey(const Key('task-description')), 'Entregar o PDF');
      await tester.tap(find.byKey(const Key('task-priority-alta')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('task-save')));
      await tester.pumpAndSettle();
      final t = (await repo.watchTasks().first).single;
      expect(t.title, 'Projeto final');
      expect(t.description, 'Entregar o PDF');
      expect(t.priority, TaskPriority.alta);
      expect(t.status, TaskStatus.doing);
      expect(find.byKey(const Key('task-save')), findsNothing);
    });

    testWidgets('leva o texto, a prioridade e o prazo já escolhidos e limpa o campo ao criar', (
      tester,
    ) async {
      final repo = MemoryRepository();
      await pumpApp(tester, repo, location: '/tarefas');
      await _pickPriority(tester, 'todo', TaskPriority.baixa);
      await _pickDay(tester, 'quick-due-todo', 30);
      await tester.enterText(find.byKey(const Key('quick-add-todo')), 'Rascunho');
      await tester.tap(find.byKey(const Key('quick-more-todo')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byKey(const Key('task-title'))).controller!.text,
        'Rascunho',
      );
      expect(find.text('Prazo: qua'), findsOneWidget);
      expect(
        tester
            .widget<SegmentedButton<TaskPriority>>(find.byType(SegmentedButton<TaskPriority>))
            .selected,
        {TaskPriority.baixa},
      );
      await tester.tap(find.byKey(const Key('task-save')));
      await tester.pumpAndSettle();
      final t = (await repo.watchTasks().first).single;
      expect(
        [t.title, t.priority, t.dueAt],
        ['Rascunho', TaskPriority.baixa, DateTime(2026, 9, 30, 23, 59)],
      );
      expect(
        tester.widget<TextField>(find.byKey(const Key('quick-add-todo'))).controller!.text,
        '',
      );
      expect(_in('quick-priority-todo', 'Média'), findsOneWidget);
      expect(_in('quick-due-todo', 'Sem prazo'), findsOneWidget);
    });

    testWidgets('cancelar não cria nem apaga o que estava no campo', (tester) async {
      final repo = MemoryRepository();
      await pumpApp(tester, repo, location: '/tarefas');
      await tester.enterText(find.byKey(const Key('quick-add-todo')), 'Rascunho');
      await tester.tap(find.byKey(const Key('quick-more-todo')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(await repo.watchTasks().first, isEmpty);
      expect(find.text('Rascunho'), findsOneWidget);
    });

    testWidgets('título em branco no diálogo não cria', (tester) async {
      final repo = MemoryRepository();
      await pumpApp(tester, repo, location: '/tarefas');
      await tester.tap(find.byKey(const Key('quick-more-todo')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('task-save')));
      await tester.pumpAndSettle();
      expect(await repo.watchTasks().first, isEmpty);
      expect(find.byKey(const Key('task-save')), findsOneWidget);
    });
  });

  group('editar e ver prioridade', () {
    testWidgets('diálogo de edição mostra a prioridade atual e salva a nova', (tester) async {
      final repo = MemoryRepository();
      await repo.upsertTask(
        const TaskItem(id: 'a', title: 'Relatório', priority: TaskPriority.baixa),
      );
      await pumpApp(tester, repo, location: '/tarefas');
      await tester.tap(find.byKey(const ValueKey('task-card-a')));
      await tester.pumpAndSettle();
      expect(find.text('Tarefa'), findsOneWidget);
      expect(find.byKey(const ValueKey('delete-task-a')), findsOneWidget);
      final seg = tester.widget<SegmentedButton<TaskPriority>>(
        find.byType(SegmentedButton<TaskPriority>),
      );
      expect(seg.selected, {TaskPriority.baixa});
      await tester.tap(find.byKey(const Key('task-priority-alta')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('task-save')));
      await tester.pumpAndSettle();
      expect((await repo.watchTasks().first).single.priority, TaskPriority.alta);
    });

    testWidgets('cartão: alta em destaque de perigo, baixa apagada, média sem marcador', (
      tester,
    ) async {
      final repo = MemoryRepository();
      await repo.upsertTask(const TaskItem(id: 'a', title: 'A', priority: TaskPriority.alta));
      await repo.upsertTask(const TaskItem(id: 'b', title: 'B', priority: TaskPriority.baixa));
      await repo.upsertTask(const TaskItem(id: 'c', title: 'C'));
      await pumpApp(tester, repo, location: '/tarefas');
      OrgBadge badge(String id, String label) => tester.widget<OrgBadge>(
        find.descendant(
          of: find.byKey(ValueKey('task-card-$id')),
          matching: find.widgetWithText(OrgBadge, label),
        ),
      );
      expect(badge('a', 'Alta').tone, OrgBadgeTone.danger);
      expect(badge('b', 'Baixa').tone, OrgBadgeTone.neutral);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('task-card-c')),
          matching: find.byType(OrgBadge),
        ),
        findsNothing,
      );
    });

    testWidgets('ordem na coluna: prioridade, depois prazo (sem prazo por último), depois título', (
      tester,
    ) async {
      final repo = MemoryRepository();
      Future<void> add(String id, TaskPriority p, [DateTime? due]) =>
          repo.upsertTask(TaskItem(id: id, title: id, priority: p, dueAt: due));
      await add('media-sem-prazo', TaskPriority.media);
      await add('baixa-cedo', TaskPriority.baixa, DateTime(2026, 9, 29, 23, 59));
      await add('alta-sem-prazo-b', TaskPriority.alta);
      await add('alta-tarde', TaskPriority.alta, DateTime(2026, 10, 5, 23, 59));
      await add('alta-sem-prazo-a', TaskPriority.alta);
      await add('alta-cedo', TaskPriority.alta, DateTime(2026, 9, 29, 23, 59));
      await add('media-cedo', TaskPriority.media, DateTime(2026, 9, 29, 23, 59));
      await pumpApp(tester, repo, location: '/tarefas', size: const Size(1000, 2400));
      final ids = [
        'alta-cedo',
        'alta-tarde',
        'alta-sem-prazo-a',
        'alta-sem-prazo-b',
        'media-cedo',
        'media-sem-prazo',
        'baixa-cedo',
      ];
      final ys = [
        for (final id in ids) tester.getTopLeft(find.byKey(ValueKey('task-card-$id'))).dy,
      ];
      expect(ys, orderedEquals([...ys]..sort()));
    });

    testWidgets('"Feito" continua por conclusão mais recente, ignorando a prioridade', (
      tester,
    ) async {
      final repo = MemoryRepository();
      await repo.upsertTask(
        TaskItem(
          id: 'velha',
          title: 'velha',
          status: TaskStatus.done,
          priority: TaskPriority.alta,
          completedAt: DateTime(2026, 9, 20),
        ),
      );
      await repo.upsertTask(
        TaskItem(
          id: 'nova',
          title: 'nova',
          status: TaskStatus.done,
          priority: TaskPriority.baixa,
          completedAt: DateTime(2026, 9, 27),
        ),
      );
      await pumpApp(tester, repo, location: '/tarefas');
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('task-card-nova'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const ValueKey('task-card-velha'))).dy),
      );
    });
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
