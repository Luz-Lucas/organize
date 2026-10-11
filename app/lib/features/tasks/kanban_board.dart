import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/space.dart';
import '../../domain/task_item.dart';
import '../../ui/org_theme.dart';
import '../../ui/org_widgets.dart';
import 'task_card.dart';

const _doneStep = 20;

/// Rótulo do chip de prazo do campo rápido: "hoje", "amanhã" ou "dd/MM".
String quickDueLabel(DateTime due, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final diff = DateTime(due.year, due.month, due.day).difference(today).inDays;
  if (diff == 0) return 'hoje';
  if (diff == 1) return 'amanhã';
  return DateFormat('dd/MM').format(due);
}

String statusLabel(TaskStatus s) => switch (s) {
      TaskStatus.todo => 'A fazer',
      TaskStatus.doing => 'Fazendo',
      TaskStatus.done => 'Feito',
    };

/// Quadro Kanban com três colunas. Computador (>= 720px): colunas lado a
/// lado com arrastar e soltar. Celular: uma aba por coluna; segurar o
/// cartão abre "Mover para…".
class KanbanBoard extends StatefulWidget {
  const KanbanBoard({
    super.key,
    required this.tasks,
    required this.spaces,
    required this.now,
    required this.onMove,
    required this.onOpen,
    required this.onQuickAdd,
    required this.onQuickAddWithDialog,
  });

  final List<TaskItem> tasks;
  final List<Space> spaces;
  final DateTime now;
  final void Function(TaskItem task, TaskStatus to) onMove;
  final void Function(TaskItem task) onOpen;

  /// Devolve `true` quando a tarefa foi criada (o campo é então limpo).
  final Future<bool> Function(
    String title,
    TaskStatus status,
    TaskPriority priority,
    DateTime? dueAt,
  )
  onQuickAdd;

  /// "Mais opções": abre o diálogo completo de criação com o que já foi
  /// digitado/escolhido. Devolve `true` quando a tarefa foi criada.
  final Future<bool> Function(
    String title,
    TaskStatus status,
    TaskPriority priority,
    DateTime? dueAt,
  )
  onQuickAddWithDialog;

  @override
  State<KanbanBoard> createState() => _KanbanBoardState();
}

