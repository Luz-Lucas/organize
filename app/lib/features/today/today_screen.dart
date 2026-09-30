import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../domain/agenda.dart';
import '../../domain/news.dart';
import '../../ui/common.dart';
import '../../ui/event_tile.dart';
import '../../ui/news_tile.dart';
import '../../ui/task_tile.dart';

class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  Timer? _midnightTimer;

  @override
  void initState() {
    super.initState();
    _scheduleMidnightRollover();
  }

  @override
  void dispose() {
    _midnightTimer?.cancel();
    super.dispose();
  }

  /// Agenda um Timer para a próxima meia-noite local, para que a data e as
  /// listas de "Hoje" atualizem mesmo sem nenhum stream emitir de novo
  /// (ex.: app deixado aberto durante a noite).
  void _scheduleMidnightRollover() {
    final now = ref.read(clockProvider)();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    _midnightTimer = Timer(nextMidnight.difference(now), () {
      if (!mounted) return;
      setState(_scheduleMidnightRollover);
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(clockProvider)();
    final events = ref.watch(eventsFromProvider(startOfDay(now)));
    final tasks = ref.watch(tasksProvider);
    final spaces = ref.watch(spacesProvider);
    final headlines = (ref.watch(newsFeedProvider).value ?? const <NewsItem>[]).take(3).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(now)),
        actions: [
          IconButton(
            key: const Key('open-news'),
            tooltip: 'Notícias',
            icon: const Icon(Icons.newspaper_outlined),
            onPressed: () => context.go('/noticias'),
          ),
        ],
      ),
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
                if (headlines.isNotEmpty) ...[
                  const SectionHeader('Manchetes'),
                  for (final n in headlines) NewsTile(key: ValueKey('news-${n.id}'), item: n),
                ],
              ],
            );
          })),
    );
  }
}
