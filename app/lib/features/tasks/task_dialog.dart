import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/repository.dart';
import '../../domain/agenda.dart' show startOfDay;
import '../../domain/ids.dart';
import '../../domain/space.dart';
import '../../domain/task_item.dart';
import '../../domain/task_series.dart';
import '../../ui/common.dart';
import '../../ui/date_labels.dart';
import '../../ui/org_theme.dart';
import '../agenda/repeat_section.dart';
import '../agenda/series_scope_dialog.dart';
import '../github/issue_form.dart';

/// Abre o editor de tarefa: folha de baixo no celular (< 720 dp), diálogo no
/// computador. Devolve `true` quando a tarefa foi salva.
Future<bool?> showTaskEditor(
  BuildContext context, {
  required TaskItem task,
  required List<Space> spaces,
  bool isNew = false,
}) {
  if (MediaQuery.sizeOf(context).width >= 720) {
    return showDialog<bool>(
      context: context,
      builder: (_) => TaskDialog(task: task, spaces: spaces, isNew: isNew),
    );
  }
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => TaskDialog(task: task, spaces: spaces, isNew: isNew, sheet: true),
  );
}

/// Edição de uma tarefa (ou criação, com [isNew]): título, descrição,
/// prioridade, prazo, espaço e, ao editar, exclusão. Fecha com `true` quando
/// salva. Falha ao gravar mantém o diálogo aberto com o que foi digitado.
///
/// Séries: tarefa nova com prazo ganha "Repetir" e grava uma tarefa por ocorrência.
/// Editar ou excluir uma tarefa que tem `seriesId` pergunta antes a quais ocorrências
/// vale; mudar só o status não pergunta.
///
/// Com [sheet] o mesmo formulário é desenhado como folha de baixo (celular),
/// com seletor de status; use [showTaskEditor] para escolher sozinho.
class TaskDialog extends ConsumerStatefulWidget {
  const TaskDialog({
    super.key,
    required this.task,
    required this.spaces,
    this.isNew = false,
    this.sheet = false,
  });

  /// Desenha como folha de baixo (sem `AlertDialog`) e mostra o status.
  final bool sheet;

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
  late TaskStatus _status = widget.task.status;
  final _repeat = RepeatController();
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Repository get _repo => ref.read(repositoryProvider);