class _KanbanBoardState extends State<KanbanBoard> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  final _inputs = {for (final s in TaskStatus.values) s: TextEditingController()};
  final _priorities = {for (final s in TaskStatus.values) s: TaskPriority.media};
  final _dues = <TaskStatus, DateTime?>{};
  int _doneLimit = _doneStep;

  @override
  void dispose() {
    _tabs.dispose();
    for (final c in _inputs.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Limpa o campo e volta os chips para "Média" e "Sem prazo".
  void _reset(TaskStatus status) {
    _inputs[status]!.clear();
    setState(() {
      _priorities[status] = TaskPriority.media;
      _dues[status] = null;
    });
  }

  Future<void> _add(TaskStatus status) async {
    final title = _inputs[status]!.text.trim();
    if (title.isEmpty) return;
    final ok = await widget.onQuickAdd(title, status, _priorities[status]!, _dues[status]);
    if (ok && mounted) _reset(status);
  }

  Future<void> _addWithDialog(TaskStatus status) async {
    final title = _inputs[status]!.text.trim();
    final ok = await widget.onQuickAddWithDialog(
      title,
      status,
      _priorities[status]!,
      _dues[status],
    );
    if (ok && mounted) _reset(status);
  }

  Future<void> _pickDue(TaskStatus status) async {
    final now = widget.now;
    final picked = await showDatePicker(
      context: context,
      initialDate: _dues[status] ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null && mounted) {
      setState(() => _dues[status] = DateTime(picked.year, picked.month, picked.day, 23, 59));
    }
  }

  List<TaskItem> _column(TaskStatus s) {
    final list = widget.tasks.where((t) => t.status == s).toList();
    if (s == TaskStatus.done) {
      final epoch = DateTime(0);
      list.sort((a, b) => (b.completedAt ?? epoch).compareTo(a.completedAt ?? epoch));
    } else {
      list.sort((a, b) {
        final byPriority = b.priority.index.compareTo(a.priority.index);
        if (byPriority != 0) return byPriority;
        final ad = a.dueAt, bd = b.dueAt;
        if (ad == null && bd != null) return 1;
        if (ad != null && bd == null) return -1;
        if (ad != null && bd != null) {
          final c = ad.compareTo(bd);
          if (c != 0) return c;
        }
        return a.title.compareTo(b.title);
      });
    }
    return list;
  }

  Future<void> _moveSheet(TaskItem task) async {
    final to = await showModalBottomSheet<TaskStatus>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Mover para…'),
            ),
            for (final s in TaskStatus.values)
              if (s != task.status)
                ListTile(title: Text(statusLabel(s)), onTap: () => Navigator.pop(ctx, s)),
          ],
        ),
      ),
    );
    if (to == null || !mounted) return;
    widget.onMove(task, to);
    _tabs.animateTo(to.index);
  }

  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.sizeOf(context).width >= 720;
    final columns = {for (final s in TaskStatus.values) s: _column(s)};
    Widget col(TaskStatus s) => _KanbanColumn(
          status: s,
          tasks: columns[s]!,
          spaces: {for (final sp in widget.spaces) sp.id: sp.name},
          now: widget.now,
          desktop: desktop,
          controller: _inputs[s]!,
          doneLimit: _doneLimit,
          onMore: () => setState(() => _doneLimit += _doneStep),
          onSubmit: () => _add(s),
          priority: _priorities[s]!,
          dueLabel: _dues[s] == null ? null : quickDueLabel(_dues[s]!, widget.now),
          onPriority: (p) => setState(() => _priorities[s] = p),
          onPickDue: () => _pickDue(s),
          onClearDue: () => setState(() => _dues[s] = null),
          onMoreOptions: () => _addWithDialog(s),
          onMove: widget.onMove,
          onOpen: widget.onOpen,
          onLongPress: _moveSheet,
        );
    if (desktop) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final s in TaskStatus.values) ...[
              if (s != TaskStatus.todo) const SizedBox(width: 12),
              Expanded(child: col(s)),
            ],
          ],
        ),
      );
    }
    return Column(
      children: [
        TabBar(
          controller: _tabs,
          tabs: [
            for (final s in TaskStatus.values) Tab(text: '${statusLabel(s)} ${columns[s]!.length}'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [for (final s in TaskStatus.values) col(s)],
          ),
        ),
      ],
    );
  }
}

class _KanbanColumn extends StatelessWidget {
  const _KanbanColumn({
    required this.status,
    required this.tasks,
    required this.spaces,
    required this.now,
    required this.desktop,
    required this.controller,
    required this.doneLimit,
    required this.onMore,
    required this.onSubmit,
    required this.priority,
    required this.dueLabel,
    required this.onPriority,
    required this.onPickDue,
    required this.onClearDue,
    required this.onMoreOptions,
    required this.onMove,
    required this.onOpen,
    required this.onLongPress,
  });

  final TaskStatus status;
  final List<TaskItem> tasks;
  final Map<String, String> spaces;
  final DateTime now;
  final bool desktop;
  final TextEditingController controller;
  final int doneLimit;
  final VoidCallback onMore;
  final VoidCallback onSubmit;
  final TaskPriority priority;

  /// `null` = sem prazo escolhido.
  final String? dueLabel;
  final void Function(TaskPriority) onPriority;
  final VoidCallback onPickDue;
  final VoidCallback onClearDue;
  final VoidCallback onMoreOptions;
  final void Function(TaskItem, TaskStatus) onMove;
  final void Function(TaskItem) onOpen;
  final void Function(TaskItem) onLongPress;

