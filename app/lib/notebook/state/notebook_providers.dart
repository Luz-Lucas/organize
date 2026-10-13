import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show KeepAliveLink;

import '../core/notebook_core.dart';
import '../data/notebook_page.dart';
import '../data/notebook_repository.dart';
import '../ui/notebook_session.dart';
import 'notebook_controller.dart';
import 'notebook_pending_store.dart';

/// `main.dart` sobrescreve com [SupabaseNotebookRepository]; os testes, com o Memory.
final notebookRepositoryProvider = Provider<NotebookRepository>(
  (ref) => throw UnimplementedError('notebookRepositoryProvider precisa de override'),
);

/// Fila local de salvamento. Padrão em memória; `main.dart` usa `shared_preferences`.
final notebookPendingStoreProvider = Provider<NotebookPendingStore>((ref) => MemoryNotebookPendingStore());

/// Como codificar uma página para gravar. Padrão: comprime em outro isolate quando a
/// página é grande. Os testes com relógio falso trocam por uma versão síncrona
/// (um isolate de verdade nunca completaria dentro do `FakeAsync`).
final notebookPageEncoderProvider = Provider<Future<String> Function(PageDoc doc)>((ref) => encodePageAsync);

/// Cria o store de imagens de um caderno (o caminho no Storage leva o id da nota).
final notebookImageStoreFactoryProvider = Provider<NotebookImageStore Function(String noteId)>(
  (ref) => throw UnimplementedError('notebookImageStoreFactoryProvider precisa de override'),
);

/// Um [NotebookController] por caderno aberto. Fica vivo enquanto houver algo por
/// salvar (mesmo depois de a tela fechar) e some quando tudo foi confirmado.
final notebookControllerProvider = Provider.autoDispose.family<NotebookController, String>((ref, noteId) {
  KeepAliveLink? link;
  final controller = NotebookController(
    noteId: noteId,
    repo: ref.read(notebookRepositoryProvider),
    images: ref.read(notebookImageStoreFactoryProvider)(noteId),
    pending: ref.read(notebookPendingStoreProvider),
    encoder: ref.read(notebookPageEncoderProvider),
    onPendingChanged: (pending) {
      if (pending) {
        link ??= ref.keepAlive();
      } else {
        link?.close();
        link = null;
      }
    },
  );
  // Ao pausar/esconder o app grava na hora; ao voltar, tenta enviar o que ficou offline.
  final lifecycle = AppLifecycleListener(onStateChange: (_) => unawaited(controller.flush()));
  ref.onDispose(() {
    lifecycle.dispose();
    controller.dispose();
  });
  unawaited(controller.start());
  return controller;
});

/// Ao iniciar o app, envia a fila local de **todos** os cadernos que ficaram com
/// alterações não confirmadas (`notebook.pending.*`), sem precisar abrir cada um:
/// quem mata o app logo depois de escrever não perde a tinta. Cada caderno ganha
/// um controller que fica vivo até enviar tudo e some em seguida.
///
/// Fica de olho (`ref.watch`) na raiz do app.
final notebookStartupSyncProvider = FutureProvider<void>((ref) async {
  final ids = await ref.read(notebookPendingStoreProvider).pendingNoteIds();
  for (final id in ids) {
    // Escutar mantém o controller (autoDispose) vivo até a fila ser enviada.
    final sub = ref.listen(notebookControllerProvider(id), (_, _) {});
    unawaited(sub.read().whenSettled().whenComplete(sub.close));
  }
});

/// 1ª página do caderno (para a miniatura). A chave inclui a data da nota: quando o
/// caderno é salvo, `notes.updated_at` muda e a miniatura é lida de novo.
final notebookFirstPageProvider =
    FutureProvider.autoDispose.family<NotebookPage?, ({String noteId, int stamp})>(
  (ref, key) => ref.watch(notebookRepositoryProvider).firstPage(key.noteId),
);

/// Texto reconhecido por caderno, para a busca de notas. Só é pedido quando há busca.
final notebookRecognizedTextProvider = FutureProvider.autoDispose<Map<String, String>>(
  (ref) => ref.watch(notebookRepositoryProvider).recognizedTextByNote(),
);