  /// Ocorrências da série de [task] (inclusive as concluídas).
  Future<List<TaskItem>> _seriesOf(TaskItem task) async {
    final series = await _repo.listTaskSeries(task.seriesId!);
    return series.any((t) => t.id == task.id) ? series : [...series, task];
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
    final moved = t.moved(_status, ref.read(clockProvider)());
    final updated = t.copyWith(
      title: title,
      description: _description.text.trim(),
      status: moved.status,
      priority: _priority,
      dueAt: _due,
      clearDue: _due == null,
      completedAt: moved.completedAt,
      clearCompleted: moved.completedAt == null,
      spaceId: _spaceId,
      clearSpace: _spaceId == null,
    );
    try {
      final due = _due;
      if (widget.isNew && due != null && _repeat.active) {
        final failure = _repeat.problem(startOfDay(due), due,
            emptyMessage: 'A repetição não gera nenhuma tarefa nesse período.');
        if (failure != null) {
          setState(() => _error = failure);
          return;
        }
        final rule = _repeat.recurrence(startOfDay(due))!;
        await _repo.upsertTasks(TaskSeriesOps.buildSeries(updated, rule, newId));
      } else if (t.seriesId != null && _contentChanged(t, updated)) {
        final scope = await showSeriesScopeDialog(context, deleting: false, labels: SeriesScopeLabels.task);
        if (scope == null || !mounted) return;
        final series = await _seriesOf(t);
        await _repo.upsertTasks(TaskSeriesOps.applyEdit(series, t, updated, scope));
      } else {
        await _repo.upsertTask(updated);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on RepositoryException {
      if (mounted) showError(context, 'Não foi possível salvar a tarefa.');
    }
  }

  /// Mudou algo além do status (que vale só para esta ocorrência e não pergunta).
  bool _contentChanged(TaskItem a, TaskItem b) =>
      a.title != b.title ||
      a.description != b.description ||
      a.priority != b.priority ||
      a.dueAt != b.dueAt ||
      a.spaceId != b.spaceId;

  /// Cria uma issue no GitHub a partir desta tarefa; ao criar, anexa o link ao
  /// fim da descrição e salva a tarefa.
  Future<void> _toIssue() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final result = await showIssueForm(
      context,
      initialTitle: _title.text.trim(),
      initialBody: _description.text.trim(),
    );
    if (result == null || !mounted) return;
    final current = _description.text.trim();
    _description.text = current.isEmpty ? result.issue.url : '$current\n\n${result.issue.url}';
    messenger
      ?..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text('Issue #${result.issue.number} criada e link anexado à tarefa.')));
    await _save();
  }

  Future<void> _delete() async {
    final repo = _repo;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final deleted = widget.task;
    try {
      if (deleted.seriesId != null) {
        // Em tarefa de série a escolha do escopo já é a confirmação.
        final scope = await showSeriesScopeDialog(context, deleting: true, labels: SeriesScopeLabels.task);
        if (scope == null || !mounted) return;
        final series = await _seriesOf(deleted);
        final ids = TaskSeriesOps.deleteIds(series, deleted, scope).toSet();
        final removed = [for (final t in series) if (ids.contains(t.id)) t];
        await repo.deleteTasks(ids.toList());
        if (!mounted) return;
        Navigator.of(context).pop();
        showUndo(
          messenger,
          removed.length == 1 ? 'Tarefa excluída' : '${removed.length} tarefas excluídas',
          () => repo.upsertTasks(removed),
        );
        return;
      }
      await repo.deleteTask(deleted.id);
      if (!mounted) return;
      Navigator.of(context).pop();
      showUndo(messenger, 'Tarefa excluída', () => repo.upsertTask(deleted));
    } on RepositoryException {
      if (mounted) showError(context, 'Não foi possível excluir a tarefa.');
    }
  }

  /// Tarefa nova: "Repetir" (precisa de prazo). Tarefa de série: o resumo da regra.
  List<Widget> _repeatSection(BuildContext context) {
    final theme = Theme.of(context);
    final org = context.org;
    final due = _due;
    if (widget.isNew) {
      if (due == null) {
        return [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Defina um prazo para repetir a tarefa.',
              key: const Key('task-repeat-needs-due'),
              style: theme.textTheme.bodySmall?.copyWith(color: org.inkMuted),
            ),
          ),
        ];
      }
      return [
        const SizedBox(height: 8),
        RepeatSection(
          controller: _repeat,
          startDay: startOfDay(due),
          startsAt: due,
          keyPrefix: 'task',
        ),
      ];
    }
    final t = widget.task;
    if (t.seriesId == null) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'Repete: ${t.recurrence?.shortLabel(t.dueAt ?? ref.read(clockProvider)()) ?? 'em série'}',
          key: const Key('task-series-label'),
          style: theme.textTheme.bodySmall?.copyWith(color: org.accentText),
        ),
      ),
    ];
  }

  Widget _form(BuildContext context) {
    final now = ref.read(clockProvider)();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const Key('task-title'),
          controller: _title,
          autofocus: widget.isNew,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Título'),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('task-description'),
          controller: _description,
          minLines: 2,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Descrição'),
        ),
        if (widget.sheet) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in TaskStatus.values)
                ChoiceChip(
                  key: Key('task-status-${s.name}'),
                  label: Text(switch (s) {
                    TaskStatus.todo => 'A fazer',
                    TaskStatus.doing => 'Fazendo',
                    TaskStatus.done => 'Feito',
                  }),
                  selected: _status == s,
                  onSelected: (_) => setState(() => _status = s),
                ),
            ],
          ),
        ],
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
                    : 'Prazo: ${dueLabel(_due!, now, done: _status == TaskStatus.done)}'),
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
        ..._repeatSection(context),
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
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('task-to-issue'),
            onPressed: _toIssue,
            icon: const Icon(Icons.code, size: 18),
            label: const Text('Criar issue no GitHub'),
          ),
        ),
      ],
    );
  }

  List<Widget> _actions(BuildContext context) => [
        if (!widget.isNew)
          TextButton(
            key: ValueKey('delete-task-${widget.task.id}'),
            onPressed: _delete,
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Excluir'),
          ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(key: const Key('task-save'), onPressed: _save, child: const Text('Salvar')),
      ];

  @override
  Widget build(BuildContext context) {
    final title = widget.isNew ? 'Nova tarefa' : 'Tarefa';
    if (widget.sheet) {
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              _form(context),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                children: _actions(context),
              ),
            ],
          ),
        ),
      );
    }
    return AlertDialog(
      title: Text(title),
      content: SizedBox(width: 420, child: SingleChildScrollView(child: _form(context))),
      actions: _actions(context),
    );
  }
}
