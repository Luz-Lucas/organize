import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;

import '../../domain/ids.dart';
import '../core/notebook_core.dart';
import '../data/notebook_page.dart';
import '../data/notebook_repository.dart';
import '../ui/notebook_session.dart';
import 'notebook_pending_store.dart';

/// Uma página como o controller a mantém: o que está na tela, a versão do servidor
/// em que isso se baseia e se há alterações ainda não confirmadas ([dirty]).
class _Local {
  _Local(this.id, this.background, this.doc, this.version, {this.dirty = false, this.locked = false})
      : seenVersion = version;

  final String id;
  PageBackground background;
  PageDoc doc;

  /// Versão usada no `where version =` do próximo save. **Só** vem de um
  /// `savePage` bem-sucedido (ou da leitura inicial, que traz versão e conteúdo
  /// juntos). O realtime atualiza [doc], nunca esta versão: se ele a adotasse sem
  /// o conteúdo ter sido mesclado, o próximo save apagaria a tinta do outro aparelho.
  int version;

  /// Maior versão remota cujo conteúdo já foi mesclado em [doc] (evita decodificar
  /// de novo o mesmo evento).
  int seenVersion;

  bool dirty;

  /// Muda a cada edição; permite saber se houve edição durante uma gravação em voo.
  int gen = 0;

  /// Página em formato desconhecido (gravada por uma versão mais nova do app):
  /// só leitura e nunca regravada, para não sobrescrever o que não entendemos.
  /// Uma página travada nunca fica [dirty].
  bool locked;

  /// O servidor recusou esta página por tamanho (CHECK de 4 MB).
  bool tooLarge = false;

  /// Perto do limite de tamanho (aviso, ainda é salva).
  bool nearLimit = false;

  /// Edição ([gen]) que o servidor recusou de forma permanente: não é reenviada
  /// enquanto a página não mudar.
  int rejectedGen = -1;

  bool get blocked => tooLarge && rejectedGen == gen;

  /// Há algo a enviar ao servidor.
  bool get needsSend => dirty && !locked && !blocked;

  /// Tem tinta que só existe no aparelho (vai para a fila local).
  bool get holdsInk => dirty && !locked;

  PageNotice get notice => locked
      ? PageNotice.newerVersion
      : tooLarge
          ? PageNotice.tooLarge
          : nearLimit
              ? PageNotice.nearLimit
              : PageNotice.none;
}

/// Stream que repete o último valor a cada nova escuta (e pode ser escutado várias vezes).
class _ReplayStream<T> extends Stream<T> {
  _ReplayStream(this._source, this._current);

  final Stream<T> _source;
  final T? Function() _current;

  @override
  bool get isBroadcast => true;

  @override
  StreamSubscription<T> listen(
    void Function(T event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    late final StreamController<T> out;
    StreamSubscription<T>? inner;
    out = StreamController<T>(
      onListen: () {
        final latest = _current();
        if (latest != null) out.add(latest);
        inner = _source.listen(out.add, onError: out.addError, onDone: out.close);
      },
      onCancel: () => inner?.cancel(),
    );
    return out.stream.listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }
}

sealed class _Op {
  _Op(this.id);
  final String id;
}

class _AddOp extends _Op {
  _AddOp(super.id, this.background);
  final PageBackground background;
}

class _DelOp extends _Op {
  _DelOp(super.id);
}

class _BgOp extends _Op {
  _BgOp(super.id, this.background);
  final PageBackground background;
}

/// Liga a tela do Caderno ao [NotebookRepository]: guarda o documento de cada
/// página, salva sozinho 1,5 s depois do último gesto (no máximo 10 s depois do
/// primeiro, e ao sair/pausar), mescla o que chega de outros aparelhos e, sem
/// conexão, guarda tudo no aparelho (`shared_preferences`) e reenvia quando a rede
/// volta.
///
/// Operações de estrutura (nova página, apagar, duplicar, fundo) valem na hora na
/// tela e entram numa fila de operações que o servidor recebe em ordem.
///
/// Proteções contra perda de dados:
/// * **por id**: todas as operações por página usam o id (a ordem muda sob a tela);
/// * **cópia local**: a tinta pendente vai para o aparelho ≤ 300 ms depois de cada
///   edição e só sai de lá depois que o servidor confirma;
/// * **lista do servidor atrasada**: o efeito de cada operação de estrutura é
///   lembrado ("apagadas/criadas/fundos ainda não confirmados") até o realtime
///   mostrar o mesmo;
/// * **stream**: se o realtime cai, assina de novo com espera crescente; a última
///   lista de páginas fica no aparelho para abrir e escrever offline;
/// * **versão**: a versão usada para salvar só vem do `savePage`;
/// * **erros permanentes** (página grande, caderno excluído, formato novo) não
///   viram "offline eterno" nem laço de reenvio.
class NotebookController implements NotebookSession {
  NotebookController({
    required this.noteId,
    required this._repo,
    required this._images,
    required this._pending,
    this.debounce = const Duration(milliseconds: 1500),
    this.maxWait = const Duration(seconds: 10),
    this.persistDelay = const Duration(milliseconds: 300),
    this.retryBase = const Duration(seconds: 5),
    this.retryMax = const Duration(seconds: 60),
    this.onPendingChanged,
    this.pageWarnLength = 3000000,
    this.pageMaxLength = 4000000,
  });

