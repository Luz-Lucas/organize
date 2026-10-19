import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/repository.dart';
import 'linked_notes.dart';

/// Acrescenta [block] às notas do caderno e avisa: "Adicionado às notas de …", com
/// **Abrir** (abre a nota) e **Desfazer** (tira o bloco). Devolve se deu certo.
///
/// Tudo o que depende do [context] e do [ref] é capturado antes do primeiro
/// `await`: o aviso e o "Desfazer" continuam valendo depois de a tela fechar.
Future<bool> addToNotebookNotes(
  BuildContext context,
  WidgetRef ref, {
  required String notebookId,
  required String notebookTitle,
  required String block,
}) async {
  final linked = ref.read(linkedNotesProvider);
  final messenger = ScaffoldMessenger.of(context);
  final router = GoRouter.of(context);
  final actionColor = Theme.of(context).colorScheme.inversePrimary;
  final NoteAddition added;
  try {
    added = await linked.add(notebookId, block);
  } on RepositoryException {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Não foi possível adicionar às notas do caderno.')));
    return false;
  }
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        key: const Key('linked-note-added'),
        duration: const Duration(seconds: 8),
        content: Row(
          children: [
            Expanded(child: Text('Adicionado às notas de $notebookTitle')),
            TextButton(
              key: const Key('linked-note-open'),
              style: TextButton.styleFrom(foregroundColor: actionColor),
              onPressed: () {
                messenger.hideCurrentSnackBar();
                unawaited(router.push('/nota/${added.note.id}'));
              },
              child: const Text('Abrir'),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'Desfazer',
          onPressed: () async {
            try {
              await linked.undo(notebookId, added);
            } on RepositoryException {
              messenger.showSnackBar(const SnackBar(content: Text('Não foi possível desfazer.')));
            }
          },
        ),
      ),
    );
  return true;
}

/// Botão "Notas": abre a nota vinculada ao caderno (cria uma vazia se ainda não há).
Future<void> openNotebookNotes(BuildContext context, WidgetRef ref, String notebookId) async {
  final linked = ref.read(linkedNotesProvider);
  final messenger = ScaffoldMessenger.of(context);
  final router = GoRouter.of(context);
  try {
    final note = (await linked.ensure(notebookId)).note;
    unawaited(router.push('/nota/${note.id}'));
  } on RepositoryException {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Não foi possível abrir as notas do caderno.')));
  }
}
