import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/domain/recurrence.dart';
import 'package:organizacional/domain/task_item.dart';
import 'package:organizacional/domain/task_series.dart';

Recurrence _r(RepeatFreq f, {Set<int> days = const {}, DateTime? until, int? count}) =>
    Recurrence(freq: f, days: days, until: until, count: count);

void main() {
  var n = 0;
  String gen() => 'id${++n}';
  setUp(() => n = 0);

  // Terça 20/10/2026, 23:59.
  TaskItem template({TaskStatus status = TaskStatus.todo}) => TaskItem(
        id: 'tpl',
        title: 'Lab de S01',
        description: 'Relatório',
        priority: TaskPriority.alta,
        status: status,
        completedAt: status == TaskStatus.done ? DateTime(2026, 10, 20, 12) : null,
        dueAt: DateTime(2026, 10, 20, 23, 59),
        spaceId: 'sp1',
      );

  List<TaskItem> weekly(int count) =>
      TaskSeriesOps.buildSeries(template(), _r(RepeatFreq.weekly, days: {2}, count: count), gen);

  TaskItem done(TaskItem t) => t.toggled(DateTime(2026, 11, 1));

  group('TaskItem', () {
    test('toMap/fromMap preserva seriesId e recurrence', () {
      final t = template().copyWith(seriesId: 's1', recurrence: _r(RepeatFreq.weekly, days: {2}, count: 3));
      final m = t.toMap();
      expect(m['series_id'], 's1');
      expect(m['recurrence'], {'freq': 'weekly', 'days': [2], 'until': null, 'count': 3});
      expect(TaskItem.fromMap(m), t);
    });

    test('sem série: series_id e recurrence nulos', () {
      final m = template().toMap();
      expect(m['series_id'], isNull);
      expect(m['recurrence'], isNull);
      expect(TaskItem.fromMap(m).seriesId, isNull);
      expect(TaskItem.fromMap(m).recurrence, isNull);
    });

    test('toggled e moved mantêm a série', () {
      final t = template().copyWith(seriesId: 's1', recurrence: _r(RepeatFreq.daily, count: 2));
      expect(t.toggled(DateTime(2026, 10, 21)).seriesId, 's1');
      expect(t.toggled(DateTime(2026, 10, 21)).recurrence, t.recurrence);
      expect(t.moved(TaskStatus.doing, DateTime(2026, 10, 21)).seriesId, 's1');
    });

    test('copyWith(clearSeries) tira série e regra', () {
      final t = template().copyWith(seriesId: 's1', recurrence: _r(RepeatFreq.daily, count: 2));
      final c = t.copyWith(clearSeries: true);
      expect(c.seriesId, isNull);
      expect(c.recurrence, isNull);
    });
  });

  group('Recurrence.shortLabel', () {
    final at = DateTime(2026, 10, 20, 23, 59);
    test('semanal com until', () {
      expect(_r(RepeatFreq.weekly, days: {2}, until: DateTime(2026, 12, 1)).shortLabel(at),
          'Toda semana às ter, até 1 dez');
    });
    test('semanal sem dias usa o dia da própria tarefa; por contagem mostra vezes', () {
      expect(_r(RepeatFreq.weekly, count: 8).shortLabel(at), 'Toda semana às ter · 8 vezes');
      expect(_r(RepeatFreq.weekly, count: 1).shortLabel(at), 'Toda semana às ter · 1 vez');
    });
    test('diária e mensal', () {
      expect(_r(RepeatFreq.daily, until: DateTime(2026, 11, 3)).shortLabel(at), 'Todo dia, até 3 nov');
      expect(_r(RepeatFreq.monthly, count: 3).shortLabel(at), 'Todo mês no dia 20 · 3 vezes');
    });
  });

  group('buildSeries', () {
    test('toda terça até 1/12 a partir de ter 20/10 gera 7 ocorrências com a mesma série', () {
      final s = TaskSeriesOps.buildSeries(
          template(), _r(RepeatFreq.weekly, days: {2}, until: DateTime(2026, 12, 1)), gen);
      expect(s.length, 7);
      expect(s.first.dueAt, DateTime(2026, 10, 20, 23, 59));
      expect(s.last.dueAt, DateTime(2026, 12, 1, 23, 59));
      expect(s.map((t) => t.seriesId).toSet().length, 1);
      expect(s.first.seriesId, isNotNull);
      expect(s.every((t) => t.recurrence != null), isTrue);
      expect(s.every((t) => t.title == 'Lab de S01' && t.spaceId == 'sp1'), isTrue);
      expect(s.every((t) => t.priority == TaskPriority.alta && t.description == 'Relatório'), isTrue);
    });

    test('a primeira reaproveita o id do template; as demais ganham ids novos', () {
      final s = weekly(3);
      expect(s.first.id, 'tpl');
      expect(s.skip(1).map((t) => t.id).toSet().length, 2);
      expect(s.skip(1).every((t) => t.id != 'tpl'), isTrue);
    });

    test('só a que reaproveita o template mantém status; as novas começam a fazer', () {
      final s = TaskSeriesOps.buildSeries(
          template(status: TaskStatus.done), _r(RepeatFreq.weekly, days: {2}, count: 3), gen);
      expect(s.first.status, TaskStatus.done);
      expect(s.first.completedAt, isNotNull);
      expect(s.skip(1).every((t) => t.status == TaskStatus.todo && t.completedAt == null), isTrue);
    });

    test('prazo depois do until: nenhuma ocorrência, sem erro', () {
      final s = TaskSeriesOps.buildSeries(
          template(), _r(RepeatFreq.weekly, days: {2}, until: DateTime(2026, 10, 19)), gen);
      expect(s, isEmpty);
    });

    test('freq none devolve só o template, sem série', () {
      final s = TaskSeriesOps.buildSeries(template(), _r(RepeatFreq.none), gen);
      expect(s.length, 1);
      expect(s.single.seriesId, isNull);
      expect(s.single.recurrence, isNull);
    });
  });

  group('nextPendingPerSeries', () {
    test('mantém tarefas sem série e só a pendente mais antiga de cada série', () {
      final s = weekly(4);
      final solo = const TaskItem(id: 'solo', title: 'Avulsa');
      final out = nextPendingPerSeries([...s, solo]);
      expect(out.map((t) => t.id), [s.first.id, 'solo']);
    });

    test('atrasada não concluída aparece; concluída a atrasada, aparece a seguinte', () {
      final s = weekly(3);
      expect(nextPendingPerSeries(s).single.id, s[0].id);
      final after = [done(s[0]), s[1], s[2]];
      final out = nextPendingPerSeries(after);
      expect(out.where((t) => !t.isDone).single.id, s[1].id);
    });

    test('concluídas continuam na lista', () {
      final s = weekly(3);
      final out = nextPendingPerSeries([done(s[0]), done(s[1]), s[2]]);
      expect(out.map((t) => t.id).toSet(), {s[0].id, s[1].id, s[2].id});
    });

    test('desmarcar a concluída mais antiga volta a ser a próxima pendente', () {
      final s = weekly(3);
      final reopened = done(s[0]).toggled(DateTime(2026, 11, 2));
      final out = nextPendingPerSeries([reopened, s[1], s[2]]);
      expect(out.map((t) => t.id), [s[0].id]);
    });

    test('série inteira concluída: só concluídas, sem erro', () {
      final s = weekly(3).map(done).toList();
      final out = nextPendingPerSeries(s);
      expect(out.length, 3);
      expect(out.every((t) => t.isDone), isTrue);
    });

    test('ordem da entrada é preservada e entrada embaralhada funciona', () {
      final s = weekly(3);
      final out = nextPendingPerSeries([s[2], s[0], s[1]]);
      expect(out.single.id, s[0].id);
    });

    test('entrada vazia', () {
      expect(nextPendingPerSeries(const []), isEmpty);
    });
  });

  group('applyEdit', () {
    TaskItem edited(TaskItem t, {String? title, Duration shift = Duration.zero, TaskPriority? priority}) =>
        t.copyWith(title: title, dueAt: t.dueAt!.add(shift), priority: priority);

    test('one: só o alvo, que sai da série', () {
      final s = weekly(4);
      final up = TaskSeriesOps.applyEdit(s, s[1], edited(s[1], title: 'Prova'), SeriesScope.one);
      expect(up.length, 1);
      expect(up.single.title, 'Prova');
      expect(up.single.seriesId, isNull);
      expect(up.single.recurrence, isNull);
    });

    test('all: título/prioridade/espaço em todas; deslocamento de dia e hora em todas', () {
      final s = weekly(3);
      final e = edited(s[0], title: 'Lab', shift: const Duration(days: 1, hours: -2), priority: TaskPriority.baixa)
          .copyWith(clearSpace: true);
      final up = TaskSeriesOps.applyEdit(s, s[0], e, SeriesScope.all);
      expect(up.length, 3);
      expect(up.every((t) => t.title == 'Lab' && t.priority == TaskPriority.baixa), isTrue);
      expect(up.every((t) => t.spaceId == null), isTrue);
      expect(up.map((t) => t.dueAt), [
        DateTime(2026, 10, 21, 21, 59),
        DateTime(2026, 10, 28, 21, 59),
        DateTime(2026, 11, 4, 21, 59),
      ]);
      expect(up.map((t) => t.seriesId).toSet(), {s.first.seriesId});
    });

    test('ocorrências concluídas mantêm o status e o completedAt', () {
      final s = weekly(3);
      final series = [done(s[0]), s[1], s[2]];
      final up = TaskSeriesOps.applyEdit(series, s[1], edited(s[1], title: 'Novo'), SeriesScope.all);
      final first = up.firstWhere((t) => t.id == s[0].id);
      expect(first.status, TaskStatus.done);
      expect(first.completedAt, DateTime(2026, 11, 1));
      expect(first.title, 'Novo');
    });

    test('following a partir do meio cria série nova só para as seguintes', () {
      final s = weekly(4);
      final up = TaskSeriesOps.applyEdit(s, s[2], edited(s[2], title: 'Z'), SeriesScope.following,
          newSeriesId: () => 'nova');
      expect(up.map((t) => t.id), [s[2].id, s[3].id]);
      expect(up.every((t) => t.seriesId == 'nova' && t.title == 'Z'), isTrue);
    });

    test('following a partir da primeira não cria série nova', () {
      final s = weekly(3);
      final up = TaskSeriesOps.applyEdit(s, s[0], edited(s[0], title: 'Z'), SeriesScope.following,
          newSeriesId: () => fail('não deveria criar série nova'));
      expect(up.length, 3);
      expect(up.every((t) => t.seriesId == s.first.seriesId), isTrue);
    });

    test('série fora de ordem: following usa o prazo, não a posição', () {
      final s = weekly(3);
      final up = TaskSeriesOps.applyEdit([s[2], s[0], s[1]], s[1], edited(s[1], title: 'Z'), SeriesScope.following,
          newSeriesId: () => 'nova');
      expect(up.map((t) => t.id).toSet(), {s[1].id, s[2].id});
    });

    test('mudança de status do alvo (folha) vale para o alvo, mas não para as outras', () {
      final s = weekly(3);
      final e = s[1].toggled(DateTime(2026, 11, 2)); // alvo marcado como feito no editor
      final up = TaskSeriesOps.applyEdit(s, s[1], e, SeriesScope.all);
      expect(up.firstWhere((t) => t.id == s[1].id).status, TaskStatus.done);
      expect(up.firstWhere((t) => t.id == s[0].id).status, TaskStatus.todo);
    });
  });

  group('deleteIds', () {
    test('one / following / all', () {
      final s = weekly(4);
      expect(TaskSeriesOps.deleteIds(s, s[1], SeriesScope.one), [s[1].id]);
      expect(TaskSeriesOps.deleteIds(s, s[1], SeriesScope.following), [s[1].id, s[2].id, s[3].id]);
      expect(TaskSeriesOps.deleteIds(s, s[1], SeriesScope.all), s.map((t) => t.id).toList());
    });

    test('ordena por prazo mesmo com a série embaralhada', () {
      final s = weekly(3);
      expect(TaskSeriesOps.deleteIds([s[2], s[0], s[1]], s[1], SeriesScope.following), [s[1].id, s[2].id]);
    });
  });
}