  Widget _card(TaskItem t) {
    final card = TaskCard(
      key: ValueKey('task-card-${t.id}'),
      task: t,
      now: now,
      spaceName: spaces[t.spaceId],
      onTap: () => onOpen(t),
      onLongPress: desktop ? null : () => onLongPress(t),
    );
    if (!desktop) return card;
    return Draggable<TaskItem>(
      data: t,
      feedback: SizedBox(
        width: 260,
        child: Material(
          color: Colors.transparent,
          child: Opacity(opacity: 0.9, child: TaskCard(task: t, now: now, spaceName: spaces[t.spaceId])),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: card),
      child: card,
    );
  }

  @override
  Widget build(BuildContext context) {
    final org = context.org;
    final theme = Theme.of(context);
    final shown = status == TaskStatus.done ? tasks.take(doneLimit).toList() : tasks;
    return DragTarget<TaskItem>(
      onWillAcceptWithDetails: (d) => d.data.status != status,
      onAcceptWithDetails: (d) => onMove(d.data, status),
      builder: (context, candidate, _) {
        final hovering = candidate.isNotEmpty;
        return AnimatedContainer(
          key: ValueKey('column-${status.name}'),
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: hovering ? org.accentSoft : org.surface,
            borderRadius: BorderRadius.circular(org.radiusMd),
            border: Border.all(color: hovering ? org.accentText : org.line),
          ),
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (desktop)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Text(statusLabel(status), style: theme.textTheme.titleSmall),
                      const SizedBox(width: 8),
                      OrgBadge('${tasks.length}', tone: OrgBadgeTone.neutral),
                    ],
                  ),
                ),
              TextField(
                key: Key('quick-add-${status.name}'),
                controller: controller,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => onSubmit(),
                decoration: const InputDecoration(
                  hintText: 'Adicionar tarefa…',
                  prefixIcon: Icon(Icons.add),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              _QuickOptions(
                status: status,
                priority: priority,
                dueLabel: dueLabel,
                onPriority: onPriority,
                onPickDue: onPickDue,
                onClearDue: onClearDue,
                onMoreOptions: onMoreOptions,
              ),
              const SizedBox(height: 12),
              if (tasks.isEmpty) const EmptyHint('Nada por aqui.'),
              for (final t in shown)
                Padding(padding: const EdgeInsets.only(bottom: 8), child: _card(t)),
              if (shown.length < tasks.length)
                TextButton(
                  key: const Key('more-done'),
                  onPressed: onMore,
                  child: const Text('Ver mais'),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Linha compacta sob o campo rápido: prioridade, prazo e "mais opções".
class _QuickOptions extends StatelessWidget {
  const _QuickOptions({
    required this.status,
    required this.priority,
    required this.dueLabel,
    required this.onPriority,
    required this.onPickDue,
    required this.onClearDue,
    required this.onMoreOptions,
  });

  final TaskStatus status;
  final TaskPriority priority;
  final String? dueLabel;
  final void Function(TaskPriority) onPriority;
  final VoidCallback onPickDue;
  final VoidCallback onClearDue;
  final VoidCallback onMoreOptions;

  @override
  Widget build(BuildContext context) {
    final org = context.org;
    final name = status.name;
    final dueSet = dueLabel != null;
    final urgent = priority == TaskPriority.alta;
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        PopupMenuButton<TaskPriority>(
          key: Key('quick-priority-$name'),
          tooltip: 'Prioridade',
          onSelected: onPriority,
          itemBuilder: (_) => [
            for (final p in TaskPriority.values)
              PopupMenuItem(
                key: Key('quick-priority-$name-${p.name}'),
                value: p,
                child: Text(p.label),
              ),
          ],
          child: Chip(
            avatar: Icon(
              Icons.flag_outlined,
              size: 16,
              color: urgent ? Theme.of(context).colorScheme.error : org.inkMuted,
            ),
            label: Text(priority.label),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        ActionChip(
          key: Key('quick-due-$name'),
          avatar: Icon(
            Icons.event_outlined,
            size: 16,
            color: dueSet ? org.accentText : org.inkMuted,
          ),
          label: Text(dueLabel ?? 'Sem prazo'),
          onPressed: onPickDue,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        if (dueSet)
          IconButton(
            key: Key('quick-due-clear-$name'),
            tooltip: 'Remover prazo',
            icon: const Icon(Icons.close, size: 16),
            visualDensity: VisualDensity.compact,
            onPressed: onClearDue,
          ),
        IconButton(
          key: Key('quick-more-$name'),
          tooltip: 'Mais opções',
          icon: const Icon(Icons.tune, size: 18),
          visualDensity: VisualDensity.compact,
          onPressed: onMoreOptions,
        ),
      ],
    );
  }
}
