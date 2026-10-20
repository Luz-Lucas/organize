import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/recurrence.dart';
import 'package:organizacional/domain/space.dart';
import 'package:organizacional/domain/task_item.dart';
import 'package:organizacional/domain/task_series.dart';

import '../helpers.dart';

/// Terças às 23:59 a partir de 29/09/2026 (hoje nos testes é seg 28/09, 10:00), 4 ocorrências:
/// o1 29/09, o2 06/10, o3 13/10, o4 20/10; série "ser".
List<TaskItem> _serie({int count = 4}) {
  var n = 0;
  String gen() {
    n++;
    return n == 1 ? 'ser' : 'o$n';
  }

  return TaskSeriesOps.buildSeries(
    TaskItem(
      id: 'o1',
      title: 'Lab de S01',
      description: 'Relatório',
      priority: TaskPriority.alta,
      dueAt: DateTime(2026, 9, 29, 23, 59),
    ),
    Recurrence(freq: RepeatFreq.weekly, days: {2}, count: count),
    gen,
  );
}

Future<MemoryRepository> _repoWithSeries({List<TaskItem> extra = const []}) async {
  final repo = MemoryRepository();
  await repo.upsertTasks([..._serie(), ...extra]);
  return repo;
}

Future<List<TaskItem>> _all(MemoryRepository repo) => repo.watchTasks().first;

Future<TaskItem> _task(MemoryRepository repo, String id) async =>
    (await _all(repo)).firstWhere((t) => t.id == id);

Finder _card(String id) => find.byKey(ValueKey('task-card-$id'));

Future<void> _open(WidgetTester tester, String id) async {
  await tester.tap(_card(id));
  await tester.pumpAndSettle();
}

