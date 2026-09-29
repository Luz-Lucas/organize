import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../domain/agenda.dart';
import '../../ui/common.dart';
import '../../ui/event_tile.dart';
import '../../ui/task_tile.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider)();
    final events = ref.watch(eventsFromProvider(startOfDay(now)));
    final tasks = ref.watch(tasksProvider);
    final spaces = ref.watch(spacesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(now))),
      body: asyncView(events, (eventList) => asyncView(tasks, (taskList) {
            final names = {for (final s in spaces.value ?? const []) s.id: s.name};
            final agenda = buildDayAgenda(now: now, events: eventList, tasks: taskList);
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const SectionHeader('Aulas e eventos'),
                if (agenda.events.isEmpty) const EmptyHint('Nada na agenda hoje.'),
                for (final e in agenda.events) EventTile(event: e, spaceName: names[e.spaceId]),
                if (agenda.overdue.isNotEmpty) ...[
                  const SectionHeader('Atrasadas'),
                  for (final t in agenda.overdue)
                    TaskTile(key: ValueKey(t.id), task: t, spaceName: names[t.spaceId]),
                ],
                const SectionHeader('Para hoje'),
                if (agenda.dueToday.isEmpty) const EmptyHint('Nenhuma tarefa para hoje.'),
                for (final t in agenda.dueToday)
                  TaskTile(key: ValueKey(t.id), task: t, spaceName: names[t.spaceId]),
              ],
            );
          })),
    );
  }
}
