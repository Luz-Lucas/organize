import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/domain/calendar_event.dart';
import 'package:organizacional/domain/task_item.dart';
import 'package:organizacional/domain/user_settings.dart';
import 'package:organizacional/reminders/reminder_background.dart';
import 'package:organizacional/reminders/reminder_scheduler.dart';

class FakeSink implements ReminderSink {
  final replaced = <List<ScheduledReminder>>[];
  @override
  Future<void> replaceAll(List<ScheduledReminder> reminders) async => replaced.add(reminders);
  @override
  Future<void> requestPermission({bool force = false}) async {}
}

class FakeSource implements ReminderDataSource {
  FakeSource({this.fail = false, this.settingsValue = const UserSettings()});
  final bool fail;
  final UserSettings settingsValue;
  DateTime? eventsFrom;
  DateTime? eventsTo;

  @override
  Future<List<TaskItem>> openTasks() async {
    if (fail) throw Exception('sem rede');
    return [TaskItem(id: 't1', title: 'Pagar a luz', dueAt: DateTime(2026, 10, 22, 18))];
  }

  @override
  Future<List<CalendarEvent>> events(DateTime from, DateTime to) async {
    if (fail) throw Exception('sem rede');
    eventsFrom = from;
    eventsTo = to;
    return [
      CalendarEvent(
        id: 'e1',
        title: 'Dentista',
        startsAt: DateTime(2026, 10, 22, 15),
        endsAt: DateTime(2026, 10, 22, 16),
      ),
    ];
  }

  @override
  Future<UserSettings> settings() async {
    if (fail) throw Exception('sem rede');
    return settingsValue;
  }
}

void main() {
  final now = DateTime(2026, 10, 21, 12);

  test('busca os dados e reagenda tudo no sink', () async {
    final sink = FakeSink();
    final source = FakeSource();
    final ok = await runReminderReschedule(source: source, sink: sink, now: now);
    expect(ok, isTrue);
    expect(sink.replaced.single.map((r) => r.payload), ['event:e1', 'task:t1']);
    // A consulta de eventos cobre o horizonte de 3 dias mais a antecedência de 1 dia.
    expect(source.eventsFrom!.isAfter(now), isFalse);
    expect(source.eventsTo!.isBefore(now.add(reminderHorizon + const Duration(days: 1))), isFalse);
  });

  test('chave do celular desligada: limpa os avisos', () async {
    final sink = FakeSink();
    final ok = await runReminderReschedule(
      source: FakeSource(settingsValue: const UserSettings(remindersPhone: false)),
      sink: sink,
      now: now,
    );
    expect(ok, isTrue);
    expect(sink.replaced.single, isEmpty);
  });

  test('sem sessão (fonte nula): cancela tudo', () async {
    final sink = FakeSink();
    final ok = await runReminderReschedule(source: null, sink: sink, now: now);
    expect(ok, isTrue);
    expect(sink.replaced.single, isEmpty);
  });

  test('falha ao buscar (sem rede): mantém o que já estava agendado', () async {
    final sink = FakeSink();
    final ok = await runReminderReschedule(source: FakeSource(fail: true), sink: sink, now: now);
    expect(ok, isFalse);
    expect(sink.replaced, isEmpty);
  });
}
