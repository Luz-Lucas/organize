import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/repository.dart';
import '../../domain/note.dart';
import '../../ui/common.dart';

/// Menu de uma nota (segurar na lista de notas): Renomear e Excluir.
/// [activeNoteId] é a nota aberta ao lado (computador): se for esta, sai dela antes de excluir.
Future<void> showNoteMenu(BuildContext context, WidgetRef ref, Note note, {String? activeNoteId}) async {
  final action = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(note.title, overflow: TextOverflow.ellipsis),
      children: [
        SimpleDialogOption(
          key: const Key('note-menu-rename'),
          onPressed: () => Navigator.of(ctx).pop('rename'),
          child: const Text('Renomear'),
        ),
        SimpleDialogOption(
          key: const Key('note-menu-delete'),
          onPressed: () => Navigator.of(ctx).pop('delete'),
          child: const Text('Excluir'),
        ),
      ],
    ),
  );
  if (!context.mounted) return;
  switch (action) {
    case 'rename':
      await renameNote(context, ref, note);
    case 'delete':
      await deleteNote(context, ref, note, wasOpen: note.id == activeNoteId);
  }
}

Future<void> renameNote(BuildContext context, WidgetRef ref, Note note) async {
  final title = await showDialog<String>(
    context: context,
    builder: (_) => _RenameNoteDialog(initial: note.title),
  );
  if (title == null || title.isEmpty || title == note.title || !context.mounted) return;
  // Um rascunho não salvo da nota leva o título novo junto (senão o rascunho o desfaria).
  final drafts = ref.read(noteDraftsProvider);
  final draft = drafts.take(note.id);
  try {
    await ref.read(repositoryProvider).upsertNote((draft ?? note).copyWith(title: title));
  } on RepositoryException catch (e) {
    if (draft != null) drafts.put(draft);
    if (context.mounted) {
      showError(context, e.duplicate ? 'Já existe uma nota com esse título.' : 'Não foi possível renomear a nota.');
    }
  }
}

Future<void> deleteNote(BuildContext context, WidgetRef ref, Note note, {bool wasOpen = false}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Excluir “${note.title}”?'),
      actions: [
        TextButton(
          key: const Key('note-delete-cancel'),
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('note-delete-confirm'),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Excluir'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final repo = ref.read(repositoryProvider);
  final drafts = ref.read(noteDraftsProvider);
  if (wasOpen) {
    // A nota aberta ao lado salva o que falta ao fechar: fecha antes e espera esse
    // salvamento sair, para ele não recriar a nota depois de excluída.
    context.go('/notas');
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  final restore = drafts.take(note.id) ?? note;
  try {
    await repo.deleteNote(note.id);
    showUndo(messenger, 'Nota excluída', () => repo.upsertNote(restore));
  } on RepositoryException {
    drafts.put(restore);
    if (context.mounted) showError(context, 'Não foi possível excluir a nota.');
  }
}

class _RenameNoteDialog extends StatefulWidget {
  const _RenameNoteDialog({required this.initial});

  final String initial;

  @override
  State<_RenameNoteDialog> createState() => _RenameNoteDialogState();
}

class _RenameNoteDialogState extends State<_RenameNoteDialog> {
  late final _controller = TextEditingController(text: widget.initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.initial.length);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Renomear nota'),
        content: TextField(
          key: const Key('note-rename-field'),
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
          FilledButton(key: const Key('note-rename-ok'), onPressed: _submit, child: const Text('Salvar')),
        ],
      );
}
