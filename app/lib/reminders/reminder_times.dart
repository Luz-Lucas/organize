import '../domain/calendar_event.dart';
import '../domain/task_item.dart';
import '../domain/user_settings.dart';

enum ReminderKind { task, event }

/// Um aviso a soar: o mesmo algoritmo de `bridge/src/reminders.ts` (`reminderFires`).
class ReminderFire {
  const ReminderFire({
    required this.kind,
    required this.itemId,
    required this.title,
    required this.fireAt,
    required this.itemAt,
    required this.dateOnly,
  });

  final ReminderKind kind;
  final String itemId;
  final String title;

  /// Quando o aviso deve soar (já ajustado pelo não perturbe).
  final DateTime fireAt;

  /// Horário do item (início do evento, prazo da tarefa; 23:59 do dia para tarefa só com data).
  final DateTime itemAt;

  /// Tarefa só com data (prazo às 23:59 local).
  final bool dateOnly;
}

/// Tarefa só com data avisa neste horário local do dia do prazo (só se prioridade alta).
const dateOnlyReminderMinutes = 10 * 60;
const _dateOnlyDueMinutes = 23 * 60 + 59;

int _minutesOfDay(DateTime d) => d.hour * 60 + d.minute;

DateTime _at(DateTime day, int minutes, {int addDays = 0}) =>
    DateTime(day.year, day.month, day.day + addDays, minutes ~/ 60, minutes % 60);

/// Passa o aviso para o fim do não perturbe quando ele cai dentro de [início, fim)
/// (que pode atravessar a meia-noite). `null` se o novo horário não é anterior ao do item.
DateTime? _applyDnd(DateTime fireAt, DateTime itemAt, UserSettings s) {
  if (!s.dndEnabled) return fireAt;
  final start = s.dndStart, end = s.dndEnd;
  if (start == end) return fireAt;
  final m = _minutesOfDay(fireAt);
  final inside = start < end ? (m >= start && m < end) : (m >= start || m < end);
  if (!inside) return fireAt;
  final moved = _at(fireAt, end, addDays: start > end && m >= start ? 1 : 0);
  return moved.isBefore(itemAt) ? moved : null;
}

/// Avisos de tarefas e eventos que ainda vão soar depois de [now], em horário local, por ordem.
/// Tarefa concluída/sem prazo e evento de dia inteiro não avisam; tarefa só com data avisa às 10:00
/// do dia do prazo, só se for de prioridade alta.
List<ReminderFire> reminderFires({
  required List<TaskItem> tasks,
  required List<CalendarEvent> events,
  required UserSettings settings,
  required DateTime now,
}) {
  final candidates = <ReminderFire>[];
  for (final t in tasks) {
    final due = t.dueAt?.toLocal();
    if (t.isDone || due == null) continue;
    if (_minutesOfDay(due) == _dateOnlyDueMinutes) {
      if (t.priority != TaskPriority.alta) continue;
      candidates.add(ReminderFire(
        kind: ReminderKind.task,
        itemId: t.id,
        title: t.title,
        fireAt: _at(due, dateOnlyReminderMinutes),
        itemAt: due,
        dateOnly: true,
      ));
      continue;
    }
    for (final m in t.reminders) {
      candidates.add(ReminderFire(
        kind: ReminderKind.task,
        itemId: t.id,
        title: t.title,
        fireAt: due.subtract(Duration(minutes: m)),
        itemAt: due,
        dateOnly: false,
      ));
    }
  }
  for (final e in events) {
    if (e.allDay) continue;
    final start = e.startsAt.toLocal();
    for (final m in e.reminders) {
      candidates.add(ReminderFire(
        kind: ReminderKind.event,
        itemId: e.id,
        title: e.title,
        fireAt: start.subtract(Duration(minutes: m)),
        itemAt: start,
        dateOnly: false,
      ));
    }
  }
  final seen = <String>{};
  final out = <ReminderFire>[];
  for (final c in candidates) {
    final fireAt = _applyDnd(c.fireAt, c.itemAt, settings);
    if (fireAt == null || !fireAt.isAfter(now)) continue;
    if (!seen.add('${c.kind.name}:${c.itemId}:${fireAt.millisecondsSinceEpoch}')) continue;
    out.add(ReminderFire(
      kind: c.kind,
      itemId: c.itemId,
      title: c.title,
      fireAt: fireAt,
      itemAt: c.itemAt,
      dateOnly: c.dateOnly,
    ));
  }
  out.sort((a, b) => a.fireAt.compareTo(b.fireAt));
  return out;
}
