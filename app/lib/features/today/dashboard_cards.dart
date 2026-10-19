import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../data/repository.dart';
import '../../domain/calendar_event.dart';
import '../../domain/event_tag.dart';
import '../../domain/task_item.dart';
import '../../ui/common.dart';
import '../../ui/org_theme.dart';
import '../../ui/org_widgets.dart';
import '../agenda/tag_style.dart';
import 'dashboard_data.dart';

/// Cabeçalho padrão dos cartões do painel: ícone, título e um destino
/// ("Ver todas", seta). Sempre com pelo menos 48 dp de altura.
class DashHeader extends StatelessWidget {
  const DashHeader({
    super.key,
    required this.icon,
    required this.title,
    this.trailing,
    this.onTap,
    this.semanticLabel,
  });

  final IconData icon;
  final String title;
  final Widget? trailing;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final org = context.org;
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        children: [
          Icon(icon, size: 20, color: org.accentText),
          const SizedBox(width: 12),
          Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
          ?trailing,
          if (onTap != null) Icon(Icons.chevron_right, size: 20, color: org.inkMuted),
        ],
      ),
    );
    if (onTap == null) return row;
    return Semantics(
      button: true,
      label: semanticLabel ?? 'Abrir $title',
      excludeSemantics: true,
      child: InkWell(borderRadius: BorderRadius.circular(org.radiusSm), onTap: onTap, child: row),
    );
  }
}

// --- Para hoje --------------------------------------------------------------

/// O que importa hoje: eventos (com "agora", selo de prova, terminados esmaecidos) e as tarefas
/// atrasadas ou com prazo hoje, que podem ser concluídas aqui mesmo.
class ParaHojeCard extends ConsumerWidget {
  const ParaHojeCard({
    super.key,
    required this.now,
    required this.events,
    required this.tasks,
    required this.spaceNames,
    this.tags = const {},
  });

  final DateTime now;
  final AsyncValue<List<CalendarEvent>> events;
  final AsyncValue<List<TaskItem>> tasks;
  final Map<String, String> spaceNames;

  /// Etiquetas por id (decidem o que sai do cartão e a cor da linha).
  final Map<String, EventTag> tags;

  /// Conclui a tarefa e oferece "Desfazer" (restaura exatamente o estado anterior).
  Future<void> _complete(BuildContext context, WidgetRef ref, TaskItem t) async {
    final repo = ref.read(repositoryProvider);
    final done = ref.read(clockProvider)();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await repo.upsertTask(t.moved(TaskStatus.done, done));
    } on RepositoryException {
      if (context.mounted) showError(context, 'Não foi possível atualizar a tarefa.');
      return;
    }
    showUndo(messenger, 'Tarefa concluída', () => repo.upsertTask(t));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final waiting = !events.hasValue && !tasks.hasValue;
    final plan = buildTodayPlan(now, events.value ?? const [], tags, tasks.value ?? const []);
    return OrgCard(
      key: const Key('today-card'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DashHeader(icon: Icons.today_outlined, title: 'Para hoje'),
          if (waiting && (events.hasError || tasks.hasError))
            const EmptyHint('Não foi possível carregar o seu dia.')
          else if (waiting)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            )
          else ...[
            if (events.hasError && !events.hasValue) const EmptyHint('Não foi possível carregar a agenda.'),
            if (tasks.hasError && !tasks.hasValue) const EmptyHint('Não foi possível carregar as tarefas.'),
            for (final e in plan.events)
              _EventRow(
                key: ValueKey('today-event-${e.id}'),
                event: e,
                now: now,
                spaceName: spaceNames[e.spaceId],
                tags: tags,
              ),
            for (final t in plan.tasks) _taskRow(context, ref, t),
            if (plan.moreTasks > 0)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const Key('today-more-tasks'),
                  onPressed: () => context.go('/tarefas'),
                  child: Text(plan.moreTasks == 1 ? '+ 1 tarefa' : '+ ${plan.moreTasks} tarefas'),
                ),
              ),
            if (plan.isEmpty && events.hasValue && tasks.hasValue)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('Dia livre', key: const Key('today-free'), style: theme.textTheme.titleSmall),
              ),
          ],
        ],
      ),
    );
  }

  Widget _taskRow(BuildContext context, WidgetRef ref, TaskItem t) {
    final theme = Theme.of(context);
    final org = context.org;
    final due = t.dueAt;
    final overdue = due != null && due.isBefore(DateTime(now.year, now.month, now.day));
    final label = overdue ? 'atrasada · ${DateFormat('d MMM', 'pt_BR').format(due)}' : 'hoje';
    final subtitle = [label, ?spaceNames[t.spaceId]].join(' · ');
    return InkWell(
      key: ValueKey('today-task-${t.id}'),
      borderRadius: BorderRadius.circular(org.radiusSm),
      onTap: () => context.go('/tarefas'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            Checkbox(
              key: ValueKey('task-check-${t.id}'),
              value: t.isDone,
              semanticLabel: 'Concluir tarefa ${t.title}',
              onChanged: (_) => _complete(context, ref, t),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyLarge),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: overdue ? theme.colorScheme.error : org.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (t.priority == TaskPriority.alta) ...[
              const SizedBox(width: 8),
              const OrgBadge('alta', tone: OrgBadgeTone.danger),
            ],
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({
    super.key,
    required this.event,
    required this.now,
    this.spaceName,
    this.tags = const {},
  });

  final CalendarEvent event;
  final DateTime now;
  final String? spaceName;
  final Map<String, EventTag> tags;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final org = context.org;
    final e = event;
    final location = e.location;
    final current = !e.allDay && !e.startsAt.isAfter(now) && e.endsAt.isAfter(now);
    final finished = !e.allDay && !e.endsAt.isAfter(now);
    final details = [
      if (!e.allDay) '${hm(e.startsAt)}–${hm(e.endsAt)}',
      ?spaceName,
      if (location != null && location.isNotEmpty) location,
    ].join(' · ');
    final look = eventLook(org, e, tags);
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 4,
          height: 36,
          margin: const EdgeInsets.only(right: 12, top: 2),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: look.tagged ? null : (current ? org.accentText : org.line),
            borderRadius: BorderRadius.circular(2),
          ),
          child: look.tagged ? ColoredBox(key: ValueKey('tag-bar-${e.id}-dash'), color: look.accent) : null,
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(e.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: look.taggedWeight)),
              if (details.isNotEmpty)
                Text(
                  details,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: org.inkMuted),
                ),
            ],
          ),
        ),
        if (isExamTitle(e.title)) ...[
          const SizedBox(width: 8),
          const OrgBadge('Prova', tone: OrgBadgeTone.danger),
        ],
        if (current) ...[
          const SizedBox(width: 8),
          const OrgBadge('agora'),
        ],
      ],
    );
    final body = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        // Com etiqueta, a linha ganha o fundo suave da cor dela.
        child: look.tagged
            ? DecoratedBox(
                decoration: BoxDecoration(color: look.fill, borderRadius: BorderRadius.circular(org.radiusSm)),
                child: Padding(padding: const EdgeInsets.fromLTRB(0, 0, 8, 0), child: row),
              )
            : row,
      ),
    );
    return InkWell(
      borderRadius: BorderRadius.circular(org.radiusSm),
      onTap: () => context.go('/agenda'),
      child: finished ? Opacity(key: ValueKey('today-done-${e.id}'), opacity: 0.5, child: body) : body,
    );
  }
}
