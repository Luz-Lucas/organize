import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/task_item.dart';
import '../../ui/org_theme.dart';
import '../../ui/org_widgets.dart';

/// Rótulo do prazo: "hoje", "amanhã" ou "sex, 16".
String dueLabel(DateTime due, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(due.year, due.month, due.day);
  final diff = day.difference(today).inDays;
  if (diff == 0) return 'hoje';
  if (diff == 1) return 'amanhã';
  return DateFormat('EEE, d', 'pt_BR').format(due);
}

/// Cartão de tarefa do Kanban: título, prioridade (só alta e baixa), espaço,
/// prazo e ícone de nota.
class TaskCard extends StatelessWidget {
  const TaskCard({
    super.key,
    required this.task,
    required this.now,
    this.spaceName,
    this.onTap,
    this.onLongPress,
  });

  final TaskItem task;
  final DateTime now;
  final String? spaceName;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final org = context.org;
    final due = task.dueAt;
    final urgent = !task.isDone && due != null && due.difference(now) <= const Duration(days: 1);
    final card = OrgCard(
      padding: const EdgeInsets.all(12),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            task.title,
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
                    dueLabel(due, now),
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
    final body = onLongPress == null
        ? card
        : GestureDetector(behavior: HitTestBehavior.deferToChild, onLongPress: onLongPress, child: card);
    return Opacity(opacity: task.isDone ? 0.55 : 1, child: body);
  }
}