  final String noteId;
  final NotebookRepository _repo;
  final NotebookImageStore _images;
  final NotebookPendingStore _pending;

  /// Espera sem gestos antes de salvar no servidor.
  final Duration debounce;

  /// Limite da espera: durante escrita contínua salva pelo menos a cada [maxWait].
  final Duration maxWait;

  /// Espera (curta) antes de guardar a cópia local depois de uma edição.
  final Duration persistDelay;
  final Duration retryBase;
  final Duration retryMax;

  /// Tamanho (caracteres do dado codificado) a partir do qual a página avisa que
  /// está perto do limite do servidor.
  final int pageWarnLength;

  /// Tamanho acima do qual o servidor recusa a página (CHECK de 4.000.000 bytes).
  final int pageMaxLength;

  /// Avisa quando passa a existir (true) ou deixa de existir (false) algo não confirmado
  /// no servidor. O provider usa para manter o controller vivo até terminar de salvar.
  final void Function(bool pending)? onPendingChanged;

  var _pages = <_Local>[];
  final _ops = <_Op>[];
  List<NotebookPage> _lastRemote = const [];
  bool _remoteKnown = false;
  Map<String, Object?>? _restored;

  /// Efeitos de operações já aceitas pelo servidor que o realtime ainda não mostrou.
  final _deletedUnconfirmed = <String>{};
  final _createdUnconfirmed = <String>{};
  final _bgUnconfirmed = <String, PageBackground>{};

  /// Tinta de páginas travadas (formato novo): guardada no aparelho, nunca enviada.
  final _parked = <String, Object?>{};

  StreamSubscription<List<NotebookPage>>? _sub;
  Timer? _debounceTimer;
  Timer? _maxWaitTimer;
  Timer? _persistTimer;
  Timer? _retryTimer;
  Timer? _streamTimer;
  late Duration _retryDelay = retryBase;
  late Duration _streamDelay = retryBase;
  Future<void>? _inFlight;
  Future<void> _storeChain = Future.value();
  bool _again = false;
  bool _started = false;
  bool _loaded = false;
  bool _disposed = false;
  bool _hasEmitted = false;
  bool _pendingFlag = false;
  bool _noteGone = false;
  bool _needReread = false;
  bool _trustEmpty = false;
  bool _rereading = false;
  String _cacheSignature = '';
  final _cacheData = <String, String>{};
  final _settledWaiters = <Completer<void>>[];
  SaveStatus _status = SaveStatus.saved;

  final _pagesCtl = StreamController<List<NotebookPageState>>.broadcast();
  final _statusCtl = StreamController<SaveStatus>.broadcast();

  // ---- NotebookSession ------------------------------------------------------

  @override
  Stream<List<NotebookPageState>> get pages =>
      _ReplayStream<List<NotebookPageState>>(_pagesCtl.stream, () => _hasEmitted ? currentPages : null);

  @override
  SaveStatus get status => _status;

