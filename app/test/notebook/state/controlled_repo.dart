import 'dart:async';

import 'package:organizacional/data/repository.dart';
import 'package:organizacional/notebook/core/notebook_core.dart';
import 'package:organizacional/notebook/data/memory_notebook_repository.dart';
import 'package:organizacional/notebook/data/notebook_page.dart';
import 'package:organizacional/notebook/data/notebook_repository.dart';

/// Repositório de teste que embrulha o [MemoryNotebookRepository] e deixa o teste
/// controlar o que o realtime entrega (atraso, queda, dados omitidos) e os erros
/// de gravação.
class ControlledRepo implements NotebookRepository {
  ControlledRepo(this.inner);

  final MemoryNotebookRepository inner;

  // ---- realtime --------------------------------------------------------------

  /// true: o stream segue o repositório na hora. false: só emite o estado inicial
  /// e o que o teste mandar por [pushRealtime]/[emitRaw] (realtime atrasado).
  bool liveRealtime = true;

  /// Quantas próximas chamadas de [watchPages] falham (erro e fecha, como a
  /// biblioteca faz quando a consulta inicial falha).
  int watchFailuresLeft = 0;

  /// Os eventos omitem `data` (linhas grandes demais para o realtime).
  bool stripData = false;

  int watchCalls = 0;
  final _manual = <StreamController<List<NotebookPage>>>[];

  List<NotebookPage> _view(List<NotebookPage> l) => stripData ? [for (final p in l) p.copyWith(data: '')] : l;

  @override
  Stream<List<NotebookPage>> watchPages(String noteId) {
    watchCalls++;
    if (watchFailuresLeft > 0) {
      watchFailuresLeft--;
      return Stream<List<NotebookPage>>.error(const RepositoryException('Sem conexão (simulado)'));
    }
    if (liveRealtime) return inner.watchPages(noteId).map(_view);
    late final StreamController<List<NotebookPage>> c;
    c = StreamController<List<NotebookPage>>(
      onListen: () async => c.add(_view(await inner.listPages(noteId))),
      onCancel: () => _manual.remove(c),
    );
    _manual.add(c);
    return c.stream;
  }

  /// Entrega ao controller o estado atual do servidor (o evento que "chegou").
  Future<void> pushRealtime(String noteId) async {
    final snapshot = _view(await inner.listPages(noteId));
    for (final c in List.of(_manual)) {
      c.add(snapshot);
    }
  }

  /// Entrega uma lista qualquer (por exemplo, uma antiga que chega atrasada).
  void emitRaw(List<NotebookPage> list) {
    for (final c in List.of(_manual)) {
      c.add(_view(list));
    }
  }

  /// Fecha os streams sem erro (a conexão do realtime caiu em silêncio).
  void closeStreams() {
    for (final c in List.of(_manual)) {
      c.close();
    }
    _manual.clear();
  }

  // ---- gravação ---------------------------------------------------------------

  /// Se devolver um erro para a página, o `savePage` lança.
  Object? Function(NotebookPage page)? saveError;

  /// Segura os `savePage` até o completer terminar (gravação em voo).
  Completer<void>? saveGate;

  /// Roda antes de cada `savePage` (por exemplo, para simular outro aparelho gravando no meio).
  Future<void> Function(NotebookPage page)? beforeSave;

  final savedVersions = <int>[];
  final savedPageIds = <String>[];

  @override
  Future<NotebookPage> savePage(NotebookPage page) async {
    await beforeSave?.call(page);
    savedVersions.add(page.version);
    savedPageIds.add(page.id);
    final gate = saveGate;
    if (gate != null) await gate.future;
    final err = saveError?.call(page);
    if (err != null) throw err;
    return inner.savePage(page);
  }

  int saveAttemptsFor(String pageId) => savedPageIds.where((i) => i == pageId).length;

  // ---- o resto delega ----------------------------------------------------------

  int listPagesCalls = 0;
  int touchCalls = 0;

  @override
  Future<void> touchNote(String noteId) async {
    touchCalls++;
    await inner.touchNote(noteId);
  }

  @override
  Future<List<NotebookPage>> listPages(String noteId) {
    listPagesCalls++;
    return inner.listPages(noteId);
  }

  @override
  Future<NotebookPage> addPage(String noteId, {PageBackground background = PageBackground.lined, String? id, int? at}) =>
      inner.addPage(noteId, background: background, id: id, at: at);

  @override
  Future<void> deletePage(String pageId) => inner.deletePage(pageId);

  @override
  Future<NotebookPage> duplicatePage(String pageId) => inner.duplicatePage(pageId);

  @override
  Future<NotebookPage?> firstPage(String noteId) => inner.firstPage(noteId);

  @override
  Future<Map<String, String>> recognizedTextByNote() => inner.recognizedTextByNote();

  @override
  Future<void> reorder(String noteId, List<String> pageIds) => inner.reorder(noteId, pageIds);

  @override
  Future<void> setBackground(String pageId, PageBackground background) => inner.setBackground(pageId, background);
}
