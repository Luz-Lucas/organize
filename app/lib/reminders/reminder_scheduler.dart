import '../domain/calendar_event.dart';
import '../domain/task_item.dart';
import '../domain/user_settings.dart';
import 'reminder_actions.dart';
import 'reminder_times.dart';

/// Só os avisos dos próximos 3 dias ficam agendados no sistema; o resto entra nas reagendas seguintes.
const reminderHorizon = Duration(days: 3);

/// Uma notificação pronta para o sistema.
class ScheduledReminder {
  const ScheduledReminder({
    required this.id,
    required this.fireAt,
    required this.title,
    required this.body,
    required this.payload,
    required this.canComplete,
  });

  final int id;
  final DateTime fireAt;
  final String title;
  final String body;
  final String payload;

  /// Tarefa: a notificação tem o botão "Concluir".
  final bool canComplete;
}

/// Destino dos lembretes do celular (plugin de notificações no Android; sem-op nos testes e fora do Android).
abstract interface class ReminderSink {
  /// Pede a permissão de notificações (Android 13+). Sem [force], só na primeira vez.
  Future<void> requestPermission({bool force = false});

  /// Cancela os avisos agendados e agenda [reminders] no lugar.
  Future<void> replaceAll(List<ScheduledReminder> reminders);
}

class NoopReminderSink implements ReminderSink {
  const NoopReminderSink();

  @override
  Future<void> requestPermission({bool force = false}) async {}

  @override
  Future<void> replaceAll(List<ScheduledReminder> reminders) async {}
}

/// Id estável (FNV-1a de tipo + item + horário), positivo e de 31 bits: o mesmo aviso mantém o id entre reagendas.
int reminderNotificationId(ReminderFire f) {
  var h = 0x811c9dc5;
  for (final unit in '${f.kind.name}|${f.itemId}|${f.fireAt.millisecondsSinceEpoch}'.codeUnits) {
    h = ((h ^ unit) * 0x01000193) & 0xffffffff;
  }
  return h & 0x7fffffff;
}

String _clock(DateTime d) => formatMinutesOfDay(d.hour * 60 + d.minute);

/// "Começa às 15:00" / "Amanhã às 15:00" (evento); "Prazo às 18:00" (tarefa); "Vence hoje" (tarefa só com data).
String reminderBody(ReminderFire f) {
  final fire = f.fireAt, item = f.itemAt;
  final later = DateTime(item.year, item.month, item.day).isAfter(DateTime(fire.year, fire.month, fire.day));
  if (f.kind == ReminderKind.event) return later ? 'Amanhã às ${_clock(item)}' : 'Começa às ${_clock(item)}';
  if (f.dateOnly) return later ? 'Vence amanhã' : 'Vence hoje';
  return later ? 'Prazo amanhã às ${_clock(item)}' : 'Prazo às ${_clock(item)}';
}

ScheduledReminder scheduledReminderFor(ReminderFire f) => ScheduledReminder(
      id: reminderNotificationId(f),
      fireAt: f.fireAt,
      title: f.title,
      body: reminderBody(f),
      payload: reminderPayload(f.kind, f.itemId),
      canComplete: f.kind == ReminderKind.task,
    );

/// O que deve estar agendado agora: avisos dentro do horizonte; nada com a chave do celular desligada.
List<ScheduledReminder> planReminders({
  required List<TaskItem> tasks,
  required List<CalendarEvent> events,
  required UserSettings settings,
  required DateTime now,
}) {
  if (!settings.remindersPhone) return const [];
  final limit = now.add(reminderHorizon);
  return [
    for (final f in reminderFires(tasks: tasks, events: events, settings: settings, now: now))
      if (!f.fireAt.isAfter(limit)) scheduledReminderFor(f),
  ];
}

/// Cancela e reagenda tudo do horizonte; devolve quantos avisos ficaram agendados.
Future<int> rescheduleReminders({
  required ReminderSink sink,
  required List<TaskItem> tasks,
  required List<CalendarEvent> events,
  required UserSettings settings,
  required DateTime now,
}) async {
  final plan = planReminders(tasks: tasks, events: events, settings: settings, now: now);
  await sink.replaceAll(plan);
  return plan.length;
}
