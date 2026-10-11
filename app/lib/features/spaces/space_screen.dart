import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/repository.dart';
import '../../domain/ids.dart';
import '../../domain/note.dart';
import '../../domain/space.dart';
import '../../domain/task_item.dart';
import '../../domain/wikilinks.dart';
import '../../ui/common.dart';
import '../../ui/org_theme.dart';
import '../../ui/org_widgets.dart';
import 'spaces_screen.dart' show iconForKind;
import '../../ui/task_tile.dart';
import '../../app/back_navigation.dart';

class SpaceScreen extends ConsumerWidget {
  const SpaceScreen({super.key, required this.spaceId});

  final String spaceId;

  Future<void> _newNote(BuildContext context, WidgetRef ref, List<Note> all) async {
    final note = Note(id: newId(), title: uniqueTitle('Sem título', all), spaceId: spaceId);
    try {
      await ref.read(repositoryProvider).upsertNote(note);
      if (context.mounted) context.push('/nota/${note.id}');
    } on RepositoryException {
      if (context.mounted) showError(context, 'Não foi possível criar a nota.');
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Space space,
    List<Note> notes,
    List<TaskItem> tasks,
  ) async {
    final nNotes = notes.where((n) => n.spaceId == space.id).length;
    final nTasks = tasks.where((t) => t.spaceId == space.id).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Excluir “${space.name}”?'),
        content: Text(
          'Isso apaga ${plural(nNotes, 'nota', 'notas')} e ${plural(nTasks, 'tarefa', 'tarefas')}. '
          'Os eventos da agenda são mantidos.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Excluir')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(repositoryProvider).deleteSpace(space.id);
      if (context.mounted) context.popOrGo('/espacos');
    } on RepositoryException {
      if (context.mounted) showError(context, 'Não foi possível excluir o espaço.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spaces = ref.watch(spacesProvider);
    final notes = ref.watch(notesProvider);
    final tasks = ref.watch(tasksProvider);
    return asyncView(spaces, (spaceList) {
      final space = spaceList.where((s) => s.id == spaceId).firstOrNull;
      if (space == null) {
        return Scaffold(
          appBar: AppBar(),
          body: const Center(child: EmptyHint('Espaço não encontrado.')),
        );
      }
      return Scaffold(
        appBar: AppBar(
          title: Text(space.name),
          actions: [
            IconButton(
              key: const Key('delete-space'),
              tooltip: 'Excluir espaço',
              icon: const Icon(Icons.delete_outline),
              // Desabilitado até notas e tarefas carregarem: antes disso a
              // contagem da confirmação (notes.value/tasks.value) seria
              // incorretamente 0.
              onPressed: notes.hasValue && tasks.hasValue
                  ? () => _delete(context, ref, space, notes.value!, tasks.value!)
                  : null,
            ),
          ],
        ),
        body: asyncView(notes, (noteList) => asyncView(tasks, (taskList) {
              final spaceNotes = noteList.where((n) => n.spaceId == spaceId).toList();
              final openTasks =
                  taskList.where((t) => t.spaceId == spaceId && !t.isDone).toList();
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  OrgCard(
                    child: Row(
                      children: [
                        Icon(iconForKind(space.kind), color: context.org.accentText, size: 28),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(space.name, style: Theme.of(context).textTheme.titleLarge),
                              const SizedBox(height: 4),
                              Text(
                                '${plural(spaceNotes.length, 'nota', 'notas')} · '
                                '${plural(openTasks.length, 'tarefa aberta', 'tarefas abertas')}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: context.org.inkMuted),
                              ),
                            ],
                          ),
                        ),
                        OrgBadge(space.kind.singular),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      const Expanded(child: SectionHeader('Notas')),
                      TextButton.icon(
                        key: const Key('new-note'),
                        onPressed: () => _newNote(context, ref, noteList),
                        icon: const Icon(Icons.add),
                        label: const Text('Nova nota'),
                      ),
                    ],
                  ),
                  if (spaceNotes.isEmpty) const EmptyHint('Nenhuma nota.'),
                  for (final n in spaceNotes)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: OrgCard(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        onTap: () => context.push('/nota/${n.id}'),
                        child: Row(
                          children: [
                            Icon(Icons.description_outlined, color: context.org.inkMuted),
                            const SizedBox(width: 12),
                            Expanded(child: Text(n.title)),
                          ],
                        ),
                      ),
                    ),
                  const SectionHeader('Tarefas abertas'),
                  if (openTasks.isEmpty) const EmptyHint('Nenhuma tarefa aberta.'),
                  for (final t in openTasks) TaskTile(key: ValueKey(t.id), task: t),
                ],
              );
            })),
      );
    });
  }
}