  @override
  Stream<SaveStatus> get statusChanges => _statusCtl.stream;

  @override
  NotebookImageStore get images => _images;

  /// Páginas como a tela as vê agora.
  List<NotebookPageState> get currentPages => [
        for (var i = 0; i < _pages.length; i++)
          NotebookPageState(
            id: _pages[i].id,
            idx: i,
            background: _pages[i].background,
            doc: _pages[i].doc,
            notice: _pages[i].notice,
          ),
      ];

  _Local? _byId(String id) {
    for (final l in _pages) {
      if (l.id == id) return l;
    }
    return null;
  }

  @override
  void updatePage(String id, PageDoc doc) {
    final l = _byId(id);
    if (_disposed || l == null || l.locked) return;
    l.doc = doc;
    l.dirty = true;
    l.gen++;
    _markPending();
    _schedulePersist();
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () => unawaited(flush()));
    // Escrita contínua nunca deixa o debounce vencer: este teto garante o envio.
    _maxWaitTimer ??= Timer(maxWait, () {
      _maxWaitTimer = null;
      unawaited(flush());
    });
  }

  @override
  void addPage({PageBackground background = PageBackground.lined}) {
    if (_disposed) return;
    final id = newId();
    _pages.add(_Local(id, background, PageDoc.empty, 0));
    _ops.add(_AddOp(id, background));
    _afterStructureChange();
  }

  @override
  void deletePage(String id) {
    final idx = _pages.indexWhere((l) => l.id == id);
    if (_disposed || idx < 0) return;
    final gone = _pages.removeAt(idx);
    _parked.remove(gone.id);
    _ops.add(_DelOp(gone.id));
    _afterStructureChange();
  }

  @override
  void duplicatePage(String id) {
    final idx = _pages.indexWhere((l) => l.id == id);
    if (_disposed || idx < 0) return;
    final src = _pages[idx];
    final newPageId = newId();
    final copy = _Local(newPageId, src.background, src.doc, 0, dirty: !src.doc.isEmpty && !src.locked)..gen = 1;
    _pages.insert(idx + 1, copy);
    _ops.add(_AddOp(newPageId, src.background));
    _afterStructureChange();
  }

  @override
  void setBackground(String id, PageBackground background) {
    final l = _byId(id);
    if (_disposed || l == null || l.background == background) return;
    l.background = background;
    _ops.removeWhere((o) => o is _BgOp && o.id == l.id && !identical(o, _ops.firstOrNull));
    _ops.add(_BgOp(l.id, background));
    _afterStructureChange();
  }

  void _afterStructureChange() {
    _markPending();
    _schedulePersist();
    _emitPages();
    unawaited(flush());
  }

  // ---- ciclo de vida ---------------------------------------------------------

