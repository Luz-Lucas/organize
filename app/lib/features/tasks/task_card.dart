import 'package:flutter/material.dart';

import '../../domain/task_item.dart';
import '../../ui/date_labels.dart';
import '../../ui/org_theme.dart';
import '../../ui/org_widgets.dart';

export '../../ui/date_labels.dart' show dueLabel;

/// Cartão de tarefa do Kanban: botão de concluir, título, prioridade (só alta
/// e baixa), espaço, prazo e ícone de nota.
class TaskCard extends StatelessWidget {
  const TaskCard({
    super.key,
    required this.task,
    required this.now,
    this.spaceName,
    this.onTap,
    this.onLongPress,
    this.onToggleDone,
  });

  final TaskItem task;
  final DateTime now;
  final String? spaceName;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Concluir (ou reabrir) com um toque. Sem ele o botão não aparece.
  final VoidCallback? onToggleDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final org = context.org;
    final due = task.dueAt;
    final urgent = !task.isDone && due != null && due.difference(now) <= const Duration(days: 1);
    final toggle = onToggleDone;
    final content = Padding(
      padding: EdgeInsets.fromLTRB(toggle == null ? 12 : 0, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            task.title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyLarge?.copyWith(
              decoration: task.isDone ? TextDecoration.lineThrough : null,
              color: task.isDone ? org.inkMuted : org.ink,
            ),
          ),
          if (spaceName != null ||
              due != null ||
              task.noteId != null ||
              task.priority != TaskPriority.media) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (task.priority == TaskPriority.alta)
                  OrgBadge(task.priority.label, tone: OrgBadgeTone.danger),
                if (task.priority == TaskPriority.baixa)
                  OrgBadge(task.priority.label, tone: OrgBadgeTone.neutral),
                if (spaceName != null) OrgBadge(spaceName!),
                if (due != null)
                  OrgBadge(
                    dueLabel(due, now, done: task.isDone),
                    tone: urgent ? OrgBadgeTone.danger : OrgBadgeTone.neutral,
                  ),
                if (task.noteId != null)
                  Icon(Icons.description_outlined, size: 16, color: org.inkMuted),
              ],
            ),
          ],
        ],
      ),
    );
    final card = OrgCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: toggle == null
          ? content
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, top: 4),
                  child: IconButton(
                    key: ValueKey('task-done-${task.id}'),
                    tooltip: task.isDone ? 'Reabrir tarefa' : 'Concluir tarefa',
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    icon: Icon(
                      task.isDone ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: task.isDone ? org.accentText : org.inkMuted,
                    ),
                    onPressed: toggle,
                  ),
                ),
                Expanded(child: content),
              ],
            ),
    );
    final body = onLongPress == null
        ? card
        : Semantics(
            onLongPressHint: 'Mover para…',
            child: GestureDetector(
              behavior: HitTestBehavior.deferToChild,
              onLongPress: onLongPress,
              child: card,
            ),
          );
    return body;
  }
}
