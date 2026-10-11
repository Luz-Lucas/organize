import 'agenda.dart';
import 'alexa.dart';
import 'task_item.dart';

class SystemNotice {
  const SystemNotice({required this.id, required this.text, this.route});

  final String id;
  final String text;
  final String? route;
}

/// Avisos gerados pelo app (tarefas atrasadas, despertares próximos, ponte fora do ar).
List<SystemNotice> systemNotices({
  required DateTime now,
  required Iterable<TaskItem> tasks,
  required BridgeStatus? bridge,
  required List<WakePlan> wakePlans,
}) {
  final out = <SystemNotice>[];
  final overdue = groupTasks(tasks, now)[TaskGroup.atrasadas]!.length;
  if (overdue > 0) {
    out.add(SystemNotice(
      id: 'overdue',
      text: overdue == 1 ? '1 tarefa atrasada' : '$overdue tarefas atrasadas',
      route: '/tarefas',
    ));
  }
  final warning = bridgeWarning(bridge, wakePlans, now);
  if (warning != null) {
    out.add(SystemNotice(id: 'bridge', text: warning, route: '/casa'));
  }
  final limit = now.add(const Duration(hours: 24));
  for (final p in wakePlans.where((p) => p.enabled)) {
    for (var offset = 0; offset <= 1; offset++) {
      final at = DateTime(now.year, now.month, now.day + offset, p.hour, p.minute);
      if (at.isAfter(now) && !at.isAfter(limit) && p.days.contains(at.weekday)) {
        final when = offset == 0 ? 'hoje' : 'amanhã';
        out.add(SystemNotice(
          id: 'wake-${p.id}',
          text: 'Despertar “${p.label}” $when às ${twoDigits(p.hour)}:${twoDigits(p.minute)}',
          route: '/casa',
        ));
        break;
      }
    }
  }
  return out;
}