  /// Começa a escutar o repositório e retoma o que ficou pendente no aparelho.
  /// Se há uma cópia local da lista de páginas, já mostra o caderno (abre offline).
  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    Map<String, Object?>? cache;
    try {
      _restored = await _pending.load(noteId);
    } catch (_) {}
    try {
      cache = await _pending.loadPagesCache(noteId);
    } catch (_) {}
    if (_disposed) return;
    if (cache != null) _initFromCache(cache);
    _subscribe();
  }

  /// Completa quando não resta nada a enviar (ou o caderno foi excluído/descartado).
  /// Só vale depois de o caderno ter sido carregado.
  Future<void> whenSettled() {
    if (_isSettled) return Future.value();
    final c = Completer<void>();
    _settledWaiters.add(c);
    return c.future;
  }

  bool get _isSettled => _disposed || _noteGone || (_loaded && !_needsSendAny && _inFlight == null);

  void _checkSettled() {
    if (!_isSettled) return;
    for (final c in _settledWaiters) {
      if (!c.isCompleted) c.complete();
    }
    _settledWaiters.clear();
  }

  void _subscribe() {
    _sub?.cancel();
    _sub = _repo.watchPages(noteId).listen(
          _onRemote,
          onError: (Object _) => _onStreamDown(),
          onDone: _onStreamDown,
          cancelOnError: true,
        );
  }

  /// A consulta inicial falhou ou o realtime caiu: a biblioteca fecha o stream e ele
  /// não volta sozinho. Assina de novo com espera crescente.
  void _onStreamDown() {
    if (_disposed) return;
    _sub = null;
    if (!_noteGone) _setStatus(SaveStatus.offline);
    if (_streamTimer != null) return;
    final delay = _streamDelay;
    _streamDelay = _streamDelay * 2 > retryMax ? retryMax : _streamDelay * 2;
    _streamTimer = Timer(delay, () {
      _streamTimer = null;
      if (!_disposed) _subscribe();
    });
  }

  /// Salva agora tudo o que está pendente (ao sair da tela, pausar o app ou no
  /// botão "tentar de novo"). Várias chamadas seguidas se juntam numa só. A cópia
  /// local é gravada **antes** de qualquer chamada de rede.
  Future<void> flush() {
    if (_disposed || !_loaded) return Future.value();
    _debounceTimer?.cancel();
    _maxWaitTimer?.cancel();
    _maxWaitTimer = null;
    _persistTimer?.cancel();
    _persistTimer = null;
    final running = _inFlight;
    if (running != null) {
      _again = true;
      return running;
    }
    return _inFlight = _runFlush().whenComplete(() {
      _inFlight = null;
      _checkSettled();
    });
  }

  void dispose() {
    if (_disposed) return;
    final holds = _loaded && (_ops.isNotEmpty || _parked.isNotEmpty || _pages.any((l) => l.holdsInk));
    _disposed = true;
    _debounceTimer?.cancel();
    _maxWaitTimer?.cancel();
    _persistTimer?.cancel();
    _retryTimer?.cancel();
    _streamTimer?.cancel();
    _sub?.cancel();
    if (holds && !_noteGone) unawaited(_persist());
    for (final c in _settledWaiters) {
      if (!c.isCompleted) c.complete();
    }
    _settledWaiters.clear();
    _pagesCtl.close();
    _statusCtl.close();
  }

  // ---- recebimento do repositório -------------------------------------------

  void _initFromCache(Map<String, Object?> cache) {
    final list = (cache['pages'] as List?) ?? const [];
    final pages = <_Local>[];
    for (final raw in list) {
      final m = (raw as Map).cast<String, Object?>();
      final id = m['id'] as String;
      final data = m['data'] as String? ?? '';
      final version = (m['ver'] as num?)?.toInt() ?? 0;
      final bg = parsePageBackground(m['bg']);
      _cacheData[id] = data;
      pages.add(_decodeLocal(id, bg, data, version));
    }
    if (pages.isEmpty) return;
    _pages = pages;
    _loaded = true;
    _applyRestored();
    _emitPages();
    if (_needsSendAny) {
      _markPending();
      unawaited(flush());
    } else {
      _checkSettled();
    }
  }

  void _onRemote(List<NotebookPage> remote) {
    if (_disposed || _noteGone) return;
    _streamDelay = retryBase;
    _lastRemote = remote;
    _remoteKnown = true;
    _writeCache(remote);
    if (!_loaded) {
      _loaded = true;
      _pages = [for (final r in remote) _fromRemote(r)];
      _applyRestored();
      _ensureOnePage();
      _emitPages();
      if (_needsSendAny) {
        _markPending();
        unawaited(flush());
      } else {
        _recoverStatus();
        _checkSettled();
      }
      _rereadIfNeeded();
      return;
    }
    if (_reconcile(remote)) _emitPages();
    _ensureOnePage();
    _rereadIfNeeded();
    if (_needsSendAny) {
      if (_status == SaveStatus.offline) unawaited(flush());
    } else {
      _recoverStatus();
    }
  }

  /// A rede (stream) voltou e não há nada a enviar: deixa de mostrar "offline".
  void _recoverStatus() {
    if (_status == SaveStatus.offline && !_noteGone && _inFlight == null) _setStatus(_idleStatus());
  }

  SaveStatus _idleStatus() => _pages.any((l) => l.tooLarge) ? SaveStatus.problem : SaveStatus.saved;

  /// Caderno sem páginas (ex.: criado fora do app): começa com uma.
  void _ensureOnePage() {
    if (_pages.isNotEmpty || _ops.isNotEmpty || !_loaded) return;
    final id = newId();
    _pages.add(_Local(id, PageBackground.lined, PageDoc.empty, 0));
    _ops.add(_AddOp(id, PageBackground.lined));
    _emitPages();
  }

  /// Página que veio do servidor (leitura inicial, cache ou página nova de outro aparelho).
  _Local _fromRemote(NotebookPage r) {
    if (r.data.isEmpty && r.version > 0 && !_trustEmpty) {
      // O realtime omitiu o `data` (linha grande): mostra vazia, versão 0 (qualquer
      // save conflita e mescla com o servidor em vez de sobrescrever) e relê a linha.
      _needReread = true;
      return _Local(r.id, r.background, PageDoc.empty, 0);
    }
    final l = _decodeLocal(r.id, r.background, r.data, r.version);
    l.nearLimit = r.data.length > pageWarnLength;
    return l;
  }

  _Local _decodeLocal(String id, PageBackground bg, String data, int version) {
    try {
      return _Local(id, bg, decodePage(data), version);
    } on PageDecodeException catch (e) {
      debugPrint('Caderno: página $id ilegível (${e.message}); ficará só para leitura.');
      return _Local(id, bg, PageDoc.empty, version, locked: true);
    }
  }

  /// Trava a página (formato que este app não entende): só leitura, nunca regravada.
  /// A tinta que ela tinha por enviar fica guardada no aparelho.
  void _lock(_Local l) {
    if (l.locked) return;
    if (l.dirty) {
      _parked[l.id] = {'data': encodePage(l.doc), 'version': l.version, 'bg': l.background.name};
    }
    l.locked = true;
    l.dirty = false;
    l.tooLarge = false;
  }

  /// Mescla o conteúdo de [r] em [l]. Devolve true se o que se vê mudou.
  bool _mergeRemoteContent(_Local l, NotebookPage r) {
    if (l.locked) {
      l.seenVersion = r.version;
      return false;
    }
    if (r.data.isEmpty && r.version > 0 && !_trustEmpty) {
      // Dado omitido (linha grande demais para o realtime): não dá para mesclar nem
      // adotar a versão; relê a linha completa.
      _needReread = true;
      return false;
    }
    try {
      final merged = l.doc.merge(decodePage(r.data));
      l.seenVersion = r.version;
      l.nearLimit = r.data.length > pageWarnLength;
      if (merged != l.doc) {
        l.doc = merged;
        return true;
      }
    } on PageDecodeException catch (e) {
      debugPrint('Caderno: página ${l.id} ilegível (${e.message}); ficará só para leitura.');
      _lock(l);
      return true;
    }
    return false;
  }

  /// Mescla o que veio do servidor ao estado local. Devolve true se algo visível mudou.
  bool _reconcile(List<NotebookPage> remote) {
    final byId = {for (final r in remote) r.id: r};
    // O que o servidor já mostra deixa de ser "ainda não confirmado".
    _deletedUnconfirmed.removeWhere((id) => !byId.containsKey(id));
    _createdUnconfirmed.removeWhere(byId.containsKey);
    _bgUnconfirmed.removeWhere((id, bg) => byId[id]?.background == bg);

    var changed = false;
    for (final l in _pages) {
      final r = byId[l.id];
      if (r == null) continue;
      if (r.version > l.seenVersion && _mergeRemoteContent(l, r)) changed = true;
      final bgPending = _bgUnconfirmed.containsKey(l.id) || _ops.any((o) => o is _BgOp && o.id == l.id);
      if (!bgPending && l.background != r.background) {
        l.background = r.background;
        changed = true;
      }
    }
    // Com operações de estrutura pendentes a nossa ordem manda; o resto só depois.
    if (_ops.isEmpty) {
      final known = {for (final l in _pages) l.id: l};
      final next = <_Local>[
        for (final r in remote)
          if (!_deletedUnconfirmed.contains(r.id)) known[r.id] ?? _fromRemote(r),
      ];
      // Páginas só nossas: criadas aqui e que o realtime ainda não mostrou, ou com tinta
      // nova (apagadas em outro aparelho: serão recriadas ao salvar).
      for (var i = 0; i < _pages.length; i++) {
        final l = _pages[i];
        if (byId.containsKey(l.id)) continue;
        if (l.dirty || _createdUnconfirmed.contains(l.id)) next.insert(math.min(i, next.length), l);
      }
      final sameShape = next.length == _pages.length && [for (var i = 0; i < next.length; i++) next[i].id == _pages[i].id].every((e) => e);
      if (!sameShape) changed = true;
      _pages = next;
    }
    return changed;
  }

  void _rereadIfNeeded() {
    if (!_needReread || _rereading || _disposed) return;
    _needReread = false;
    _rereading = true;
    unawaited(_reread());
  }

  /// O realtime omitiu o dado de uma linha grande: lê as linhas completas e mescla.
  Future<void> _reread() async {
    try {
      final full = await _repo.listPages(noteId);
      if (_disposed) return;
      _trustEmpty = true; // linha completa: dado vazio agora é vazio de verdade
      try {
        _lastRemote = full;
        if (_reconcile(full)) _emitPages();
      } finally {
        _trustEmpty = false;
      }
    } catch (_) {
      // Sem rede agora: o próximo evento do realtime tenta de novo.
    } finally {
      _rereading = false;
    }
    _needReread = false;
  }

  void _emitPages() {
    if (_disposed) return;
    _hasEmitted = true;
    _pagesCtl.add(currentPages);
  }

  // ---- gravação ---------------------------------------------------------------

  bool get _needsSendAny => !_noteGone && (_ops.isNotEmpty || _pages.any((l) => l.needsSend));

  Future<void> _runFlush() async {
    await _persist();
    do {
      _again = false;
      if (!await _flushOnce()) return;
    } while (!_disposed && !_noteGone && (_again || _needsSendAny));
    if (_disposed || _noteGone) return;
    _retryTimer?.cancel();
    _retryDelay = retryBase;
    // Tudo o que dava para enviar foi confirmado: a fila local fica só com o que o
    // servidor recusou de forma permanente (ou não entendemos), se houver.
    await _persist();
    _notifyPending(false);
    _setStatus(_idleStatus());
  }

  /// Uma passada: primeiro a fila de estrutura, depois a tinta das páginas sujas.
  /// Devolve false se falhou (e já cuidou de ficar offline).
  Future<bool> _flushOnce() async {
    try {
      while (_ops.isNotEmpty && !_disposed && !_noteGone) {
        final op = _ops.first;
        try {
          switch (op) {
            case _AddOp():
              final at = _pages.indexWhere((l) => l.id == op.id);
              await _repo.addPage(noteId, id: op.id, background: op.background, at: at < 0 ? null : at);
              _createdUnconfirmed.add(op.id);
            case _DelOp():
              await _repo.deletePage(op.id);
              _createdUnconfirmed.remove(op.id);
              _bgUnconfirmed.remove(op.id);
              _deletedUnconfirmed.add(op.id);
            case _BgOp():
              await _repo.setBackground(op.id, op.background);
              _bgUnconfirmed[op.id] = op.background;
          }
        } on NotebookRepositoryException catch (e) {
          if (e.kind == NotebookErrorKind.transient) rethrow;
          _onNoteGone(); // criar/apagar/trocar fundo recusado de forma permanente
          return true;
        }
        _ops.remove(op);
      }
      if (_noteGone) return true;
      if (_ops.isEmpty && _remoteKnown && _reconcile(_lastRemote)) _emitPages();
      _rereadIfNeeded();
      for (final l in List.of(_pages)) {
        if (_disposed || _noteGone) return true;
        if (!l.needsSend || !_pages.contains(l)) continue;
        final gen = l.gen;
        final sent = encodePage(l.doc);
        final before = l.notice;
        if (sent.length > pageMaxLength) {
          // Nem adianta enviar: o servidor recusaria.
          l.tooLarge = true;
          l.rejectedGen = gen;
          _emitPages();
          continue;
        }
        final NotebookPage saved;
        try {
          saved = await _repo.savePage(NotebookPage(
            id: l.id,
            noteId: noteId,
            idx: _pages.indexOf(l),
            background: l.background,
            data: sent,
            version: l.version,
          ));
        } on NotebookRepositoryException catch (e) {
          switch (e.kind) {
            case NotebookErrorKind.transient:
              rethrow;
            case NotebookErrorKind.pageTooLarge:
              l.tooLarge = true;
              l.rejectedGen = gen;
              _emitPages();
              continue;
            case NotebookErrorKind.noteGone:
              _onNoteGone();
              return true;
            case NotebookErrorKind.newerFormat:
              _lock(l);
              _emitPages();
              continue;
          }
        }
        l.version = saved.version;
        var changed = false;
        if (saved.data != sent) {
          // Outro aparelho gravou no meio: o servidor devolveu o resultado mesclado.
          try {
            final merged = l.doc.merge(decodePage(saved.data));
            if (merged != l.doc) {
              l.doc = merged;
              changed = true;
            }
          } on PageDecodeException {
            _lock(l);
            _emitPages();
            continue;
          }
        }
        l.seenVersion = math.max(l.seenVersion, saved.version);
        l.tooLarge = false;
        l.nearLimit = math.max(sent.length, saved.data.length) > pageWarnLength;
        if (l.gen == gen) l.dirty = false;
        if (changed || l.notice != before) _emitPages();
      }
      return true;
    } catch (e) {
      if (_disposed) return false;
      await _goOffline();
      return false;
    }
  }

  /// O servidor diz que o caderno não existe mais (ou não é nosso): não há para onde
  /// enviar. Avisa e para de tentar; a fila local é descartada para não reenviar a cada abertura.
  void _onNoteGone() {
    if (_noteGone) return;
    _noteGone = true;
    _ops.clear();
    for (final l in _pages) {
      l.dirty = false;
    }
    _parked.clear();
    _retryTimer?.cancel();
    _streamTimer?.cancel();
    _debounceTimer?.cancel();
    _maxWaitTimer?.cancel();
    _maxWaitTimer = null;
    _persistTimer?.cancel();
    _persistTimer = null;
    unawaited(_store(() async {
      try {
        await _pending.clear(noteId);
        await _pending.clearPagesCache(noteId);
      } catch (_) {}
    }));
    _notifyPending(false);
    _setStatus(SaveStatus.noteDeleted);
    _emitPages();
    _checkSettled();
  }

  Future<void> _goOffline() async {
    _setStatus(SaveStatus.offline);
    _notifyPending(true);
    _scheduleRetry();
    await _persist();
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    final delay = _retryDelay;
    _retryDelay = _retryDelay * 2 > retryMax ? retryMax : _retryDelay * 2;
    _retryTimer = Timer(delay, () {
      if (!_disposed) unawaited(flush());
    });
  }

  void _markPending() {
    if (_noteGone) return;
    _notifyPending(true);
    if (_status != SaveStatus.offline) _setStatus(SaveStatus.saving);
  }

  void _notifyPending(bool pending) {
    if (_disposed || _pendingFlag == pending) return;
    _pendingFlag = pending;
    onPendingChanged?.call(pending);
  }

  void _setStatus(SaveStatus s) {
    if (_disposed || _status == s) return;
    _status = s;
    _statusCtl.add(s);
  }

  // ---- fila local (shared_preferences) ---------------------------------------

  /// Serializa as escritas no armazenamento local (a última sempre vence).
  Future<void> _store(Future<void> Function() job) {
    final next = _storeChain.then((_) => job());
    _storeChain = next.then((_) {}, onError: (_) {});
    return next;
  }

  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(persistDelay, () {
      _persistTimer = null;
      unawaited(_persist());
    });
  }

  Future<void> _persist() => _store(_persistNow);

  Future<void> _persistNow() async {
    // Antes da primeira leitura a fila guardada ainda não foi reaplicada: não mexer nela.
    if (!_loaded || _noteGone) return;
    final pages = <String, Object?>{};
    for (final l in _pages) {
      if (!l.holdsInk) continue;
      pages[l.id] = {'data': encodePage(l.doc), 'version': l.version, 'bg': l.background.name};
    }
    final ops = <Map<String, Object?>>[
      for (final o in _ops)
        switch (o) {
          _AddOp() => {'op': 'add', 'id': o.id, 'bg': o.background.name, 'at': _pages.indexWhere((l) => l.id == o.id)},
          _DelOp() => {'op': 'del', 'id': o.id},
          _BgOp() => {'op': 'bg', 'id': o.id, 'bg': o.background.name},
        },
    ];
    try {
      if (pages.isEmpty && ops.isEmpty && _parked.isEmpty) {
        await _pending.clear(noteId);
      } else {
        await _pending.save(noteId, {'v': 1, 'pages': pages, 'ops': ops, 'parked': _parked});
      }
    } catch (e) {
      debugPrint('Caderno: não foi possível guardar a fila local: $e');
    }
  }

  /// Aplica ao estado local o que ficou pendente numa sessão anterior (chamado uma vez,
  /// logo depois da primeira leitura do servidor ou do cache).
  void _applyRestored() {
    final r = _restored;
    _restored = null;
    if (r == null) return;
    for (final raw in (r['ops'] as List? ?? const [])) {
      final o = (raw as Map).cast<String, Object?>();
      final id = o['id'] as String;
      final bg = parsePageBackground(o['bg']);
      switch (o['op']) {
        case 'add':
          if (!_pages.any((l) => l.id == id)) {
            final at = ((o['at'] as num?)?.toInt() ?? _pages.length).clamp(0, _pages.length);
            _pages.insert(at, _Local(id, bg, PageDoc.empty, 0));
          }
          _ops.add(_AddOp(id, bg));
        case 'del':
          _pages.removeWhere((l) => l.id == id);
          _ops.add(_DelOp(id));
        case 'bg':
          for (final l in _pages) {
            if (l.id == id) l.background = bg;
          }
          _ops.add(_BgOp(id, bg));
      }
    }
    _parked.addAll((r['parked'] as Map?)?.cast<String, Object?>() ?? const {});
    final saved = (r['pages'] as Map?)?.cast<String, Object?>() ?? const {};
    for (final e in saved.entries) {
      final m = (e.value as Map).cast<String, Object?>();
      PageDoc doc;
      try {
        doc = decodePage(m['data'] as String? ?? '');
      } on PageDecodeException {
        continue;
      }
      final local = _pages.where((l) => l.id == e.key).firstOrNull;
      if (local != null) {
        if (local.locked) {
          // Página que não entendemos: a tinta guardada fica guardada, sem ser enviada.
          _parked[e.key] = m;
          continue;
        }
        local.doc = local.doc.merge(doc);
        local.dirty = true;
        local.gen++;
      } else {
        // Página que o servidor não tem mais: recria no fim com a tinta guardada.
        _pages.add(_Local(e.key, parsePageBackground(m['bg']), doc, (m['version'] as num?)?.toInt() ?? 0, dirty: true)..gen = 1);
      }
    }
  }

  // ---- cache da lista de páginas ---------------------------------------------

  /// Guarda a última lista de páginas do servidor, para abrir e escrever offline.
  void _writeCache(List<NotebookPage> remote) {
    final live = [for (final r in remote) if (!_deletedUnconfirmed.contains(r.id)) r];
    final sig = [for (final r in live) '${r.id}:${r.version}:${r.background.name}:${r.data.length}'].join('|');
    if (sig == _cacheSignature) return;
    _cacheSignature = sig;
    final entries = <Map<String, Object?>>[];
    for (final r in live) {
      // Linha grande cujo dado o realtime omitiu: mantém o que já tínhamos guardado.
      var data = r.data;
      if (data.isEmpty && r.version > 0) {
        data = _cacheData[r.id] ?? '';
      } else {
        _cacheData[r.id] = data;
      }
      entries.add({'id': r.id, 'bg': r.background.name, 'data': data, 'ver': r.version});
    }
    unawaited(_store(() async {
      if (_noteGone) return;
      try {
        await _pending.savePagesCache(noteId, {'v': 1, 'pages': entries});
      } catch (e) {
        debugPrint('Caderno: não foi possível guardar o cache das páginas: $e');
      }
    }));
  }
}
