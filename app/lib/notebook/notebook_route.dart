import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/providers.dart';
import '../features/notes/note_screen.dart';
import 'state/notebook_providers.dart';
import 'ui/notebook_screen.dart';

/// Rota `/caderno/:id`: liga a tela do Caderno ao controller do caderno.
///
/// Fica fora da casca (sem barra inferior/lateral) para a escrita ter a tela toda.
/// Voltar fecha o caderno; se não há para onde voltar (link direto), vai para Notas.
class NotebookRoute extends ConsumerWidget {
  const NotebookRoute({super.key, required this.noteId});

  final String noteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(notesProvider);
    final loaded = notes.value;
    final note = loaded?.where((n) => n.id == noteId).firstOrNull;
    final Widget body;
    if (loaded == null) {
      body = const Scaffold(body: Center(child: CircularProgressIndicator()));
    } else if (note == null) {
      body = Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Caderno não encontrado.')),
      );
    } else if (!note.isNotebook) {
      body = NoteScreen(key: ValueKey(noteId), noteId: noteId);
    } else {
      body = NotebookScreen(
        key: const Key('notebook-screen'),
        noteId: noteId,
        title: note.title,
        session: ref.watch(notebookControllerProvider(noteId)),
      );
    }
    return PopScope(
      canPop: context.canPop(),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go('/notas');
      },
      child: body,
    );
  }
}

/// Rota `/nota/:id`: abre o editor de texto, ou o caderno se a nota for um caderno
/// (links, listas de espaço, busca e atalhos apontam todos para `/nota/<id>`).
class NoteOrNotebookRoute extends ConsumerStatefulWidget {
  const NoteOrNotebookRoute({super.key, required this.noteId});

  final String noteId;

  @override
  ConsumerState<NoteOrNotebookRoute> createState() => _NoteOrNotebookRouteState();
}

class _NoteOrNotebookRouteState extends ConsumerState<NoteOrNotebookRoute> {
  bool _redirected = false;

  @override
  Widget build(BuildContext context) {
    final notes = ref.watch(notesProvider).value;
    final note = notes?.where((n) => n.id == widget.noteId).firstOrNull;
    if (notes == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (note != null && note.isNotebook) {
      if (!_redirected) {
        _redirected = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.pushReplacement('/caderno/${widget.noteId}');
        });
      }
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return NoteScreen(key: ValueKey(widget.noteId), noteId: widget.noteId);
  }
}