Future<void> _pickDueDay(WidgetTester tester, int day) async {
  await tester.tap(find.byKey(const Key('task-due')));
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(of: find.byType(DatePickerDialog), matching: find.text('$day')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

Future<void> _chooseFreq(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const Key('task-repeat')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _newTaskWithDialog(WidgetTester tester, String title) async {
  await tester.enterText(find.byKey(const Key('quick-add-todo')), title);
  await tester.tap(find.byKey(const Key('quick-more-todo')));
  await tester.pumpAndSettle();
}

void main() {
  group('criar série pelo editor', () {
    testWidgets('semanal por quantidade cria as ocorrências com o mesmo seriesId e o mesmo horário', (tester) async {
      final repo = MemoryRepository();
      await pumpApp(tester, repo, location: '/tarefas');
      await _newTaskWithDialog(tester, 'Lab de S01');
      expect(find.byKey(const Key('task-repeat')), findsNothing); // sem prazo não repete
      expect(find.byKey(const Key('task-repeat-needs-due')), findsOneWidget);

      await _pickDueDay(tester, 29); // terça 29/09, 23:59
      expect(find.byKey(const Key('task-repeat-needs-due')), findsNothing);
      await _chooseFreq(tester, 'Toda semana');
      expect(tester.widget<FilterChip>(find.byKey(const Key('task-repeat-day-2'))).selected, isTrue);
      await tester.tap(find.byKey(const Key('task-repeat-mode-count')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('task-repeat-count')), '3');
      await tester.pumpAndSettle();
      expect(find.textContaining('Toda semana às ter'), findsOneWidget);
      expect(find.textContaining('3 ocorrências'), findsOneWidget);

      await tester.tap(find.byKey(const Key('task-save')));
      await tester.pumpAndSettle();

      final tasks = await _all(repo);
      final byDue = [...tasks]..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));
      expect(byDue.map((t) => t.dueAt), [
        DateTime(2026, 9, 29, 23, 59),
        DateTime(2026, 10, 6, 23, 59),
        DateTime(2026, 10, 13, 23, 59),
      ]);
      expect(tasks.map((t) => t.seriesId).toSet().length, 1);
      expect(tasks.first.seriesId, isNotNull);
      expect(tasks.every((t) => t.title == 'Lab de S01' && t.recurrence != null), isTrue);
      // Na tela, só a próxima pendente da série.
      expect(find.text('Lab de S01'), findsOneWidget);
    });

    testWidgets('padrão "Até" (prazo + 3 meses) cria a série e a tela mostra uma só', (tester) async {
      final repo = MemoryRepository();
      await pumpApp(tester, repo, location: '/tarefas');
      await _newTaskWithDialog(tester, 'Ponto');
      await _pickDueDay(tester, 29);
      await _chooseFreq(tester, 'Todo dia');
      await tester.tap(find.byKey(const Key('task-save')));
      await tester.pumpAndSettle();
      final tasks = await _all(repo);
      expect(tasks.length, greaterThan(80));
      expect(tasks.map((t) => t.seriesId).toSet().length, 1);
      expect(find.text('Ponto'), findsOneWidget);
    });

    testWidgets('repetição sem nenhuma ocorrência no período mostra o aviso e não grava', (tester) async {
      final repo = MemoryRepository();
      await pumpApp(tester, repo, location: '/tarefas');
      await _newTaskWithDialog(tester, 'Lab');
      await _pickDueDay(tester, 29); // terça
      await _chooseFreq(tester, 'Toda semana');
      // Só segunda, até 30/09: nenhuma segunda no intervalo.
      await tester.tap(find.byKey(const Key('task-repeat-day-1')));
      await tester.tap(find.byKey(const Key('task-repeat-day-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('task-repeat-until')));
      await tester.pumpAndSettle();
      // O seletor abre em dezembro (prazo + 3 meses): volta três meses até setembro.
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byIcon(Icons.chevron_left));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.descendant(of: find.byType(DatePickerDialog), matching: find.text('30')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Nenhuma ocorrência no período'), findsOneWidget);

      await tester.tap(find.byKey(const Key('task-save')));
      await tester.pumpAndSettle();
      expect(find.text('A repetição não gera nenhuma tarefa nesse período.'), findsOneWidget);
      expect(await _all(repo), isEmpty);
    });

    testWidgets('tirar o prazo depois de escolher a repetição salva uma tarefa comum', (tester) async {
      final repo = MemoryRepository();
      await pumpApp(tester, repo, location: '/tarefas');
      await _newTaskWithDialog(tester, 'Avulsa');
      await _pickDueDay(tester, 29);
      await _chooseFreq(tester, 'Toda semana');
      await tester.tap(find.byKey(const Key('task-due-clear')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('task-repeat')), findsNothing);
      await tester.tap(find.byKey(const Key('task-save')));
      await tester.pumpAndSettle();
      final t = (await _all(repo)).single;
      expect(t.seriesId, isNull);
      expect(t.dueAt, isNull);
    });

    testWidgets('celular (folha): também cria a série', (tester) async {
      final repo = MemoryRepository();
      await pumpApp(tester, repo, location: '/tarefas', size: const Size(400, 900));
      await _newTaskWithDialog(tester, 'Lab');
      await _pickDueDay(tester, 29);
      await _chooseFreq(tester, 'Toda semana');
      await tester.tap(find.byKey(const Key('task-repeat-mode-count')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('task-repeat-count')), '2');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('task-save')));
      await tester.tap(find.byKey(const Key('task-save')));
      await tester.pumpAndSettle();
      expect((await _all(repo)).length, 2);
    });

    testWidgets('editar uma tarefa existente sem série não oferece "Repetir"', (tester) async {
      final repo = MemoryRepository();
      await repo.upsertTask(TaskItem(id: 'a', title: 'Relatório', dueAt: DateTime(2026, 10, 1, 23, 59)));
      await pumpApp(tester, repo, location: '/tarefas');
      await _open(tester, 'a');
      expect(find.byKey(const Key('task-repeat')), findsNothing);
    });
  });

  group('lista mostra só a próxima pendente', () {
    testWidgets('quadro: só a primeira da série (e o selo com o resumo)', (tester) async {
      final repo = await _repoWithSeries(extra: const [TaskItem(id: 'solo', title: 'Avulsa')]);
      await pumpApp(tester, repo, location: '/tarefas');
      expect(_card('o1'), findsOneWidget);
      expect(_card('o2'), findsNothing);
      expect(_card('o4'), findsNothing);
      expect(_card('solo'), findsOneWidget);
      expect(find.text('A fazer 2'), findsNothing); // desktop: sem abas; contagem na coluna
      final badge = find.byKey(const Key('task-series-badge-o1'));
      expect(badge, findsOneWidget);
      expect(find.descendant(of: badge, matching: find.textContaining('Toda semana às ter')), findsOneWidget);
      expect(find.byKey(const Key('task-series-badge-solo')), findsNothing);
    });

    testWidgets('celular: contagem da aba conta só a próxima', (tester) async {
      final repo = await _repoWithSeries();
      await pumpApp(tester, repo, location: '/tarefas', size: const Size(400, 800));
      expect(find.text('A fazer 1'), findsOneWidget);
    });

    testWidgets('concluir a atrasada mostra a seguinte; a concluída vai para Feito', (tester) async {
      final repo = await _repoWithSeries();
      // hoje é seg 28/09; "atrasar" a série: o relógio vai para 08/10 (o1 e o2 vencidas).
      await pumpApp(tester, repo, location: '/tarefas', now: DateTime(2026, 10, 8, 10));
      expect(_card('o1'), findsOneWidget); // a atrasada, não a o2
      expect(_card('o2'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('task-done-o1')));
      await tester.pumpAndSettle();
      expect((await _task(repo, 'o1')).status, TaskStatus.done);
      // Sem diálogo de escopo ao concluir.
      expect(find.byKey(const Key('series-scope-all')), findsNothing);
      expect(_card('o2'), findsOneWidget); // a seguinte virou a pendente
      expect(_card('o3'), findsNothing);
      expect(_card('o1'), findsOneWidget); // na coluna Feito
    });

    testWidgets('reabrir a concluída mais antiga a traz de volta como pendente', (tester) async {
      final repo = await _repoWithSeries();
      final s = await _all(repo);
      await repo.upsertTask(s.firstWhere((t) => t.id == 'o1').toggled(DateTime(2026, 9, 29)));
      await pumpApp(tester, repo, location: '/tarefas');
      expect(_card('o2'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('task-done-o1')));
      await tester.pumpAndSettle();
      expect((await _task(repo, 'o1')).status, TaskStatus.todo);
      expect(_card('o2'), findsNothing);
      expect(_card('o1'), findsOneWidget);
    });

    testWidgets('série inteira concluída: só concluídas, sem erro', (tester) async {
      final repo = MemoryRepository();
      await repo.upsertTasks([for (final t in _serie()) t.toggled(DateTime(2026, 10, 25))]);
      await pumpApp(tester, repo, location: '/tarefas', size: const Size(1000, 1800));
      expect(tester.takeException(), isNull);
      for (final id in ['o1', 'o2', 'o3', 'o4']) {
        expect(_card(id), findsOneWidget);
      }
    });
  });

  group('editar com escopo', () {
    testWidgets('"Todas": título e prazo valem para a série inteira', (tester) async {
      final repo = await _repoWithSeries();
      await pumpApp(tester, repo, location: '/tarefas');
      await _open(tester, 'o1');
      expect(find.byKey(const Key('task-series-label')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('task-title')), 'Lab final');
      await tester.tap(find.byKey(const Key('task-save')));
      await tester.pumpAndSettle();
      expect(find.text('Esta tarefa se repete'), findsOneWidget);
      expect(find.text('Só esta tarefa'), findsOneWidget);
      await tester.tap(find.byKey(const Key('series-scope-all')));
      await tester.pumpAndSettle();
      final tasks = await _all(repo);
      expect(tasks.length, 4);
      expect(tasks.every((t) => t.title == 'Lab final'), isTrue);
      expect(tasks.map((t) => t.seriesId).toSet(), {'ser'});
    });

    testWidgets('"Só esta": muda uma e ela sai da série; a próxima da série passa a ser a o2', (tester) async {
      final repo = await _repoWithSeries();
      await pumpApp(tester, repo, location: '/tarefas');
      await _open(tester, 'o1');
      await tester.enterText(find.byKey(const Key('task-title')), 'Só essa');
      await tester.tap(find.byKey(const Key('task-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('series-scope-one')));
      await tester.pumpAndSettle();
      final o1 = await _task(repo, 'o1');
      expect(o1.title, 'Só essa');
      expect(o1.seriesId, isNull);
      expect((await _task(repo, 'o2')).title, 'Lab de S01');
      expect(_card('o1'), findsOneWidget);
      expect(_card('o2'), findsOneWidget);
    });

    testWidgets('"Esta e as seguintes" a partir da primeira não cria série nova', (tester) async {
      final repo = await _repoWithSeries();
      await pumpApp(tester, repo, location: '/tarefas');
      await _open(tester, 'o1');
      await tester.enterText(find.byKey(const Key('task-title')), 'Novo nome');
      await tester.tap(find.byKey(const Key('task-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('series-scope-following')));
      await tester.pumpAndSettle();
      final tasks = await _all(repo);
      expect(tasks.map((t) => t.seriesId).toSet(), {'ser'});
      expect(tasks.every((t) => t.title == 'Novo nome'), isTrue);
    });

    testWidgets('"Esta e as seguintes" no meio cria série nova; as anteriores ficam', (tester) async {
      final repo = await _repoWithSeries();
      final o1 = await _task(repo, 'o1');
      await repo.upsertTask(o1.toggled(DateTime(2026, 9, 29))); // o2 vira a próxima
      await pumpApp(tester, repo, location: '/tarefas');
      await _open(tester, 'o2');
      await tester.enterText(find.byKey(const Key('task-title')), 'Depois');
      await tester.tap(find.byKey(const Key('task-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('series-scope-following')));
      await tester.pumpAndSettle();
      final tasks = await _all(repo);
      expect((await _task(repo, 'o1')).title, 'Lab de S01');
      expect((await _task(repo, 'o1')).seriesId, 'ser');
      final later = tasks.where((t) => t.title == 'Depois').toList();
      expect(later.map((t) => t.id).toSet(), {'o2', 'o3', 'o4'});
      expect(later.map((t) => t.seriesId).toSet().length, 1);
      expect(later.first.seriesId, isNot('ser'));
    });

    testWidgets('cancelar a pergunta de escopo não salva e mantém o editor aberto', (tester) async {
      final repo = await _repoWithSeries();
      await pumpApp(tester, repo, location: '/tarefas');
      await _open(tester, 'o1');
      await tester.enterText(find.byKey(const Key('task-title')), 'Mudou');
      await tester.tap(find.byKey(const Key('task-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('series-scope-cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('task-title')), findsOneWidget);
      expect((await _task(repo, 'o1')).title, 'Lab de S01');
    });

    testWidgets('mudar só o status (folha no celular) não pergunta e mantém a série', (tester) async {
      final repo = await _repoWithSeries();
      await pumpApp(tester, repo, location: '/tarefas', size: const Size(400, 900));
      await _open(tester, 'o1');
      await tester.tap(find.byKey(const Key('task-status-done')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('task-save')));
      await tester.tap(find.byKey(const Key('task-save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('series-scope-all')), findsNothing);
      final o1 = await _task(repo, 'o1');
      expect(o1.status, TaskStatus.done);
      expect(o1.seriesId, 'ser');
      expect((await _task(repo, 'o2')).status, TaskStatus.todo);
    });

    testWidgets('espaço: trocar o espaço com "Todas" vale para a série', (tester) async {
      final repo = await _repoWithSeries();
      await repo.upsertSpace(const Space(id: 'sp1', name: 'Cálculo I', position: 0));
      await pumpApp(tester, repo, location: '/tarefas');
      await _open(tester, 'o1');
      await tester.tap(find.byKey(const Key('task-space')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cálculo I').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('task-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('series-scope-all')));
      await tester.pumpAndSettle();
      expect((await _all(repo)).every((t) => t.spaceId == 'sp1'), isTrue);
    });
  });

  group('apagar com escopo', () {
    testWidgets('"Todas" apaga a série e "Desfazer" traz tudo de volta', (tester) async {
      final repo = await _repoWithSeries();
      await pumpApp(tester, repo, location: '/tarefas');
      await _open(tester, 'o1');
      await tester.tap(find.byKey(const ValueKey('delete-task-o1')));
      await tester.pumpAndSettle();
      expect(find.text('Esta tarefa se repete'), findsOneWidget);
      expect(find.text('O que você quer excluir?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('series-scope-all')));
      await tester.pumpAndSettle();
      expect(await _all(repo), isEmpty);
      expect(find.text('4 tarefas excluídas'), findsOneWidget);
      await tester.tap(find.text('Desfazer'));
      await tester.pumpAndSettle();
      expect((await _all(repo)).length, 4);
    });

    testWidgets('"Só esta" apaga uma e a seguinte vira a pendente', (tester) async {
      final repo = await _repoWithSeries();
      await pumpApp(tester, repo, location: '/tarefas');
      await _open(tester, 'o1');
      await tester.tap(find.byKey(const ValueKey('delete-task-o1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('series-scope-one')));
      await tester.pumpAndSettle();
      expect((await _all(repo)).map((t) => t.id).toSet(), {'o2', 'o3', 'o4'});
      expect(find.text('Tarefa excluída'), findsOneWidget);
      expect(_card('o2'), findsOneWidget);
    });

    testWidgets('"Esta e as seguintes" apaga dali em diante', (tester) async {
      final repo = await _repoWithSeries();
      final o1 = await _task(repo, 'o1');
      await repo.upsertTask(o1.toggled(DateTime(2026, 9, 29)));
      await pumpApp(tester, repo, location: '/tarefas');
      await _open(tester, 'o2');
      await tester.tap(find.byKey(const ValueKey('delete-task-o2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('series-scope-following')));
      await tester.pumpAndSettle();
      expect((await _all(repo)).map((t) => t.id).toSet(), {'o1'});
    });

    testWidgets('cancelar a pergunta mantém tudo', (tester) async {
      final repo = await _repoWithSeries();
      await pumpApp(tester, repo, location: '/tarefas');
      await _open(tester, 'o1');
      await tester.tap(find.byKey(const ValueKey('delete-task-o1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('series-scope-cancel')));
      await tester.pumpAndSettle();
      expect((await _all(repo)).length, 4);
    });

    testWidgets('tarefa sem série apaga direto, sem pergunta', (tester) async {
      final repo = MemoryRepository();
      await repo.upsertTask(const TaskItem(id: 'a', title: 'Solta'));
      await pumpApp(tester, repo, location: '/tarefas');
      await _open(tester, 'a');
      await tester.tap(find.byKey(const ValueKey('delete-task-a')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('series-scope-all')), findsNothing);
      expect(await _all(repo), isEmpty);
    });
  });
}
