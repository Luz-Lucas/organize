import 'package:intl/intl.dart';

import '../../data/location_repository.dart';
import '../../domain/agenda.dart';
import '../../domain/calendar_event.dart';
import '../../domain/event_tag.dart';
import '../../domain/home_presence.dart';
import '../../domain/task_item.dart';
import '../../domain/task_series.dart';
import '../../domain/user_settings.dart';
import '../../domain/workout.dart';

/// Lógica pura do painel da Início (sem Flutter): "Para hoje" e a faixa de presença.

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

// --- Para hoje --------------------------------------------------------------

/// Quantas tarefas o cartão "Para hoje" mostra.
const todayTaskLimit = 5;

/// Séries que se repetem tantas vezes na janela de 7 dias são rotina (remédio, ponto) e não entram.
const _frequentSeriesMin = 5;

class TodayPlan {
  const TodayPlan({required this.events, required this.tasks, required this.moreTasks});

  /// Eventos de hoje que importam: dia inteiro primeiro, depois por início.
  final List<CalendarEvent> events;

  /// Tarefas atrasadas ou com prazo hoje, por prazo, até [todayTaskLimit]. De cada série de tarefas
  /// conta só a próxima pendente.
  final List<TaskItem> tasks;

  /// Quantas tarefas ficaram de fora do limite.
  final int moreTasks;

  bool get isEmpty => events.isEmpty && tasks.isEmpty;
}

/// O que importa hoje. Ficam de fora dos eventos: academia (tem cartão próprio), etiqueta de papel
/// `secondary` e séries com 5 ou mais ocorrências em `[início de hoje, +7 dias)` na lista recebida.
TodayPlan buildTodayPlan(
  DateTime now,
  Iterable<CalendarEvent> events,
  Map<String, EventTag> tags,
  Iterable<TaskItem> tasks,
) {
  final start = DateTime(now.year, now.month, now.day);
  final windowEnd = DateTime(now.year, now.month, now.day + 7);
  final perSeries = <String, int>{};
  for (final e in events) {
    final id = e.seriesId;
    if (id != null && !e.startsAt.isBefore(start) && e.startsAt.isBefore(windowEnd)) {
      perSeries[id] = (perSeries[id] ?? 0) + 1;
    }
  }
  bool matters(CalendarEvent e) {
    if (isGymEvent(e, tags)) return false;
    if (e.tagId != null && tags[e.tagId]?.role == EventTagRole.secondary) return false;
    final id = e.seriesId;
    return id == null || (perSeries[id] ?? 0) < _frequentSeriesMin;
  }

  final today = eventsOnDay(events, now).where(matters).toList();
  final ordered = [...today.where((e) => e.allDay), ...today.where((e) => !e.allDay)];

  final groups = groupTasks(nextPendingPerSeries(tasks), now);
  final due = [...groups[TaskGroup.atrasadas]!, ...groups[TaskGroup.hoje]!];
  return TodayPlan(
    events: ordered,
    tasks: due.take(todayTaskLimit).toList(),
    moreTasks: due.length > todayTaskLimit ? due.length - todayTaskLimit : 0,
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
