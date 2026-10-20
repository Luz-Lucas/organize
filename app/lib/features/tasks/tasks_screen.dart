import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/repository.dart';
import '../../domain/ids.dart';
import '../../domain/space.dart';
import '../../domain/task_item.dart';
import '../../domain/task_series.dart';
import '../../ui/common.dart';
import '../../ui/org_widgets.dart';
import 'kanban_board.dart';
import 'task_dialog.dart';

/// Filtro de espaço da tela Tarefas (`null` = todos). Fica fora do widget para
/// sobreviver à troca de abas.
class TasksSpaceFilter extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? spaceId) => state = spaceId;
}

final tasksSpaceFilterProvider = NotifierProvider<TasksSpaceFilter, String?>(TasksSpaceFilter.new);

class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  String? get _spaceFilter => ref.read(tasksSpaceFilterProvider);

  TaskItem _draft(String title, TaskStatus status, TaskPriority priority, DateTime? dueAt) {
    final now = ref.read(clockProvider)();
    return TaskItem(
      id: newId(),
      title: title,
      status: status,
      priority: priority,
      dueAt: dueAt,
      completedAt: status == TaskStatus.done ? now : null,
      spaceId: _spaceFilter,
    );
  }

  Future<bool> _add(
    String title,
    TaskStatus status,
    TaskPriority priority,
    DateTime? dueAt,
  ) async {
    final task = _draft(title, status, priority, dueAt);
    try {
      await ref.read(repositoryProvider).upsertTask(task);
      return mounted;
    } on RepositoryException {
      if (mounted) showError(context, 'Não foi possível adicionar. O texto continua no campo.');
      return false;
    }
  }

  /// "Mais opções" do campo rápido: abre o diálogo completo em modo de criação.
  Future<bool> _addWithDialog(
    String title,
    TaskStatus status,
    TaskPriority priority,
    DateTime? dueAt,
    List<Space> spaces,
  ) async {
    final saved = await showTaskEditor(
      context,
      task: _draft(title, status, priority, dueAt),
      spaces: spaces,
      isNew: true,
    );
    return saved == true && mounted;
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
    final mobile = MediaQuery.sizeOf(context).width < 720;
    final gutter = mobile ? 16.0 : 24.0;
    return Scaffold(
      body: SafeArea(
        child: asyncView(spaces, (spaceList) => asyncView(tasks, (taskList) {
              // Espaço apagado depois de escolhido: volta a mostrar tudo.
              final selected = spaceList.any((s) => s.id == ref.watch(tasksSpaceFilterProvider))
                  ? ref.watch(tasksSpaceFilterProvider)
                  : null;
              // Tarefas de série: só a próxima pendente de cada uma (as concluídas ficam).
              final current = nextPendingPerSeries(taskList);
              final visible = selected == null
                  ? current
                  : current.where((t) => t.spaceId == selected).toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PageHeader(
                    title: 'Tarefas',
                    subtitle: mobile
                        ? 'Segure um cartão para mover'
                        : 'Arraste os cartões entre as colunas',
                  ),
                  if (spaceList.isNotEmpty)
                    SingleChildScrollView(
                      key: const Key('space-filter'),
                      scrollDirection: Axis.horizontal,
                      padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 12),
                      child: Row(
                        children: [
                          ChoiceChip(
                            label: const Text('Todos'),
                            selected: selected == null,
                            onSelected: (_) => ref.read(tasksSpaceFilterProvider.notifier).select(null),
                          ),
                          for (final s in spaceList) ...[
                            const SizedBox(width: 8),
                            ChoiceChip(
                              label: Text(s.name),
                              selected: selected == s.id,
                              onSelected: (_) =>
                                  ref.read(tasksSpaceFilterProvider.notifier).select(s.id),
                            ),
                          ],
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
                      onQuickAddWithDialog: (title, status, priority, dueAt) =>
                          _addWithDialog(title, status, priority, dueAt, spaceList),
                      onOpen: (t) => showTaskEditor(context, task: t, spaces: spaceList),
                    ),
                  ),
                ],
              );
            })),
      ),
    );
  }
}
