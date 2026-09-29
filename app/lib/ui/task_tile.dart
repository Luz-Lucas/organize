import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../app/providers.dart';
import '../data/repository.dart';
import '../domain/task_item.dart';
import 'common.dart';

class TaskTile extends ConsumerWidget {
  const TaskTile({super.key, required this.task, this.spaceName});

  final TaskItem task;
  final String? spaceName;

  Future<void> _toggle(BuildContext context, WidgetRef ref) async {
    final now = ref.read(clockProvider)();
    try {
      await ref.read(repositoryProvider).upsertTask(task.toggled(now));
    } on RepositoryException {
      if (context.mounted) showError(context, 'Não foi possível atualizar a tarefa.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final due = task.dueAt;
    final subtitle = [
      ?spaceName,
      if (due != null) DateFormat('d MMM', 'pt_BR').format(due),
    ].join(' · ');
    return ListTile(
      leading: Checkbox(
        key: ValueKey('task-check-${task.id}'),
        value: task.isDone,
        onChanged: (_) => _toggle(context, ref),
      ),
      title: Text(
        task.title,
        style: task.isDone
            ? TextStyle(
                decoration: TextDecoration.lineThrough,
                color: theme.colorScheme.onSurfaceVariant,
              )
            : null,
      ),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
    );
  }
}
