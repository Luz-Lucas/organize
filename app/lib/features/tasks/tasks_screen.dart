import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/repository.dart';
import '../../domain/ids.dart';
import '../../domain/task_item.dart';
import '../../ui/common.dart';
import '../../ui/org_widgets.dart';
import 'kanban_board.dart';
import 'task_dialog.dart';

class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  String? _spaceFilter;

  Future<bool> _add(String title, TaskStatus status) async {
    final now = ref.read(clockProvider)();
    final task = TaskItem(
      id: newId(),
      title: title,
      status: status,
      completedAt: status == TaskStatus.done ? now : null,
      spaceId: _spaceFilter,
    );
    try {
      await ref.read(repositoryProvider).upsertTask(task);
      return mounted;
    } on RepositoryException {
      if (mounted) showError(context, 'Não foi possível adicionar. O texto continua no campo.');
      return false;
    }
  }

  Future<void> _move(TaskItem task, TaskStatus to) async {
    final now = ref.read(clockProvider)();
    try {
      await ref.read(repositoryProvider).upsertTask(task.moved(to, now));
    } on RepositoryException {
      if (mounted) showError(context, 'Não foi possível mover a tarefa.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(clockProvider)();
    final spaces = ref.watch(spacesProvider);
    final tasks = ref.watch(tasksProvider);
    return Scaffold(
      body: SafeArea(
        child: asyncView(spaces, (spaceList) => asyncView(tasks, (taskList) {
              final visible = _spaceFilter == null
                  ? taskList
                  : taskList.where((t) => t.spaceId == _spaceFilter).toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const PageHeader(title: 'Tarefas', subtitle: 'Arraste os cartões entre as colunas'),
                  if (spaceList.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('Todos'),
                            selected: _spaceFilter == null,
                            onSelected: (_) => setState(() => _spaceFilter = null),
                          ),
                          for (final s in spaceList)
                            ChoiceChip(
                              label: Text(s.name),
                              selected: _spaceFilter == s.id,
                              onSelected: (_) => setState(() => _spaceFilter = s.id),
                            ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: KanbanBoard(
                      tasks: visible,
                      spaces: spaceList,
                      now: now,
                      onMove: _move,
                      onQuickAdd: _add,
                      onOpen: (t) => showDialog<void>(
                        context: context,
                        builder: (_) => TaskDialog(task: t, spaces: spaceList),
                      ),
                    ),
                  ),
                ],
              );
            })),
      ),
    );
  }
}
