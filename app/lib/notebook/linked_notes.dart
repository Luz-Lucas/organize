import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../data/repository.dart';
import '../domain/ids.dart';
import '../domain/note.dart';
import '../domain/notebook_linked_note.dart';
import '../domain/wikilinks.dart';

/// A nota vinculada de um caderno e se ela acabou de ser criada.
class LinkedNote {
  const LinkedNote(this.note, {required this.created});

  final Note note;

  /// Criada agora (e não já existente / reaproveitada).
  final bool created;
}

/// Um bloco acrescentado à nota vinculada: o que [LinkedNotes.undo] precisa para desfazer.
class NoteAddition {
  const NoteAddition(this.note, this.block, {required this.created});

  /// A nota vinculada, já com o bloco.
  final Note note;

  /// O texto acrescentado (como foi gravado).
  final String block;

  /// A nota foi criada neste envio.
  final bool created;
}

/// "Notas do caderno": cada caderno tem no máximo uma nota de texto vinculada,
/// "Notas — nome do caderno", na mesma pasta; tudo que se envia para as notas do caderno
/// é acrescentado ao fim dela.
///
/// As notas não têm merge (a última gravação vence), então cada operação **relê a
/// nota mais recente do repositório** logo antes de gravar, para não apagar o que
/// outro aparelho escreveu. Sem resposta do servidor em [readTimeout] (sem rede),
/// usa as notas que o app já tem ([cachedNotes]).
class LinkedNotes {
  LinkedNotes(
    this._repo, {
    this.cachedNotes,
    this.readTimeout = const Duration(seconds: 4),
  });

  final Repository _repo;
  final List<Note>? Function()? cachedNotes;
  final Duration readTimeout;

  Future<List<Note>> _latest() async {
    try {
      return await _repo.watchNotes().first.timeout(readTimeout);
    } on TimeoutException {
      final cached = cachedNotes?.call();
      if (cached != null) return cached;
      throw const RepositoryException('Sem conexão para ler as notas.');
    }
  }

  /// A nota vinculada ao caderno [notebookId]; cria uma vazia se ainda não há.
  Future<LinkedNote> ensure(String notebookId) async => _resolve(notebookId);

  /// Acrescenta [block] ao fim da nota vinculada (criando-a na primeira vez).
  /// Lança [RepositoryException] se não puder gravar.
  Future<NoteAddition> add(String notebookId, String block) async {
    final target = await _resolve(notebookId);
    final updated = target.note.copyWith(body: appendBlock(target.note.body, block));
    await _repo.upsertNote(updated);
    return NoteAddition(updated, block, created: target.created);
  }

  /// Desfaz [add]: tira o bloco da nota (se ele ainda estiver lá). Se a nota foi
  /// criada naquele envio e ficou vazia, apaga a nota e solta o vínculo.
  Future<void> undo(String notebookId, NoteAddition addition) async {
    final all = await _latest();
    final current = all.where((n) => n.id == addition.note.id).firstOrNull;
    if (current == null) return;
    final body = removeBlock(current.body, addition.block);
    if (body == null) return;
    if (addition.created && body.trim().isEmpty) {
      await _repo.deleteNote(current.id);
      final book = all.where((n) => n.id == notebookId).firstOrNull;
      if (book != null && book.linkedNoteId == current.id) await _repo.upsertNote(book.withLinkedNoteId(null));
      return;
    }
    await _repo.upsertNote(current.copyWith(body: body));
  }

  Future<LinkedNote> _resolve(String notebookId) async {
    final all = await _latest();
    final book = all.where((n) => n.id == notebookId && n.isNotebook).firstOrNull;
    if (book == null) throw const RepositoryException('Caderno não encontrado.');
    final id = book.linkedNoteId;
    final existing = id == null ? null : all.where((n) => n.id == id && !n.isNotebook).firstOrNull;
    if (existing != null) return LinkedNote(existing, created: false);

    final base = 'Notas — ${book.title}';
    final taken = {for (final n in all) normalizeTitle(n.title): n};
    final linkedElsewhere = {for (final n in all) ?n.linkedNoteId};
    // "Notas — X" já existe: reaproveita se estiver vazia (e não for de outro caderno).
    final clash = taken[normalizeTitle(base)];
    if (clash != null && !clash.isNotebook && clash.body.trim().isEmpty && !linkedElsewhere.contains(clash.id)) {
      await _repo.upsertNote(book.withLinkedNoteId(clash.id));
      return LinkedNote(clash, created: false);
    }
    var title = base;
    for (var i = 2; taken.containsKey(normalizeTitle(title)); i++) {
      title = '$base ($i)';
    }
    final note = Note(id: newId(), title: title, spaceId: book.spaceId);
    await _repo.upsertNote(note);
    try {
      await _repo.upsertNote(book.withLinkedNoteId(note.id));
    } on RepositoryException {
      // Sem o vínculo a nota ficaria solta: desfaz (no melhor esforço) e avisa.
      try {
        await _repo.deleteNote(note.id);
      } on RepositoryException {
        // Segue o erro original.
      }
      rethrow;
    }
    return LinkedNote(note, created: true);
  }
}

final linkedNotesProvider = Provider<LinkedNotes>(
  (ref) => LinkedNotes(ref.watch(repositoryProvider), cachedNotes: () => ref.read(notesProvider).value),
);
