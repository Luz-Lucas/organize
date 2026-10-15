import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../data/repository.dart';
import '../../../domain/note.dart';
import '../../../domain/space.dart';
import '../../../notebook/data/notebook_image_purger.dart';
import '../../../notebook/state/notebook_providers.dart';
import '../../../ui/common.dart';
import 'cover_editor.dart';
import 'notebooks_logic.dart';

/// Menu de um caderno (segurar na árvore de notas ou na grade de Cadernos):
/// Capa, Mover para pasta, Renomear e Excluir.
Future<void> showNotebookMenu(BuildContext context, WidgetRef ref, Note note) async {
  final action = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(note.title, overflow: TextOverflow.ellipsis),
      children: [
        SimpleDialogOption(
          key: const Key('notebook-menu-cover'),
          onPressed: () => Navigator.of(ctx).pop('cover'),
          child: const Text('Capa…'),
        ),
        SimpleDialogOption(
          key: const Key('notebook-menu-move'),
          onPressed: () => Navigator.of(ctx).pop('move'),
          child: const Text('Mover para pasta'),
        ),
        SimpleDialogOption(
          key: const Key('notebook-menu-rename'),
          onPressed: () => Navigator.of(ctx).pop('rename'),
          child: const Text('Renomear'),
        ),
        SimpleDialogOption(
          key: const Key('notebook-menu-delete'),
          onPressed: () => Navigator.of(ctx).pop('delete'),
          child: const Text('Excluir'),
        ),
      ],
    ),
  );
  if (!context.mounted) return;
  switch (action) {
    case 'cover':
      await editNotebookCover(context, ref, note);
    case 'move':
      await moveNotebook(context, ref, note);
    case 'rename':
      await renameNotebook(context, ref, note);
    case 'delete':
      await deleteNotebook(context, ref, note);
  }
}

/// Folha com as pastas (matérias, pastas e "Sem pasta"); grava o `space_id` escolhido.
Future<void> moveNotebook(BuildContext context, WidgetRef ref, Note note) async {
  final spaces = ref.read(spacesProvider).value ?? const <Space>[];
  final groups = splitFolders(spaces);
  // Devolve o id da pasta, ou '' para "Sem pasta" (null fica para "fechou a folha").
  final picked = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Mover “${note.title}” para…',
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(ctx).textTheme.titleMedium),
            ),
            for (final s in [...groups.materias, ...groups.others])
              ListTile(
                key: ValueKey('move-to-${s.id}'),
                leading: FolderDot(color: parseFolderColor(s.color)),
                title: Text(s.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: s.kind == SpaceKind.materia ? const Text('Matéria') : null,
                selected: note.spaceId == s.id,
                trailing: note.spaceId == s.id ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(ctx).pop(s.id),
              ),
            ListTile(
              key: const ValueKey('move-to-none'),
              leading: const Icon(Icons.folder_off_outlined),
              title: const Text('Sem pasta'),
              selected: note.spaceId == null,
              trailing: note.spaceId == null ? const Icon(Icons.check) : null,
              onTap: () => Navigator.of(ctx).pop(''),
            ),
          ],
        ),
      ),
    ),
  );
  if (picked == null || !context.mounted) return;
  final target = picked.isEmpty ? null : picked;
  if (target == note.spaceId) return;
  try {
    await ref.read(repositoryProvider).upsertNote(note.withSpace(target));
  } on RepositoryException {
    if (context.mounted) showError(context, 'Não foi possível mover o caderno.');
  }
}

Future<void> renameNotebook(BuildContext context, WidgetRef ref, Note note) async {
  final title = await showDialog<String>(
    context: context,
    builder: (_) => _RenameNotebookDialog(initial: note.title),
  );
  if (title == null || title.isEmpty || title == note.title || !context.mounted) return;
  try {
    await ref.read(repositoryProvider).upsertNote(note.copyWith(title: title));
  } on RepositoryException catch (e) {
    if (context.mounted) {
      showError(context, e.duplicate ? 'Já existe uma nota com esse título.' : 'Não foi possível renomear o caderno.');
    }
  }
}

Future<void> deleteNotebook(BuildContext context, WidgetRef ref, Note note) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Excluir “${note.title}”?'),
      content: const Text('As páginas e imagens do caderno serão apagadas. Essa ação não pode ser desfeita.'),
      actions: [
        TextButton(
          key: const Key('notebook-delete-cancel'),
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('notebook-delete-confirm'),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Excluir'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final images = ref.read(notebookImageStoreFactoryProvider)(note.id);
  try {
    await ref.read(repositoryProvider).deleteNote(note.id);
  } on RepositoryException {
    if (context.mounted) showError(context, 'Não foi possível excluir o caderno.');
    return;
  }
  // O banco apagou as páginas em cascata; as imagens só saem pela API do Storage.
  if (images is NotebookImagePurger) {
    unawaited((images as NotebookImagePurger).purgeAll().catchError((Object _) {}));
  }
}

class _RenameNotebookDialog extends StatefulWidget {
  const _RenameNotebookDialog({required this.initial});

  final String initial;

  @override
  State<_RenameNotebookDialog> createState() => _RenameNotebookDialogState();
}

class _RenameNotebookDialogState extends State<_RenameNotebookDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Renomear caderno'),
        content: TextField(key: const Key('notebook-rename-field'), controller: _controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
          FilledButton(
            key: const Key('notebook-rename-ok'),
            onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
            child: const Text('Salvar'),
          ),
        ],
      );
}

/// Bolinha com a cor da pasta (a cor do tema se a pasta não tem cor).
class FolderDot extends StatelessWidget {
  const FolderDot({super.key, required this.color, this.size = 12});

  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color ?? Theme.of(context).colorScheme.tertiary,
          shape: BoxShape.circle,
        ),
      );
}
