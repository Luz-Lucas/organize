import 'dart:async';

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
  _Local(this.id, this.background, this.doc, this.version, {this.dirty = false, this.locked = false});

  final String id;
  PageBackground background;
  PageDoc doc;
  int version;
  bool dirty;

  /// Muda a cada edição; permite saber se houve edição durante uma gravação em voo.
  int gen = 0;

  /// Página em formato desconhecido (gravada por uma versão mais nova do app):
  /// mostrada vazia e nunca regravada, para não sobrescrever o que não entendemos.
  final bool locked;
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
/// página, salva sozinho 1,5 s depois do último gesto (e ao sair/pausar), mescla o
/// que chega de outros aparelhos e, sem conexão, guarda tudo no aparelho
/// (`shared_preferences`) e reenvia quando a rede volta.
///
/// Operações de estrutura (nova página, apagar, duplicar, fundo) valem na hora na
/// tela e entram numa fila de operações que o servidor recebe em ordem.
class NotebookController implements NotebookSession {
  NotebookController({
    required this.noteId,
    required this._repo,
    required this._images,
    required this._pending,
    this.debounce = const Duration(milliseconds: 1500),
    this.retryBase = const Duration(seconds: 5),
    this.retryMax = const Duration(seconds: 60),
    this.onPendingChanged,
  });

  final String noteId;
  final NotebookRepository _repo;
  final NotebookImageStore _images;
  final NotebookPendingStore _pending;
  final Duration debounce;
  final Duration retryBase;
  final Duration retryMax;

  /// Avisa quando passa a existir (true) ou deixa de existir (false) algo não confirmado
  /// no servidor. O provider usa para manter o controller vivo até terminar de salvar.
  final void Function(bool pending)? onPendingChanged;

