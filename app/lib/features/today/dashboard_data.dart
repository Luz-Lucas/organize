import 'package:intl/intl.dart';

import '../../data/location_repository.dart';
import '../../domain/agenda.dart';
import '../../domain/calendar_event.dart';
import '../../domain/home_presence.dart';
import '../../domain/task_item.dart';
import '../../domain/user_settings.dart';

/// Lógica pura do painel da Início (sem Flutter): "agora e a seguir", próxima
/// prova, tarefas em destaque e a faixa de presença.

/// Mesma regra de título dos widgets Android (`widget_snapshot.dart`, kind
/// `prova`): começa com "prova" ou "np" + dígito, ignorando maiúsculas.
final _examRe = RegExp(r'^(prova|np\d)', caseSensitive: false);

bool isExamTitle(String title) => _examRe.hasMatch(title.trim());

DateTime _utcDate(DateTime d) => DateTime.utc(d.year, d.month, d.day);

/// Diferença em dias de calendário (imune a horário de verão).
int calendarDaysBetween(DateTime from, DateTime to) =>
    _utcDate(to).difference(_utcDate(from)).inDays;

/// "hoje", "amanhã", "ontem" ou "qua., 14 out.".
String dayLabel(DateTime d, DateTime now) {
  final diff = calendarDaysBetween(now, d);
  if (diff == 0) return 'hoje';
  if (diff == 1) return 'amanhã';
  if (diff == -1) return 'ontem';
  return DateFormat('EEE, d MMM', 'pt_BR').format(d);
}

String hm(DateTime d) => DateFormat.Hm('pt_BR').format(d);

// --- Agora e a seguir -------------------------------------------------------

class NowNext {
  const NowNext({
    required this.allDay,
    required this.current,
    required this.upcoming,
    required this.todayCount,
    required this.nextDayEvent,
  });

  /// Eventos de dia inteiro de hoje.
  final List<CalendarEvent> allDay;

  /// Eventos com horário em andamento agora.
  final List<CalendarEvent> current;

  /// Eventos com horário que ainda vão começar hoje (todos, em ordem).
  final List<CalendarEvent> upcoming;

  /// Quantos eventos (de qualquer tipo) tocam o dia de hoje.
  final int todayCount;

  /// Primeiro evento de um dia depois de hoje (para a agenda livre).
  final CalendarEvent? nextDayEvent;

  /// Nada em andamento, nada por vir e nenhum evento de dia inteiro.
  bool get nothingLeft => allDay.isEmpty && current.isEmpty && upcoming.isEmpty;

  /// Hoje não tem evento algum.
  bool get freeDay => todayCount == 0;
}

NowNext buildNowNext(DateTime now, Iterable<CalendarEvent> events) {
  final today = eventsOnDay(events, now);
  final tomorrow = DateTime(now.year, now.month, now.day + 1);
  final future = events.where((e) => !e.startsAt.isBefore(tomorrow)).toList()
    ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  final timed = today.where((e) => !e.allDay);
  return NowNext(
    allDay: today.where((e) => e.allDay).toList(),
    current: timed.where((e) => !e.startsAt.isAfter(now) && e.endsAt.isAfter(now)).toList(),
    upcoming: timed.where((e) => e.startsAt.isAfter(now)).toList(),
    todayCount: today.length,
    nextDayEvent: future.isEmpty ? null : future.first,
  );
}

// --- Próxima prova ----------------------------------------------------------

/// Janela de busca da próxima prova, em dias.
const examWindowDays = 30;

class ExamInfo {
  const ExamInfo({required this.event, required this.days, required this.inProgress});

  final CalendarEvent event;

  /// Dias de calendário até o início (0 = hoje).
  final int days;
  final bool inProgress;
}

ExamInfo? nextExam(DateTime now, Iterable<CalendarEvent> events) {
  final candidates = events.where((e) {
    if (!isExamTitle(e.title) || !e.endsAt.isAfter(now)) return false;
    return calendarDaysBetween(now, e.startsAt) <= examWindowDays;
  }).toList()
    ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  if (candidates.isEmpty) return null;
  final e = candidates.first;
  final days = calendarDaysBetween(now, e.startsAt);
  return ExamInfo(
    event: e,
    days: days < 0 ? 0 : days,
    inProgress: !e.allDay && !e.startsAt.isAfter(now),
  );
}

/// "hoje às 10:00", "amanhã às 10:00", "em 5 dias" ou "em andamento".
String examWhen(ExamInfo info) {
  if (info.inProgress) return 'em andamento';
  final time = info.event.allDay ? '' : ' às ${hm(info.event.startsAt)}';
  return switch (info.days) {
    0 => 'hoje$time',
    1 => 'amanhã$time',
    final n => 'em $n dias',
  };
}

// --- Tarefas ----------------------------------------------------------------

/// Quantas tarefas o cartão mostra.
const dashboardTaskLimit = 5;

class TaskPicks {
  const TaskPicks({
    required this.overdue,
    required this.today,
    required this.doing,
    required this.hidden,
    required this.pending,
  });

  /// Já limitadas a [dashboardTaskLimit] no total.
  final List<TaskItem> overdue;
  final List<TaskItem> today;
  final List<TaskItem> doing;

  /// Quantas tarefas em destaque ficaram de fora do limite.
  final int hidden;

  /// Total de tarefas não concluídas.
  final int pending;

  int get shown => overdue.length + today.length + doing.length;
}

/// Atrasadas, para hoje e em andamento (nessa ordem), até [dashboardTaskLimit].
TaskPicks pickDashboardTasks(DateTime now, Iterable<TaskItem> tasks) {
  final groups = groupTasks(tasks, now);
  final overdue = groups[TaskGroup.atrasadas]!;
  final today = groups[TaskGroup.hoje]!;
  final taken = {for (final t in [...overdue, ...today]) t.id};
  final doing = tasks.where((t) => t.status == TaskStatus.doing && !taken.contains(t.id)).toList()
    ..sort((a, b) {
      if (a.dueAt == null && b.dueAt == null) return a.title.compareTo(b.title);
      if (a.dueAt == null) return 1;
      if (b.dueAt == null) return -1;
      return a.dueAt!.compareTo(b.dueAt!);
    });
  final total = overdue.length + today.length + doing.length;
  var room = dashboardTaskLimit;
  List<TaskItem> take(List<TaskItem> l) {
    final out = l.take(room).toList();
    room -= out.length;
    return out;
  }

  final o = take(overdue), t = take(today), d = take(doing);
  final pending = tasks.where((t) => !t.isDone).length;
  return TaskPicks(
    overdue: o,
    today: t,
    doing: d,
    hidden: total - (o.length + t.length + d.length),
    pending: pending,
  );
}

// --- Presença ---------------------------------------------------------------

/// Texto da faixa de presença; null quando a casa não está definida.
class PresenceChip {
  const PresenceChip(this.state, this.label);

  final PresenceState state;
  final String label;
}

PresenceChip? presenceChip({
  required UserSettings? settings,
  required LocationReport? last,
  required DateTime now,
}) {
  if (settings == null || !settings.hasHome) return null;
  final status = presenceStatus(
    home: settings.home,
    radiusM: settings.homeRadiusM,
    requireHome: true,
    last: last,
    now: now,
  );
  return switch (status.state) {
    PresenceState.home => const PresenceChip(PresenceState.home, 'Em casa'),
    PresenceState.away => PresenceChip(
        PresenceState.away,
        status.distanceM == null ? 'Fora de casa' : 'Fora (a ${formatDistance(status.distanceM!)})',
      ),
    _ => const PresenceChip(PresenceState.unknown, 'Local indisponível'),
  };
}
