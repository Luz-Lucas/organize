import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../data/repository.dart';
import '../../domain/space.dart';
import '../../domain/task_item.dart';
import '../../ui/common.dart';

/// Edição de uma tarefa (ou criação, com [isNew]): título, descrição,
/// prioridade, prazo, espaço e, ao editar, exclusão. Fecha com `true` quando
/// salva. Falha ao gravar mantém o diálogo aberto com o que foi digitado.
class TaskDialog extends ConsumerStatefulWidget {
  const TaskDialog({super.key, required this.task, required this.spaces, this.isNew = false});

  /// Em modo de criação, a tarefa já vem montada (id novo, status da coluna).
  final bool isNew;
  final TaskItem task;
  final List<Space> spaces;

  @override
  ConsumerState<TaskDialog> createState() => _TaskDialogState();
}

class _TaskDialogState extends ConsumerState<TaskDialog> {
  late final _title = TextEditingController(text: widget.task.title);
  late final _description = TextEditingController(text: widget.task.description);
  late TaskPriority _priority = widget.task.priority;
  late DateTime? _due = widget.task.dueAt;
  late String? _spaceId = widget.task.spaceId;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDue() async {
    final now = ref.read(clockProvider)();
    final picked = await showDatePicker(
      context: context,
      initialDate: _due ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null && mounted) {
      setState(() => _due = DateTime(picked.year, picked.month, picked.day, 23, 59));
    }
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    final t = widget.task;
    final updated = TaskItem(
      id: t.id,
      title: title,
      description: _description.text.trim(),
      status: t.status,
      priority: _priority,
      dueAt: _due,
      completedAt: t.completedAt,
      spaceId: _spaceId,
      noteId: t.noteId,
      source: t.source,
      externalId: t.externalId,
    );
    try {
      await ref.read(repositoryProvider).upsertTask(updated);
      if (mounted) Navigator.of(context).pop(true);
    } on RepositoryException {
      if (mounted) showError(context, 'Não foi possível salvar a tarefa.');
    }
  }

  Future<void> _delete() async {
    try {
      await ref.read(repositoryProvider).deleteTask(widget.task.id);
      if (mounted) Navigator.of(context).pop();
    } on RepositoryException {
      if (mounted) showError(context, 'Não foi possível excluir a tarefa.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isNew ? 'Nova tarefa' : 'Tarefa'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const Key('task-title'),
                controller: _title,
                decoration: const InputDecoration(labelText: 'Título'),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('task-description'),
                controller: _description,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(labelText: 'Descrição'),
              ),
              const SizedBox(height: 12),
              SegmentedButton<TaskPriority>(
                showSelectedIcon: false,
                segments: [
                  for (final p in TaskPriority.values)
                    ButtonSegment(
                      value: p,
                      label: Text(p.label, key: Key('task-priority-${p.name}')),
                    ),
                ],
                selected: {_priority},
                onSelectionChanged: (v) => setState(() => _priority = v.first),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('task-due'),
                      onPressed: _pickDue,
                      icon: const Icon(Icons.event_outlined),
                      label: Text(_due == null
                          ? 'Sem prazo'
                          : 'Prazo: ${DateFormat('d MMM', 'pt_BR').format(_due!)}'),
                    ),
                  ),
                  if (_due != null)
                    IconButton(
                      key: const Key('task-due-clear'),
                      tooltip: 'Remover prazo',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _due = null),
                    ),
                ],
              ),
              if (widget.spaces.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  key: const Key('task-space'),
                  initialValue: _spaceId,
                  decoration: const InputDecoration(labelText: 'Espaço'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Sem espaço')),
                    for (final s in widget.spaces)
                      DropdownMenuItem<String?>(value: s.id, child: Text(s.name)),
                  ],
                  onChanged: (v) => setState(() => _spaceId = v),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (!widget.isNew)
          TextButton(
            key: ValueKey('delete-task-${widget.task.id}'),
            onPressed: _delete,
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Excluir'),
          ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(key: const Key('task-save'), onPressed: _save, child: const Text('Salvar')),
      ],
    );
  }
}
