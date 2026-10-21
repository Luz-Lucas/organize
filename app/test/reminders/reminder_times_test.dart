import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/domain/calendar_event.dart';
import 'package:organizacional/domain/task_item.dart';
import 'package:organizacional/domain/user_settings.dart';
import 'package:organizacional/reminders/reminder_times.dart';

// Mesmos casos de bridge/test/reminders.test.ts. Os horários são locais (o teste
// roda com TZ=America/Sao_Paulo, como o app no celular do usuário).
DateTime at(String date, String hhmm) {
  final d = date.split('-').map(int.parse).toList();
  final h = hhmm.split(':').map(int.parse).toList();
  return DateTime(d[0], d[1], d[2], h[0], h[1]);
}

UserSettings dnd({bool enabled = true, String start = '23:00', String end = '10:00'}) {
  int m(String s) {
    final p = s.split(':').map(int.parse).toList();
    return p[0] * 60 + p[1];
  }

  return UserSettings(dndEnabled: enabled, dndStart: m(start), dndEnd: m(end));
}

CalendarEvent event({
  String date = '2026-10-22',
  String start = '15:00',
  List<int> reminders = const [30],
  bool allDay = false,
  String id = 'e1',
}) {
  final s = at(date, start);
  return CalendarEvent(
    id: id,
    title: 'Reunião',
    startsAt: s,
    endsAt: s.add(const Duration(hours: 1)),
    allDay: allDay,
    reminders: reminders,
  );
}

TaskItem task({
  String due = '2026-10-22 18:00',
  TaskPriority priority = TaskPriority.media,
  TaskStatus status = TaskStatus.todo,
  bool noDue = false,
  List<int> reminders = const [60],
  String id = 't1',
}) {
  final p = due.split(' ');
  return TaskItem(
    id: id,
    title: 'Pagar a luz',
    status: status,
    priority: priority,
    dueAt: noDue ? null : at(p[0], p[1]),
    reminders: reminders,
  );
}

final now = at('2026-10-21', '08:00');

List<ReminderFire> fires({
  List<TaskItem> tasks = const [],
  List<CalendarEvent> events = const [],
  UserSettings? settings,
  DateTime? clock,
}) =>
    reminderFires(tasks: tasks, events: events, settings: settings ?? dnd(), now: clock ?? now);

void main() {
  group('eventos', () {
    test('evento 15:00 com {30} avisa às 14:30', () {
      final f = fires(events: [event()]).single;
      expect(f.kind, ReminderKind.event);
      expect(f.itemId, 'e1');
      expect(f.title, 'Reunião');
      expect(f.dateOnly, isFalse);
      expect(f.fireAt, at('2026-10-22', '14:30'));
      expect(f.itemAt, at('2026-10-22', '15:00'));
    });

    test('evento 08:30 com {30}: 08:00 cai no não perturbe, 10:00 passa do horário e é descartado', () {
      expect(fires(events: [event(start: '08:30')]), isEmpty);
    });

    test('evento 11:00 com {1440} avisa na véspera às 11:00', () {
      final f = fires(events: [event(start: '11:00', reminders: [1440])]).single;
      expect(f.fireAt, at('2026-10-21', '11:00'));
    });

    test('evento 10:20 com {60,30}: 09:20 e 09:50 viram um único 10:00', () {
      final r = fires(events: [event(start: '10:20', reminders: [60, 30])]);
      expect(r.map((f) => f.fireAt), [at('2026-10-22', '10:00')]);
    });

    test('não perturbe desligado mantém 08:00', () {
      final r = fires(events: [event(start: '08:30')], settings: dnd(enabled: false));
      expect(r.map((f) => f.fireAt), [at('2026-10-22', '08:00')]);
    });

    test('não perturbe 22:00 -> 07:00 com aviso às 23:30 vai para 07:00 do dia seguinte', () {
      final r = fires(
        events: [event(date: '2026-10-23', start: '23:30', reminders: [1440])],
        settings: dnd(start: '22:00', end: '07:00'),
      );
      expect(r.map((f) => f.fireAt), [at('2026-10-23', '07:00')]);
    });

    test('aviso de madrugada sobe para o fim do intervalo do mesmo dia, se ainda for antes do item', () {
      final s = dnd(start: '22:00', end: '07:00');
      final r = fires(events: [event(date: '2026-10-23', start: '03:30', reminders: [30, 1440])], settings: s);
      expect(r.map((f) => f.fireAt), [at('2026-10-22', '07:00')]);
      final r2 = fires(events: [event(date: '2026-10-23', start: '09:00', reminders: [1440])], settings: s);
      expect(r2.map((f) => f.fireAt), [at('2026-10-22', '09:00')]);
    });

    test('dia inteiro não avisa', () {
      expect(fires(events: [event(allDay: true)]), isEmpty);
    });

    test('sem lembretes não avisa', () {
      expect(fires(events: [event(reminders: const [])]), isEmpty);
    });

    test('remove avisos que já passaram', () {
      final r = fires(
        events: [event(date: '2026-10-21', start: '12:00', reminders: [30, 15, 1440])],
        clock: at('2026-10-21', '11:40'),
      );
      expect(r.map((f) => f.fireAt), [at('2026-10-21', '11:45')]);
    });
  });

  group('tarefas', () {
    test('tarefa com hora avisa dueAt - m', () {
      final f = fires(tasks: [task()]).single;
      expect(f.kind, ReminderKind.task);
      expect(f.itemId, 't1');
      expect(f.dateOnly, isFalse);
      expect(f.fireAt, at('2026-10-22', '17:00'));
    });

    test('tarefa só com data e prioridade alta avisa às 10:00 do dia do prazo', () {
      final f = fires(tasks: [task(due: '2026-10-22 23:59', priority: TaskPriority.alta)]).single;
      expect(f.dateOnly, isTrue);
      expect(f.fireAt, at('2026-10-22', '10:00'));
      expect(f.itemAt, at('2026-10-22', '23:59'));
    });

    test('tarefa só com data e prioridade média não avisa', () {
      expect(fires(tasks: [task(due: '2026-10-22 23:59')]), isEmpty);
    });

    test('tarefa concluída ou sem prazo não avisa', () {
      expect(fires(tasks: [task(status: TaskStatus.done), task(id: 't2', noDue: true)]), isEmpty);
    });

    test('tarefa só com data alta, com o não perturbe cobrindo 10:00, sobe para o fim do intervalo', () {
      final f = fires(
        tasks: [task(due: '2026-10-22 23:59', priority: TaskPriority.alta)],
        settings: dnd(start: '08:00', end: '12:00'),
      ).single;
      expect(f.fireAt, at('2026-10-22', '12:00'));
    });
  });

  test('ordena por horário do aviso', () {
    final r = fires(events: [event(start: '15:00')], tasks: [task()]);
    expect(r.map((f) => f.kind), [ReminderKind.event, ReminderKind.task]);
  });
}
