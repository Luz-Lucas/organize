import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/domain/calendar_event.dart';
import 'package:organizacional/domain/task_item.dart';
import 'package:organizacional/domain/user_settings.dart';
import 'package:organizacional/reminders/reminder_scheduler.dart';
import 'package:organizacional/reminders/reminder_times.dart';

class FakeSink implements ReminderSink {
  final replaced = <List<ScheduledReminder>>[];
  final permissionRequests = <bool>[];
  @override
  Future<void> replaceAll(List<ScheduledReminder> reminders) async => replaced.add(reminders);
  @override
  Future<void> requestPermission({bool force = false}) async => permissionRequests.add(force);
}

CalendarEvent event(String id, DateTime start, {List<int> reminders = const [30], String title = 'Reunião'}) =>
    CalendarEvent(
      id: id,
      title: title,
      startsAt: start,
      endsAt: start.add(const Duration(hours: 1)),
      reminders: reminders,
    );

void main() {
  final now = DateTime(2026, 10, 21, 12);
  const settings = UserSettings();

  ReminderFire fire(ReminderKind kind, DateTime fireAt, DateTime itemAt, {bool dateOnly = false, String id = 'x'}) =>
      ReminderFire(kind: kind, itemId: id, title: 'Título', fireAt: fireAt, itemAt: itemAt, dateOnly: dateOnly);

  group('id da notificação', () {
    test('é estável para o mesmo item e horário e muda com o horário', () {
      final a = fire(ReminderKind.event, DateTime(2026, 10, 22, 14, 30), DateTime(2026, 10, 22, 15));
      final b = fire(ReminderKind.event, DateTime(2026, 10, 22, 14, 30), DateTime(2026, 10, 22, 15));
      final c = fire(ReminderKind.event, DateTime(2026, 10, 22, 14, 45), DateTime(2026, 10, 22, 15));
      expect(reminderNotificationId(a), reminderNotificationId(b));
      expect(reminderNotificationId(a), isNot(reminderNotificationId(c)));
    });

    test('muda com o tipo e o item, e cabe em 32 bits positivos', () {
      final t = DateTime(2026, 10, 22, 14, 30);
      final ev = fire(ReminderKind.event, t, t, id: 'abc');
      final tk = fire(ReminderKind.task, t, t, id: 'abc');
      final other = fire(ReminderKind.event, t, t, id: 'abd');
      expect({reminderNotificationId(ev), reminderNotificationId(tk), reminderNotificationId(other)}, hasLength(3));
      for (final f in [ev, tk, other]) {
        expect(reminderNotificationId(f), inInclusiveRange(0, 0x7fffffff));
      }
    });
  });

  group('texto', () {
    test('evento no mesmo dia: "Começa às 15:00"', () {
      final f = fire(ReminderKind.event, DateTime(2026, 10, 22, 14, 30), DateTime(2026, 10, 22, 15));
      expect(reminderBody(f), 'Começa às 15:00');
    });

    test('evento no dia seguinte: "Amanhã às 15:00"', () {
      final f = fire(ReminderKind.event, DateTime(2026, 10, 21, 15), DateTime(2026, 10, 22, 15));
      expect(reminderBody(f), 'Amanhã às 15:00');
    });

    test('tarefa com hora: "Prazo às 18:00"', () {
      final f = fire(ReminderKind.task, DateTime(2026, 10, 22, 17), DateTime(2026, 10, 22, 18));
      expect(reminderBody(f), 'Prazo às 18:00');
    });

    test('tarefa só com data: "Vence hoje"', () {
      final f = fire(ReminderKind.task, DateTime(2026, 10, 22, 10), DateTime(2026, 10, 22, 23, 59), dateOnly: true);
      expect(reminderBody(f), 'Vence hoje');
    });
  });

  group('plano', () {
    test('título do item, texto, horário e payload; só tarefa tem o botão Concluir', () {
      final tasks = [
        TaskItem(id: 't1', title: 'Pagar a luz', dueAt: DateTime(2026, 10, 22, 18)),
      ];
      final events = [event('e1', DateTime(2026, 10, 22, 15), title: 'Dentista')];
      final plan = planReminders(tasks: tasks, events: events, settings: settings, now: now);
      expect(plan, hasLength(2));
      final ev = plan[0];
      expect(ev.title, 'Dentista');
      expect(ev.body, 'Começa às 15:00');
      expect(ev.fireAt, DateTime(2026, 10, 22, 14, 30));
      expect(ev.payload, 'event:e1');
      expect(ev.canComplete, isFalse);
      final tk = plan[1];
      expect(tk.title, 'Pagar a luz');
      expect(tk.body, 'Prazo às 18:00');
      expect(tk.fireAt, DateTime(2026, 10, 22, 17));
      expect(tk.payload, 'task:t1');
      expect(tk.canComplete, isTrue);
    });

    test('o horizonte é de 3 dias: avisos além dele ficam para depois', () {
      final events = [
        event('perto', DateTime(2026, 10, 24, 11)), // aviso 24/10 10:30 < 24/10 12:00
        event('longe', DateTime(2026, 10, 24, 13)), // aviso 24/10 12:30 > agora + 3 dias
      ];
      final plan = planReminders(tasks: const [], events: events, settings: settings, now: now);
      expect(plan.map((p) => p.payload), ['event:perto']);
    });

    test('chave do celular desligada: nada agendado', () {
      final events = [event('e1', DateTime(2026, 10, 22, 15))];
      final plan = planReminders(
          tasks: const [], events: events, settings: const UserSettings(remindersPhone: false), now: now);
      expect(plan, isEmpty);
    });
  });

  group('rescheduleReminders', () {
    test('troca tudo no sink e devolve quantos agendou', () async {
      final sink = FakeSink();
      final n = await rescheduleReminders(
        sink: sink,
        tasks: const [],
        events: [event('e1', DateTime(2026, 10, 22, 15))],
        settings: settings,
        now: now,
      );
      expect(n, 1);
      expect(sink.replaced.single.single.payload, 'event:e1');
    });

    test('com a chave desligada limpa o que estava agendado', () async {
      final sink = FakeSink();
      final n = await rescheduleReminders(
        sink: sink,
        tasks: const [],
        events: [event('e1', DateTime(2026, 10, 22, 15))],
        settings: const UserSettings(remindersPhone: false),
        now: now,
      );
      expect(n, 0);
      expect(sink.replaced.single, isEmpty);
    });
  });
}
