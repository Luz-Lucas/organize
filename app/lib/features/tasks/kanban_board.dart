import 'package:flutter/material.dart';

import '../../domain/space.dart';
import '../../domain/task_item.dart';
import '../../ui/org_theme.dart';
import '../../ui/org_widgets.dart';
import 'task_card.dart';

const _doneStep = 20;

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
  });

  final List<TaskItem> tasks;
  final List<Space> spaces;
  final DateTime now;
  final void Function(TaskItem task, TaskStatus to) onMove;
  final void Function(TaskItem task) onOpen;

  /// Devolve `true` quando a tarefa foi criada (o campo é então limpo).
  final Future<bool> Function(String title, TaskStatus status) onQuickAdd;

  @override
  State<KanbanBoard> createState() => _KanbanBoardState();
}

class _KanbanBoardState extends State<KanbanBoard> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  final _inputs = {for (final s in TaskStatus.values) s: TextEditingController()};
  int _doneLimit = _doneStep;

  @override
  void dispose() {
    _tabs.dispose();
    for (final c in _inputs.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _add(TaskStatus status) async {
    final controller = _inputs[status]!;
    final title = controller.text.trim();
    if (title.isEmpty) return;
    final ok = await widget.onQuickAdd(title, status);
    if (ok && mounted) controller.clear();
  }

  List<TaskItem> _column(TaskStatus s) {
    final list = widget.tasks.where((t) => t.status == s).toList();
    if (s == TaskStatus.done) {
      final epoch = DateTime(0);
      list.sort((a, b) => (b.completedAt ?? epoch).compareTo(a.completedAt ?? epoch));
    } else {
      list.sort((a, b) {
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
