import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../domain/agenda.dart';
import '../../data/repository.dart';
import '../../domain/alexa.dart';
import '../../domain/notice.dart';
import '../../domain/system_notices.dart';
import '../../domain/task_item.dart';
import '../../domain/news.dart';
import '../../ui/common.dart';
import '../../ui/event_tile.dart';
import '../../ui/motif_painter.dart';
import '../../ui/news_tile.dart';
import '../../ui/org_theme.dart';
import '../../ui/org_widgets.dart';
import 'notice_board.dart';

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
    // Ao entrar em Hoje, relê as manchetes (o provider pode seguir vivo na troca de tela).
    ref.invalidate(newsFeedProvider);
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
      ref.invalidate(newsFeedProvider);
      setState(_scheduleMidnightRollover);
    });
  }

  String _greeting(DateTime now) {
    if (now.hour < 12) return 'Bom dia';
    if (now.hour < 18) return 'Boa tarde';
    return 'Boa noite';
  }

  Future<void> _toggle(TaskItem t, DateTime now) async {
    try {
      await ref
          .read(repositoryProvider)
          .upsertTask(t.moved(t.isDone ? TaskStatus.todo : TaskStatus.done, now));
    } on RepositoryException {
      if (mounted) showError(context, 'Não foi possível atualizar a tarefa.');
    }
  }

  Widget _taskRow(TaskItem t, String? spaceName, DateTime now) {
    final theme = Theme.of(context);
    final due = t.dueAt;
    final subtitle = [
      ?spaceName,
      if (due != null) DateFormat('d MMM', 'pt_BR').format(due),
    ].join(' · ');
    return ListTile(
      key: ValueKey(t.id),
      leading: Checkbox(
        key: ValueKey('task-check-${t.id}'),
        value: t.isDone,
        onChanged: (_) => _toggle(t, now),
      ),
      title: Text(t.title),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      onTap: () => context.go('/tarefas'),
      textColor: theme.colorScheme.onSurface,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final org = context.org;
    final now = ref.watch(clockProvider)();
    final events = ref.watch(eventsFromProvider(startOfDay(now)));
    final tasks = ref.watch(tasksProvider);
    final spaces = ref.watch(spacesProvider);
    final headlines = (ref.watch(newsFeedProvider).value ?? const <NewsItem>[]).take(3).toList();
    final userNotices = activeNotices(ref.watch(noticesProvider).value ?? const <Notice>[], now);
    return Scaffold(
      body: SafeArea(
        child: asyncView(events, (eventList) => asyncView(tasks, (taskList) {
              final names = {for (final s in spaces.value ?? const []) s.id: s.name};
              final agenda = buildDayAgenda(now: now, events: eventList, tasks: taskList);
              final system = systemNotices(
                now: now,
                tasks: taskList,
                bridge: ref.watch(bridgeStatusProvider).value,
                wakePlans: ref.watch(wakePlansProvider).value ?? const <WakePlan>[],
              );
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  MotifBackground(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 12, 20),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_greeting(now), style: theme.textTheme.headlineMedium),
                                const SizedBox(height: 6),
                                Text(
                                  DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(now),
                                  style: theme.textTheme.bodyLarge?.copyWith(color: org.accentText),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            key: const Key('open-news'),
                            tooltip: 'Notícias',
                            icon: const Icon(Icons.newspaper_outlined),
                            onPressed: () => context.go('/noticias'),
                          ),
                          IconButton(
                            key: const Key('open-home'),
                            tooltip: 'Casa',
                            icon: const Icon(Icons.home_outlined),
                            onPressed: () => context.go('/casa'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  NoticeBoard(system: system, notices: userNotices, now: now),
                  const SectionHeader('Hoje'),
                  if (agenda.events.isEmpty) const EmptyHint('Nada na agenda hoje.'),
                  if (agenda.events.isNotEmpty)
                    OrgCard(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(children: [
                        for (final e in agenda.events)
                          EventTile(event: e, spaceName: names[e.spaceId]),
                      ]),
                    ),
                  const SectionHeader('Tarefas'),
                  if (agenda.overdue.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                      child: Text('Atrasadas',
                          style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.error)),
                    ),
                    OrgCard(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(children: [
                        for (final t in agenda.overdue) _taskRow(t, names[t.spaceId], now),
                      ]),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (agenda.dueToday.isEmpty) const EmptyHint('Nenhuma tarefa para hoje.'),
                  if (agenda.dueToday.isNotEmpty)
                    OrgCard(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(children: [
                        for (final t in agenda.dueToday) _taskRow(t, names[t.spaceId], now),
                      ]),
                    ),
                  if (headlines.isNotEmpty) ...[
                    const SectionHeader('Manchetes'),
                    OrgCard(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(children: [
                        for (final n in headlines) NewsTile(key: ValueKey('news-${n.id}'), item: n),
                      ]),
                    ),
                  ],
                ],
              );
            })),
      ),
    );
  }
}
