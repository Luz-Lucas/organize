import 'dart:async';

import '../../data/repository.dart';
import '../../domain/ids.dart';
import '../core/notebook_core.dart';
import 'notebook_page.dart';
import 'notebook_repository.dart';

/// Implementação em memória (testes). Reproduz a versão otimista, o merge em
/// conflito e a cascata de excluir a nota. Vários "aparelhos" podem compartilhar
/// a mesma instância.
class MemoryNotebookRepository implements NotebookRepository {
  final _pages = <String, NotebookPage>{};
  final _changes = StreamController<void>.broadcast(sync: true);

  /// Quando true, toda escrita falha, simulando uma queda de conexão.
  bool failWrites = false;

  /// Notas "tocadas" (uma entrada por savePage), para os testes.
  final touchedNoteIds = <String>[];

  /// Quantas gravações de dados chegaram ao servidor (por savePage bem-sucedido).
  int saveCount = 0;

  List<NotebookPage> _sorted(String noteId) =>
      _pages.values.where((p) => p.noteId == noteId).toList()..sort((a, b) => a.idx.compareTo(b.idx));

  /// Chamado a cada tentativa de escrita (antes de falhar ou não), para os testes.
  void Function()? onWriteAttempt;

  void _guardWrite() {
    onWriteAttempt?.call();
    if (failWrites) throw const RepositoryException('Sem conexão (simulado)');
  }

  void _emit() => _changes.add(null);

  /// Simula `on delete cascade` da nota.
  void removeNote(String noteId) {
    _pages.removeWhere((_, p) => p.noteId == noteId);
    _emit();
  }

  @override
  Stream<List<NotebookPage>> watchPages(String noteId) {
    StreamSubscription<void>? sub;
    late final StreamController<List<NotebookPage>> controller;
    controller = StreamController<List<NotebookPage>>(
      onListen: () {
        controller.add(_sorted(noteId));
        sub = _changes.stream.listen((_) => controller.add(_sorted(noteId)));
      },
      onCancel: () {
        sub?.cancel();
        controller.close();
      },
    );
    return controller.stream;
  }

  @override
  Future<List<NotebookPage>> listPages(String noteId) async => _sorted(noteId);

  @override
  Future<NotebookPage?> firstPage(String noteId) async => _sorted(noteId).firstOrNull;

  @override
  Future<Map<String, String>> recognizedTextByNote() async {
    final out = <String, List<String>>{};
    final all = _pages.values.where((p) => p.recognizedText.isNotEmpty).toList()
      ..sort((a, b) => a.idx.compareTo(b.idx));
    for (final p in all) {
      out.putIfAbsent(p.noteId, () => []).add(p.recognizedText);
    }
    return {for (final e in out.entries) e.key: e.value.join('\n')};
  }

  /// Só para testes: simula o reconhecimento de escrita (fase 2).
  void setRecognizedText(String pageId, String text) {
    final p = _pages[pageId];
    if (p == null) return;
    _pages[pageId] = NotebookPage(
      id: p.id, noteId: p.noteId, idx: p.idx, background: p.background, data: p.data,
      recognizedText: text, version: p.version, updatedAt: p.updatedAt,
    );
    _emit();
  }

  @override
  Future<NotebookPage> addPage(
    String noteId, {
    PageBackground background = PageBackground.lined,
    String? id,
    int? at,
  }) async {
    _guardWrite();
    final existing = id == null ? null : _pages[id];
    if (existing != null) return existing;
    final order = [for (final p in _sorted(noteId)) p.id];
    final page = NotebookPage(
      id: id ?? newId(),
      noteId: noteId,
      idx: order.length,
      background: background,
      updatedAt: DateTime.now(),
    );
    _pages[page.id] = page;
    order.insert((at ?? order.length).clamp(0, order.length), page.id);
    _reindex(noteId, order);
    _emit();
    return _pages[page.id]!;
  }

  @override
  Future<NotebookPage> savePage(NotebookPage page) async {
    _guardWrite();
    final current = _pages[page.id];
    NotebookPage result;
    if (current == null) {
      // Apagada em outro aparelho: recria no fim, sem perder a tinta.
      result = page.copyWith(idx: _sorted(page.noteId).length, version: 1, updatedAt: DateTime.now());
    } else {
      final String data;
      try {
        data = current.version == page.version ? page.data : mergePageData(current.data, page.data);
      } on PageDecodeException catch (e) {
        throw NotebookRepositoryException(e.message, kind: NotebookErrorKind.newerFormat);
      }
      // O fundo não entra aqui: quem troca o fundo é o setBackground.
      result = current.copyWith(
        data: data,
        version: current.version + 1,
        updatedAt: DateTime.now(),
      );
    }
    _pages[result.id] = result;
    saveCount++;
    touchedNoteIds.add(page.noteId);
    _emit();
    return result;
  }

  @override
  Future<void> setBackground(String pageId, PageBackground background) async {
    _guardWrite();
    final p = _pages[pageId];
    if (p == null) return;
    _pages[pageId] = p.copyWith(background: background);
    _emit();
  }

  void _reindex(String noteId, List<String> order) {
    for (var i = 0; i < order.length; i++) {
      _pages[order[i]] = _pages[order[i]]!.copyWith(idx: i);
    }
  }

  @override
  Future<void> deletePage(String pageId) async {
    _guardWrite();
    final p = _pages.remove(pageId);
    if (p == null) return;
    _reindex(p.noteId, [for (final x in _sorted(p.noteId)) x.id]);
    _emit();
  }

  @override
  Future<NotebookPage> duplicatePage(String pageId) async {
    final src = _pages[pageId];
    if (src == null) throw const RepositoryException('Página não encontrada.');
    final copy = await addPage(src.noteId, background: src.background, at: src.idx + 1);
    _pages[copy.id] = copy.copyWith(data: src.data);
    _emit();
    return _pages[copy.id]!;
  }

  @override
  Future<void> reorder(String noteId, List<String> pageIds) async {
    _guardWrite();
    final current = {for (final p in _sorted(noteId)) p.id};
    if (pageIds.length != current.length || !current.containsAll(pageIds)) {
      throw const RepositoryException('A nova ordem não corresponde às páginas do caderno.');
    }
    _reindex(noteId, pageIds);
    _emit();
  }
}