  var _pages = <_Local>[];
  final _ops = <_Op>[];
  List<NotebookPage> _lastRemote = const [];
  Map<String, Object?>? _restored;
  StreamSubscription<List<NotebookPage>>? _sub;
  Timer? _debounceTimer;
  Timer? _retryTimer;
  late Duration _retryDelay = retryBase;
  Future<void>? _inFlight;
  bool _again = false;
  bool _started = false;
  bool _loaded = false;
  bool _disposed = false;
  bool _hasEmitted = false;
  bool _pendingFlag = false;
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
          NotebookPageState(idx: i, background: _pages[i].background, doc: _pages[i].doc),
      ];

  bool _valid(int idx) => idx >= 0 && idx < _pages.length;

  @override
  void updatePage(int idx, PageDoc doc) {
    if (_disposed || !_valid(idx) || _pages[idx].locked) return;
    final l = _pages[idx];
    l.doc = doc;
    l.dirty = true;
    l.gen++;
    _markPending();
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () => unawaited(flush()));
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
  void deletePage(int idx) {
    if (_disposed || !_valid(idx)) return;
    final gone = _pages.removeAt(idx);
    _ops.add(_DelOp(gone.id));
    _afterStructureChange();
  }

  @override
  void duplicatePage(int idx) {
    if (_disposed || !_valid(idx)) return;
    final src = _pages[idx];
    final id = newId();
    final copy = _Local(id, src.background, src.doc, 0, dirty: !src.doc.isEmpty)..gen = 1;
    _pages.insert(idx + 1, copy);
    _ops.add(_AddOp(id, src.background));
    _afterStructureChange();
  }

  @override
  void setBackground(int idx, PageBackground background) {
    if (_disposed || !_valid(idx) || _pages[idx].background == background) return;
    final l = _pages[idx];
    l.background = background;
    _ops.removeWhere((o) => o is _BgOp && o.id == l.id && !identical(o, _ops.firstOrNull));
    _ops.add(_BgOp(l.id, background));
    _afterStructureChange();
  }

  void _afterStructureChange() {
    _markPending();
    _emitPages();
    unawaited(flush());
  }

  // ---- ciclo de vida ---------------------------------------------------------

  /// Começa a escutar o repositório e retoma o que ficou pendente no aparelho.
  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    try {
      _restored = await _pending.load(noteId);
    } catch (_) {}
    if (_disposed) return;
    _subscribe();
  }

  void _subscribe() {
    _sub?.cancel();
    _sub = _repo.watchPages(noteId).listen(_onRemote, onError: (Object _) {
      if (_disposed) return;
      _setStatus(SaveStatus.offline);
      _scheduleRetry();
    });
  }

  /// Salva agora tudo o que está pendente (ao sair da tela, pausar o app ou no
  /// botão "tentar de novo"). Várias chamadas seguidas se juntam numa só.
  Future<void> flush() {
    if (_disposed) return Future.value();
    _debounceTimer?.cancel();
    final running = _inFlight;
    if (running != null) {
      _again = true;
      return running;
    }
    return _inFlight = _runFlush().whenComplete(() => _inFlight = null);
  }

  void dispose() {
    if (_disposed) return;
    final dirty = _hasUnsaved;
    _disposed = true;
    _debounceTimer?.cancel();
    _retryTimer?.cancel();
    _sub?.cancel();
    if (dirty) unawaited(_persist());
    _pagesCtl.close();
    _statusCtl.close();
  }

  // ---- recebimento do repositório -------------------------------------------

  void _onRemote(List<NotebookPage> remote) {
    if (_disposed) return;
    _lastRemote = remote;
    if (!_loaded) {
      _loaded = true;
      _pages = [for (final r in remote) _fromRemote(r)];
      _applyRestored();
      if (_pages.isEmpty && _ops.isEmpty) {
        // Caderno sem páginas (ex.: criado fora do app): começa com uma.
        final id = newId();
        _pages.add(_Local(id, PageBackground.lined, PageDoc.empty, 0));
        _ops.add(_AddOp(id, PageBackground.lined));
      }
      _emitPages();
      if (_hasUnsaved) {
        _markPending();
        unawaited(flush());
      }
      return;
    }
    if (_reconcile(remote)) _emitPages();
  }

  _Local _fromRemote(NotebookPage r) {
    try {
      return _Local(r.id, r.background, decodePage(r.data), r.version);
    } on PageDecodeException catch (e) {
      debugPrint('Caderno: página ${r.id} ilegível (${e.message}); ficará só para leitura.');
      return _Local(r.id, r.background, PageDoc.empty, r.version, locked: true);
    }
  }

  /// Mescla o que veio do servidor ao estado local. Devolve true se algo visível mudou.
  bool _reconcile(List<NotebookPage> remote) {
    final byId = {for (final r in remote) r.id: r};
    var changed = false;
    for (final l in _pages) {
      final r = byId[l.id];
      if (r == null) continue;
      if (r.version > l.version) {
        try {
          final merged = l.doc.merge(decodePage(r.data));
          if (!l.locked && merged != l.doc) {
            l.doc = merged;
            changed = true;
          }
        } on PageDecodeException {
          // Mantém o que temos.
        }
        l.version = r.version;
      }
      if (_ops.isEmpty && !l.dirty && l.background != r.background) {
        l.background = r.background;
        changed = true;
      }
    }
    // Com operações de estrutura pendentes a nossa ordem manda; o resto só depois.
    if (_ops.isEmpty) {
      final known = {for (final l in _pages) l.id: l};
      final next = <_Local>[
        for (final r in remote) known[r.id] ?? _fromRemote(r),
        // Página só nossa e com tinta nova (apagada em outro aparelho): será recriada ao salvar.
        for (final l in _pages)
          if (!byId.containsKey(l.id) && l.dirty) l,
      ];
      final sameShape = next.length == _pages.length && [for (var i = 0; i < next.length; i++) next[i].id == _pages[i].id].every((e) => e);
      if (!sameShape) changed = true;
      _pages = next;
    }
    return changed;
  }

  void _emitPages() {
    if (_disposed) return;
    _hasEmitted = true;
    _pagesCtl.add(currentPages);
  }

  // ---- gravação ---------------------------------------------------------------

  bool get _hasUnsaved => _ops.isNotEmpty || _pages.any((l) => l.dirty);

  Future<void> _runFlush() async {
    do {
      _again = false;
      if (!await _flushOnce()) return;
    } while (!_disposed && (_again || _hasUnsaved));
    if (_disposed) return;
    _retryTimer?.cancel();
    _retryDelay = retryBase;
    try {
      await _pending.clear(noteId);
    } catch (_) {}
    _notifyPending(false);
    _setStatus(SaveStatus.saved);
  }

  /// Uma passada: primeiro a fila de estrutura, depois a tinta das páginas sujas.
  /// Devolve false se falhou (e já cuidou de ficar offline).
  Future<bool> _flushOnce() async {
    try {
      while (_ops.isNotEmpty && !_disposed) {
        final op = _ops.first;
        switch (op) {
          case _AddOp():
            final at = _pages.indexWhere((l) => l.id == op.id);
            await _repo.addPage(noteId, id: op.id, background: op.background, at: at < 0 ? null : at);
          case _DelOp():
            await _repo.deletePage(op.id);
          case _BgOp():
            await _repo.setBackground(op.id, op.background);
        }
        _ops.remove(op);
      }
      if (_ops.isEmpty && _reconcile(_lastRemote)) _emitPages();
      for (final l in List.of(_pages)) {
        if (_disposed) return true;
        if (!l.dirty || l.locked || !_pages.contains(l)) continue;
        final gen = l.gen;
        final sent = encodePage(l.doc);
        final saved = await _repo.savePage(NotebookPage(
          id: l.id,
          noteId: noteId,
          idx: _pages.indexOf(l),
          background: l.background,
          data: sent,
          version: l.version,
        ));
        l.version = saved.version;
        if (saved.data != sent) {
          // Outro aparelho gravou no meio: o servidor devolveu o resultado mesclado.
          final merged = l.doc.merge(decodePage(saved.data));
          if (merged != l.doc) {
            l.doc = merged;
            _emitPages();
          }
        }
        if (l.gen == gen) l.dirty = false;
      }
      return true;
    } catch (e) {
      if (_disposed) return false;
      await _goOffline();
      return false;
    }
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

  Future<void> _persist() async {
    final pages = <String, Object?>{};
    for (final l in _pages) {
      if (!l.dirty || l.locked) continue;
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
      if (pages.isEmpty && ops.isEmpty) {
        await _pending.clear(noteId);
      } else {
        await _pending.save(noteId, {'v': 1, 'pages': pages, 'ops': ops});
      }
    } catch (e) {
      debugPrint('Caderno: não foi possível guardar a fila local: $e');
    }
  }

  /// Aplica ao estado local o que ficou pendente numa sessão anterior (chamado uma vez,
  /// logo depois da primeira leitura do servidor).
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
        local.doc = local.doc.merge(doc);
        local.dirty = true;
        local.gen++;
      } else {
        // Página que o servidor não tem mais: recria no fim com a tinta guardada.
        _pages.add(_Local(e.key, parsePageBackground(m['bg']), doc, (m['version'] as num?)?.toInt() ?? 0, dirty: true)..gen = 1);
      }
    }
  }
}
