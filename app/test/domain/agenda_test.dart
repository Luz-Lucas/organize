import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/domain/agenda.dart';
import 'package:organizacional/domain/calendar_event.dart';
import 'package:organizacional/domain/task_item.dart';

void main() {
  final now = DateTime(2026, 9, 28, 10); // segunda-feira

  TaskItem task(String id, {DateTime? due, bool done = false}) => TaskItem(
        id: id,
        title: id,
        dueAt: due,
        status: done ? TaskStatus.done : TaskStatus.todo,
        completedAt: done ? now : null,
      );

  CalendarEvent event(String id, DateTime start, DateTime end) =>
      CalendarEvent(id: id, title: id, startsAt: start, endsAt: end);

  test('a semana começa na segunda', () {
    expect(startOfWeek(DateTime(2026, 10, 1, 15)), DateTime(2026, 9, 28));
    expect(startOfWeek(DateTime(2026, 10, 4)), DateTime(2026, 9, 28));
    expect(startOfWeek(DateTime(2026, 9, 28)), DateTime(2026, 9, 28));
  });

  group('eventsOnDay', () {
    test('inclui só os eventos do dia, ordenados pelo início', () {
      final b = event('b', DateTime(2026, 9, 28, 14), DateTime(2026, 9, 28, 15));
      final a = event('a', DateTime(2026, 9, 28, 8), DateTime(2026, 9, 28, 9));
      final other = event('x', DateTime(2026, 9, 29, 8), DateTime(2026, 9, 29, 9));
      expect(eventsOnDay([b, other, a], DateTime(2026, 9, 28)), [a, b]);
    });

    test('evento que termina à meia-noite não vaza para o dia seguinte', () {
      final e = event('noite', DateTime(2026, 9, 27, 22), DateTime(2026, 9, 28));
      expect(eventsOnDay([e], DateTime(2026, 9, 28)), isEmpty);
      expect(eventsOnDay([e], DateTime(2026, 9, 27)), [e]);
    });

    test('evento que atravessa a meia-noite aparece nos dois dias', () {
      final e = event('festa', DateTime(2026, 9, 27, 23), DateTime(2026, 9, 28, 1));
      expect(eventsOnDay([e], DateTime(2026, 9, 27)), [e]);
      expect(eventsOnDay([e], DateTime(2026, 9, 28)), [e]);
    });

    test('evento de duração zero à meia-noite pertence ao dia que começa', () {
      final e = event('marco', DateTime(2026, 9, 28), DateTime(2026, 9, 28));
      expect(eventsOnDay([e], DateTime(2026, 9, 28)), [e]);
      expect(eventsOnDay([e], DateTime(2026, 9, 27)), isEmpty);
    });

    final brasilia = DateTime(2026, 9, 27).timeZoneOffset == const Duration(hours: -3);
    test('evento às 23:30 de Brasília (02:30Z) fica no dia local', () {
      final e = CalendarEvent.fromMap({
        'id': 'e1',
        'title': 'Aula noturna',
        'starts_at': '2026-09-28T02:30:00+00:00',
        'ends_at': '2026-09-28T02:50:00+00:00',
      });
      expect(eventsOnDay([e], DateTime(2026, 9, 27)), [e]);
      expect(eventsOnDay([e], DateTime(2026, 9, 28)), isEmpty);
    }, skip: brasilia ? false : 'rode com TZ=America/Sao_Paulo');
  });

  group('groupTasks', () {
    test('separa atrasadas, hoje, próximas, sem data e concluídas', () {
      final groups = groupTasks([
        task('amanha', due: DateTime(2026, 9, 29, 23, 59)),
        task('ontem', due: DateTime(2026, 9, 27, 23, 59)),
        task('hoje', due: DateTime(2026, 9, 28, 23, 59)),
        task('livre'),
        task('feita', due: DateTime(2026, 9, 20), done: true),
      ], now);
      expect(groups[TaskGroup.atrasadas]!.map((t) => t.id), ['ontem']);
      expect(groups[TaskGroup.hoje]!.map((t) => t.id), ['hoje']);
      expect(groups[TaskGroup.proximas]!.map((t) => t.id), ['amanha']);
      expect(groups[TaskGroup.semData]!.map((t) => t.id), ['livre']);
      expect(groups[TaskGroup.concluidas]!.map((t) => t.id), ['feita']);
    });

    test('prazo às 00:00 de hoje conta como hoje, não como atrasada', () {
      final groups = groupTasks([task('meianoite', due: DateTime(2026, 9, 28))], now);
      expect(groups[TaskGroup.hoje]!.single.id, 'meianoite');
    });
  });

  test('buildDayAgenda junta os eventos do dia e as tarefas pendentes', () {
    final aula = event('aula', DateTime(2026, 9, 28, 8), DateTime(2026, 9, 28, 9, 40));
    final agenda = buildDayAgenda(
      now: now,
      events: [aula, event('amanha', DateTime(2026, 9, 29, 8), DateTime(2026, 9, 29, 9))],
      tasks: [
        task('ontem', due: DateTime(2026, 9, 27)),
        task('hoje', due: DateTime(2026, 9, 28, 18)),
        task('feita', due: DateTime(2026, 9, 28, 18), done: true),
      ],
    );
    expect(agenda.events, [aula]);
    expect(agenda.overdue.map((t) => t.id), ['ontem']);
    expect(agenda.dueToday.map((t) => t.id), ['hoje']);
  });

  test('validateEventTimes exige fim depois do início', () {
    final start = DateTime(2026, 9, 28, 10);
    expect(validateEventTimes(start, start.add(const Duration(hours: 1))), isNull);
    expect(validateEventTimes(start, start), 'O fim precisa ser depois do início.');
  });
}
