import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../data/repository.dart';
import '../../domain/calendar_event.dart';
import '../../domain/event_tag.dart';
import '../../domain/ids.dart';
import '../../domain/news.dart';
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

class _MiniLabel extends StatelessWidget {
  const _MiniLabel(this.text, {this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(
          color: color ?? theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// Estados de carregando/erro de um cartão cujos dados ainda não chegaram.
Widget? _pendingBody(BuildContext context, AsyncValue<Object?> value, String errorText) {
  if (value.hasValue) return null;
  if (value.hasError) return EmptyHint(errorText);
  return const Padding(
    padding: EdgeInsets.symmetric(vertical: 12),
    child: Center(
      child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
    ),
  );
}

// --- Agora e a seguir -------------------------------------------------------

class NowNextCard extends StatelessWidget {
  const NowNextCard({
    super.key,
    required this.now,
    required this.events,
    required this.spaceNames,
    this.tags = const {},
  });

  final DateTime now;
  final AsyncValue<List<CalendarEvent>> events;
  final Map<String, String> spaceNames;

  /// Etiquetas por id; sem elas a linha segue sem cor de etiqueta.
  final Map<String, EventTag> tags;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final org = context.org;
    final pending = _pendingBody(context, events, 'Não foi possível carregar a agenda.');
    final data = events.value;
    final nn = data == null ? null : buildNowNext(now, data);
    final next = nn?.upcoming.take(2).toList() ?? const <CalendarEvent>[];
    final more = nn == null ? 0 : nn.upcoming.length - next.length;
    return OrgCard(
      key: const Key('card-now-next'),
      onTap: () => context.go('/agenda'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DashHeader(
            icon: Icons.schedule_outlined,
            title: 'Agora e a seguir',
            trailing: Icon(Icons.chevron_right, size: 20, color: org.inkMuted),
          ),
          ?pending,
          if (nn != null) ...[
            if (nn.allDay.isNotEmpty) ...[
              const _MiniLabel('Dia todo'),
              for (final e in nn.allDay)
                _EventRow(key: ValueKey('now-${e.id}'), event: e, spaceName: spaceNames[e.spaceId], tags: tags),
            ],
            if (nn.current.isNotEmpty) ...[
              _MiniLabel('Agora', color: org.accentText),
              for (final e in nn.current.take(2))
                _EventRow(
                  key: ValueKey('now-${e.id}'),
                  event: e,
                  spaceName: spaceNames[e.spaceId],
                  tags: tags,
                  highlight: true,
                ),
            ],
            if (next.isNotEmpty) ...[
              const _MiniLabel('A seguir'),
              for (final e in next)
                _EventRow(key: ValueKey('next-${e.id}'), event: e, spaceName: spaceNames[e.spaceId], tags: tags),
              if (more > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    more == 1 ? '+ 1 evento mais tarde' : '+ $more eventos mais tarde',
                    style: theme.textTheme.bodySmall?.copyWith(color: org.inkMuted),
                  ),
                ),
            ],
            if (nn.current.isEmpty && next.isEmpty && nn.allDay.isEmpty) ...[
              Text(
                nn.freeDay ? 'Agenda livre hoje' : 'Nada mais por hoje',
                key: const Key('now-next-free'),
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                nn.nextDayEvent == null
                    ? 'Nenhum evento à vista.'
                    : 'Próximo: ${dayLabel(nn.nextDayEvent!.startsAt, now)}'
                        '${nn.nextDayEvent!.allDay ? '' : ', ${hm(nn.nextDayEvent!.startsAt)}'}'
                        ' · ${nn.nextDayEvent!.title}',
                key: const Key('now-next-upcoming'),
                style: theme.textTheme.bodyMedium?.copyWith(color: org.inkMuted),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({super.key, required this.event, this.spaceName, this.tags = const {}, this.highlight = false});

  final CalendarEvent event;
  final String? spaceName;
  final Map<String, EventTag> tags;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final org = context.org;
    final e = event;
    final location = e.location;
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
            color: look.tagged ? null : (highlight ? org.accentText : org.line),
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
      ],
    );
    return ConstrainedBox(
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
  }
}

// --- Próxima prova ----------------------------------------------------------

class ExamCard extends StatelessWidget {
  const ExamCard({super.key, required this.now, required this.info});

  final DateTime now;
  final ExamInfo info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final org = context.org;
    final e = info.event;
    final location = e.location;
    final detail = info.days >= 2
        ? DateFormat('EEE, d MMM', 'pt_BR').format(e.startsAt) + (e.allDay ? '' : ' às ${hm(e.startsAt)}')
        : null;
    final countdown = switch (info.days) {
      _ when info.inProgress => const Icon(Icons.edit_note, size: 28),
      0 => Text('hoje', style: theme.textTheme.titleSmall?.copyWith(color: org.accentText)),
      final n => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$n', style: theme.textTheme.headlineSmall?.copyWith(color: org.accentText)),
            Text(n == 1 ? 'dia' : 'dias', style: theme.textTheme.labelSmall?.copyWith(color: org.inkMuted)),
          ],
        ),
    };
    return OrgCard(
      key: const Key('card-exam'),
      onTap: () => context.go('/agenda'),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 60, minHeight: 60),
            padding: const EdgeInsets.all(8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: org.accentSoft,
              borderRadius: BorderRadius.circular(org.radiusSm),
            ),
            child: countdown,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Próxima prova', style: theme.textTheme.labelMedium?.copyWith(color: org.inkMuted)),
                const SizedBox(height: 2),
                Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  examWhen(info),
                  key: const Key('exam-when'),
                  style: theme.textTheme.bodyMedium?.copyWith(color: org.accentText, fontWeight: FontWeight.w600),
                ),
                if (detail != null)
                  Text(detail, style: theme.textTheme.bodySmall?.copyWith(color: org.inkMuted)),
                if (location != null && location.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      children: [
                        Icon(Icons.place_outlined, size: 16, color: org.inkMuted),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            location,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(color: org.inkMuted),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- Tarefas ----------------------------------------------------------------

class TasksCard extends ConsumerStatefulWidget {
  const TasksCard({super.key, required this.now, required this.tasks, required this.spaceNames});

  final DateTime now;
  final AsyncValue<List<TaskItem>> tasks;
  final Map<String, String> spaceNames;

  @override
  ConsumerState<TasksCard> createState() => _TasksCardState();
}

class _TasksCardState extends ConsumerState<TasksCard> {
  final _quick = TextEditingController();
  bool _adding = false;

  @override
  void dispose() {
    _quick.dispose();
    super.dispose();
  }

  /// Conclui a tarefa e oferece "Desfazer" (restaura exatamente o estado anterior).
  Future<void> _complete(TaskItem t) async {
    final repo = ref.read(repositoryProvider);
    final now = ref.read(clockProvider)();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await repo.upsertTask(t.moved(TaskStatus.done, now));
    } on RepositoryException {
      if (mounted) showError(context, 'Não foi possível atualizar a tarefa.');
      return;
    }
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: const Text('Tarefa concluída'),
        action: SnackBarAction(
          label: 'Desfazer',
          onPressed: () async {
            try {
              await repo.upsertTask(t);
            } on RepositoryException {
              messenger.showSnackBar(const SnackBar(content: Text('Não foi possível desfazer.')));
            }
          },
        ),
      ));
  }

  Future<void> _quickAdd() async {
    final title = _quick.text.trim();
    if (title.isEmpty || _adding) return;
    final repo = ref.read(repositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    setState(() => _adding = true);
    try {
      await repo.upsertTask(TaskItem(id: newId(), title: title));
      _quick.clear();
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: const Text('Tarefa adicionada'),
          action: SnackBarAction(label: 'Ver', onPressed: () => router.go('/tarefas')),
        ));
    } on RepositoryException {
      messenger.showSnackBar(
          const SnackBar(content: Text('Não foi possível adicionar. O texto continua no campo.')));
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Widget _row(TaskItem t, _RowKind kind) {
    final theme = Theme.of(context);
    final org = context.org;
    final due = t.dueAt;
    final dueText = due == null ? null : DateFormat('d MMM', 'pt_BR').format(due);
    final label = switch (kind) {
      _RowKind.overdue => 'atrasada${dueText == null ? '' : ' · $dueText'}',
      _RowKind.today => 'hoje',
      _RowKind.doing => 'em andamento${dueText == null ? '' : ' · $dueText'}',
    };
    final subtitle = [label, ?widget.spaceNames[t.spaceId]].join(' · ');
    return InkWell(
      key: ValueKey(t.id),
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
              onChanged: (_) => _complete(t),
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
                        color: kind == _RowKind.overdue ? theme.colorScheme.error : org.inkMuted,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final org = context.org;
    final pending = _pendingBody(context, widget.tasks, 'Não foi possível carregar as tarefas.');
    final data = widget.tasks.value;
    final picks = data == null ? null : pickDashboardTasks(widget.now, data);
    return OrgCard(
      key: const Key('card-tasks'),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: DashHeader(
              icon: Icons.check_circle_outline,
              title: 'Tarefas',
              onTap: () => context.go('/tarefas'),
              semanticLabel: 'Abrir todas as tarefas',
              trailing: picks == null || picks.pending == 0
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: OrgBadge('${picks.pending}', tone: OrgBadgeTone.neutral),
                    ),
            ),
          ),
          if (pending != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: pending),
          if (picks != null) ...[
            if (picks.shown == 0)
              const EmptyHint('Nenhuma tarefa para hoje.'),
            if (picks.overdue.isNotEmpty) ...[
              _section('Atrasadas', theme.colorScheme.error),
              for (final t in picks.overdue) _row(t, _RowKind.overdue),
            ],
            if (picks.today.isNotEmpty) ...[
              _section('Para hoje', null),
              for (final t in picks.today) _row(t, _RowKind.today),
            ],
            if (picks.doing.isNotEmpty) ...[
              _section('Em andamento', null),
              for (final t in picks.doing) _row(t, _RowKind.doing),
            ],
            if (picks.hidden > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: Text(
                  picks.hidden == 1 ? '+ 1 tarefa em destaque' : '+ ${picks.hidden} tarefas em destaque',
                  style: theme.textTheme.bodySmall?.copyWith(color: org.inkMuted),
                ),
              ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 0, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('quick-task-field'),
                    controller: _quick,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _quickAdd(),
                    decoration: const InputDecoration(
                      hintText: 'Adicionar tarefa…',
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('quick-task-add'),
                  tooltip: 'Adicionar tarefa',
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: _adding ? null : _quickAdd,
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const Key('tasks-see-all'),
              onPressed: () => context.go('/tarefas'),
              child: const Text('Ver todas'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String text, Color? color) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
        child: _MiniLabel(text, color: color),
      );
}

enum _RowKind { overdue, today, doing }

// --- Notícias ---------------------------------------------------------------

class NewsCard extends ConsumerWidget {
  const NewsCard({super.key, required this.now, required this.feed});

  final DateTime now;
  final AsyncValue<List<NewsItem>> feed;

  Future<void> _open(BuildContext context, WidgetRef ref, NewsItem item) async {
    const message = 'Não foi possível abrir o link.';
    final uri = Uri.tryParse(item.url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      showError(context, message);
      return;
    }
    var opened = false;
    try {
      opened = await ref.read(linkOpenerProvider)(uri);
    } catch (_) {
      opened = false;
    }
    if (!opened && context.mounted) showError(context, message);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final org = context.org;
    final items = (feed.value ?? const <NewsItem>[]).take(3).toList();
    return OrgCard(
      key: const Key('card-news'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DashHeader(
            icon: Icons.newspaper_outlined,
            title: 'Notícias',
            onTap: () => context.go('/noticias'),
          ),
          if (!feed.hasValue && feed.hasError)
            Row(
              children: [
                const Expanded(child: EmptyHint('Não foi possível carregar as notícias.')),
                TextButton(
                  key: const Key('news-retry'),
                  onPressed: () => ref.invalidate(newsFeedProvider),
                  child: const Text('Tentar de novo'),
                ),
              ],
            )
          else if (!feed.hasValue)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            )
          else if (items.isEmpty)
            const EmptyHint('Nenhuma manchete por enquanto. Escolha suas fontes em Notícias.')
          else
            for (final n in items)
              InkWell(
                key: ValueKey('news-${n.id}'),
                borderRadius: BorderRadius.circular(org.radiusSm),
                onTap: () => _open(context, ref, n),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          n.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: n.highlighted ? FontWeight.w600 : null,
                          ),
                        ),
                        Text(
                          '${n.sourceName} · ${timeAgo(n.publishedAt, now)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: org.inkMuted),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
