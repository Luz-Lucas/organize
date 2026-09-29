import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../data/repository.dart';
import '../../domain/agenda.dart';
import '../../domain/ids.dart';
import '../../domain/task_item.dart';
import '../../ui/common.dart';
import '../../ui/task_tile.dart';

class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  final _input = TextEditingController();
  DateTime? _due;
  String? _spaceFilter;
  bool _showDone = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final title = _input.text.trim();
    if (title.isEmpty) return;
    final task = TaskItem(id: newId(), title: title, dueAt: _due, spaceId: _spaceFilter);
    try {
      await ref.read(repositoryProvider).upsertTask(task);
      _input.clear();
      setState(() => _due = null);
    } on RepositoryException {
      if (mounted) showError(context, 'Não foi possível adicionar. O texto continua no campo.');
    }
  }

  Future<void> _pickDue() async {
    final now = ref.read(clockProvider)();
    final picked = await showDatePicker(
      context: context,
      initialDate: _due ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) {
      setState(() => _due = DateTime(picked.year, picked.month, picked.day, 23, 59));
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(clockProvider)();
    final spaces = ref.watch(spacesProvider);
    final tasks = ref.watch(tasksProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tarefas'),
        actions: [
          IconButton(
            key: const Key('show-done'),
            tooltip: _showDone ? 'Ocultar concluídas' : 'Mostrar concluídas',
            icon: Icon(_showDone ? Icons.visibility_off_outlined : Icons.visibility_outlined),
            onPressed: () => setState(() => _showDone = !_showDone),
          ),
        ],
      ),
      body: asyncView(spaces, (spaceList) => asyncView(tasks, (taskList) {
            final names = {for (final s in spaceList) s.id: s.name};
            final visible = _spaceFilter == null
                ? taskList
                : taskList.where((t) => t.spaceId == _spaceFilter);
            final groups = groupTasks(visible, now);
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  key: const Key('quick-add'),
                  controller: _input,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _add(),
                  decoration: InputDecoration(
                    hintText: 'Adicionar tarefa…',
                    prefixIcon: const Icon(Icons.add),
                    suffixIcon: IconButton(
                      tooltip: 'Prazo',
                      icon: const Icon(Icons.event_outlined),
                      onPressed: _pickDue,
                    ),
                  ),
                ),
                if (_due != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: InputChip(
                        label: Text('Prazo: ${DateFormat('d MMM', 'pt_BR').format(_due!)}'),
                        onDeleted: () => setState(() => _due = null),
                      ),
                    ),
                  ),
                if (spaceList.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
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
                for (final group in TaskGroup.values)
                  if (groups[group]!.isNotEmpty && (group != TaskGroup.concluidas || _showDone)) ...[
                    SectionHeader(group.label),
                    for (final t in groups[group]!)
                      TaskTile(key: ValueKey(t.id), task: t, spaceName: names[t.spaceId]),
                  ],
                if (taskList.isEmpty)
                  const EmptyHint('Nenhuma tarefa ainda. Digite acima e pressione Enter.'),
              ],
            );
          })),
    );
  }
}
