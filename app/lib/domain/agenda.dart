import 'calendar_event.dart';
import 'task_item.dart';

DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime startOfWeek(DateTime d) =>
    DateTime(d.year, d.month, d.day - (d.weekday - DateTime.monday));

List<CalendarEvent> eventsOnDay(Iterable<CalendarEvent> events, DateTime day) {
  final start = DateTime(day.year, day.month, day.day);
  final end = DateTime(day.year, day.month, day.day + 1);
  bool overlaps(CalendarEvent e) =>
      e.startsAt.isBefore(end) &&
      (e.endsAt.isAfter(start) || !e.startsAt.isBefore(start));
  return events.where(overlaps).toList()
    ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
}

enum TaskGroup {
  atrasadas('Atrasadas'),
  hoje('Para hoje'),
  proximas('Próximas'),
  semData('Sem data'),
  concluidas('Concluídas');

  const TaskGroup(this.label);

  final String label;
}

Map<TaskGroup, List<TaskItem>> groupTasks(Iterable<TaskItem> tasks, DateTime now) {
  final start = DateTime(now.year, now.month, now.day);
  final end = DateTime(now.year, now.month, now.day + 1);
  final out = {for (final g in TaskGroup.values) g: <TaskItem>[]};
  for (final t in tasks) {
    final due = t.dueAt;
    final group = t.isDone
        ? TaskGroup.concluidas
        : due == null
            ? TaskGroup.semData
            : due.isBefore(start)
                ? TaskGroup.atrasadas
                : due.isBefore(end)
                    ? TaskGroup.hoje
                    : TaskGroup.proximas;
    out[group]!.add(t);
  }
  int byDue(TaskItem a, TaskItem b) => a.dueAt!.compareTo(b.dueAt!);
  out[TaskGroup.atrasadas]!.sort(byDue);
  out[TaskGroup.hoje]!.sort(byDue);
  out[TaskGroup.proximas]!.sort(byDue);
  out[TaskGroup.semData]!.sort((a, b) => a.title.compareTo(b.title));
  final epoch = DateTime(0);
  out[TaskGroup.concluidas]!
      .sort((a, b) => (b.completedAt ?? epoch).compareTo(a.completedAt ?? epoch));
  return out;
}

class DayAgenda {
  const DayAgenda({required this.events, required this.overdue, required this.dueToday});

  final List<CalendarEvent> events;
  final List<TaskItem> overdue;
  final List<TaskItem> dueToday;
}

DayAgenda buildDayAgenda({
  required DateTime now,
  required Iterable<CalendarEvent> events,
  required Iterable<TaskItem> tasks,
}) {
  final groups = groupTasks(tasks, now);
  return DayAgenda(
    events: eventsOnDay(events, now),
    overdue: groups[TaskGroup.atrasadas]!,
    dueToday: groups[TaskGroup.hoje]!,
  );
}

String? validateEventTimes(DateTime start, DateTime end) =>
    end.isAfter(start) ? null : 'O fim precisa ser depois do início.';

/// Fim de um evento montado a partir de dia + hora. Se cair no mesmo dia do
/// início mas não depois dele (ex.: 22:00 → 02:00), o fim vai para o dia seguinte.
DateTime resolveEventEnd(DateTime start, DateTime endDay, int endHour, int endMinute) {
  var end = DateTime(endDay.year, endDay.month, endDay.day, endHour, endMinute);
  final sameDay =
      endDay.year == start.year && endDay.month == start.month && endDay.day == start.day;
  if (sameDay && !end.isAfter(start)) {
    end = DateTime(end.year, end.month, end.day + 1, endHour, endMinute);
  }
  return end;
}
