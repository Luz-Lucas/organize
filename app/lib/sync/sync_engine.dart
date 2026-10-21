import 'dart:async';

import 'local_store.dart';
import 'remote_source.dart';

/// Uma alteração que o servidor recusou de vez (e que por isso saiu da fila).
class SyncRejection {
  const SyncRejection({required this.tbl, required this.id, required this.message});

  final String tbl;
  final String id;
  final String message;

  @override
  bool operator ==(Object other) =>
      other is SyncRejection && other.tbl == tbl && other.id == id && other.message == message;

  @override
  int get hashCode => Object.hash(tbl, id, message);

  @override
  String toString() => 'SyncRejection($tbl/$id: $message)';
}

class SyncState {
  const SyncState({required this.pending, required this.online, required this.lastError});

  /// Alterações aguardando envio.
  final int pending;

  /// `false` depois de uma falha de rede, até a próxima chamada que funcione.
  final bool online;
  final String? lastError;

  @override
  bool operator ==(Object other) =>
      other is SyncState && other.pending == pending && other.online == online && other.lastError == lastError;

  @override
  int get hashCode => Object.hash(pending, online, lastError);

  @override
  String toString() => 'SyncState(pending: $pending, online: $online, lastError: $lastError)';
}

/// Leva a fila do [LocalStore] para a nuvem e traz de volta o que mudou lá.
class SyncEngine {
  SyncEngine(
    this.store,
    this.remote, {
    required List<String> tables,
    List<String> readOnly = const [],
    DateTime Function()? now,
    Duration Function(int failures)? retryDelay,
    this.autoFlush = true,
    this.flushDelay = const Duration(milliseconds: 250),
    this.flushInterval = const Duration(seconds: 30),
    this.refreshInterval = const Duration(minutes: 5),
  })  : _tables = {...tables, ...readOnly}.toList(),
        _readOnly = readOnly.toSet(),
        _now = now ?? DateTime.now,
        _retryDelay = retryDelay ?? defaultRetryDelay;

  final LocalStore store;
  final RemoteSource remote;

  /// Envia sozinho depois de cada escrita local (com [flushDelay] para juntar escritas seguidas).
  final bool autoFlush;
  final Duration flushDelay;

  /// De quanto em quanto tempo reenvia a fila / recarrega tudo (`null` desliga).
  final Duration? flushInterval;
  final Duration? refreshInterval;

  final List<String> _tables;
  final Set<String> _readOnly;
  final DateTime Function() _now;
  final Duration Function(int failures) _retryDelay;

  /// Espera entre novas tentativas depois de [failures] falhas seguidas: 1 s, 2 s, 4 s … até 60 s.
  static Duration defaultRetryDelay(int failures) {
    if (failures <= 1) return const Duration(seconds: 1);
    final seconds = 1 << (failures - 1 > 6 ? 6 : failures - 1);
    return Duration(seconds: seconds > 60 ? 60 : seconds);
  }

  static const _groupLimit = 100;

  final _rejections = StreamController<SyncRejection>.broadcast();
  final _stateChanges = StreamController<SyncState>.broadcast();
  final _subs = <StreamSubscription<Object?>>[];
  Timer? _flushTimer;
  Timer? _retryTimer;
  Timer? _flushInterval;
  Timer? _refreshInterval;

  bool _started = false;
  bool _disposed = false;
  bool _online = true;
  String? _lastError;
  int _failures = 0;
  bool _needsRefresh = false;
  Future<void>? _flushing;
  bool _flushAgain = false;
  Future<void>? _refreshing;
  SyncState? _lastEmitted;

  Stream<SyncRejection> get rejections => _rejections.stream;

  SyncState get currentState => SyncState(pending: _pendingNow(), online: _online, lastError: _lastError);

  int _pendingNow() {
    try {
      return store.pendingNow;
    } on Object {
      return 0; // banco já fechado
    }
  }

  /// Emite o estado atual ao assinar e a cada mudança.
  Stream<SyncState> get state => Stream<SyncState>.multi((c) {
        c.add(currentState);
        final sub = _stateChanges.stream.listen(c.add);
        c.onCancel = sub.cancel;
      });

  // ---------------------------------------------------------------- ciclo de vida

  /// Assina as mudanças em tempo real, carrega todas as tabelas e envia a fila.
  /// Não lança por falta de rede: fica offline e tenta de novo sozinho.
  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    _subs.add(store.watchPending().listen((_) => _emitState()));
    _subs.add(store.onLocalWrite.listen((_) => _scheduleFlush()));
    for (final tbl in _tables) {
      _subs.add(remote.changes(tbl).listen(
            (change) => _onRemoteChange(tbl, change),
            onError: (Object e) => _onChannelError(),
          ));
    }
    final fi = flushInterval;
    if (fi != null) {
      _flushInterval = Timer.periodic(fi, (_) {
        if (store.pendingNow > 0 && _retryTimer == null) unawaited(flush());
      });
    }
    final ri = refreshInterval;
    if (ri != null) {
      _refreshInterval = Timer.periodic(ri, (_) => unawaited(refresh()));
    }
    await refresh();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _flushTimer?.cancel();
    _retryTimer?.cancel();
    _flushInterval?.cancel();
    _refreshInterval?.cancel();
    _flushTimer = _retryTimer = _flushInterval = _refreshInterval = null;
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    try {
      await _flushing;
    } catch (_) {}
    try {
      await _refreshing;
    } catch (_) {}
    await _rejections.close();
    await _stateChanges.close();
  }

  // ---------------------------------------------------------------- envio

  /// Envia a fila, em ordem. Nunca lança: falha de rede deixa tudo na fila e agenda nova tentativa.
  Future<void> flush() {
    if (_disposed) return Future.value();
    final running = _flushing;
    if (running != null) {
      _flushAgain = true;
      return running;
    }
    return _flushing = _flushLoop().whenComplete(() => _flushing = null);
  }

  Future<void> _flushLoop() async {
    var ok = true;
    do {
      _flushAgain = false;
      ok = await _flushOnce();
    } while (_flushAgain && ok && !_disposed);
  }

  /// Devolve `false` se parou por falha transitória (nova tentativa já agendada).
  Future<bool> _flushOnce() async {
    final isolated = <int>{};
    final announced = <SyncRejection>{};
    final cloudRows = <String, List<Map<String, dynamic>>>{};
    while (!_disposed) {
      final queue = store.pendingOutbox();
      if (queue.isEmpty) {
        _succeeded();
        return true;
      }
      final skip = queue.where((e) => _readOnly.contains(e.tbl)).toList();
      if (skip.isNotEmpty) {
        store.dropOutbox(skip);
        continue;
      }
      final group = _firstGroup(queue, isolated);
      try {
        await _send(group);
      } on PermanentSyncError catch (e) {
        if (group.length > 1) {
          // O servidor recusa o lote inteiro: reenvia um a um para achar quem foi.
          isolated.addAll(group.map((g) => g.seq));
        } else {
          await _reject(group.single, e.message, announced, cloudRows);
        }
        continue;
      } on Object catch (e) {
        final message = e is SyncError ? e.message : e.toString();
        if (!_disposed) store.markOutboxFailed(group, message);
        _failed(message);
        return false;
      }
      if (_disposed) return true; // fechou durante o envio: sem ack, o reenvio é idempotente
      store.ackOutbox(group);
      _succeeded();
    }
    return true;
  }

  List<OutboxEntry> _firstGroup(List<OutboxEntry> queue, Set<int> isolated) {
    final first = queue.first;
    if (isolated.contains(first.seq)) return [first];
    final group = <OutboxEntry>[];
    final ids = <String>{};
    for (final e in queue) {
      if (group.length >= _groupLimit || e.tbl != first.tbl || e.op != first.op || isolated.contains(e.seq)) break;
      if (!ids.add(e.id)) break; // a mesma linha duas vezes no lote: a segunda vai no próximo
      group.add(e);
    }
    return group;
  }

  Future<void> _send(List<OutboxEntry> group) {
    final first = group.first;
    if (first.op == OutboxOp.upsert) {
      return remote.upsert(first.tbl, [for (final e in group) e.data!]);
    }
    return remote.delete(first.tbl, [for (final e in group) e.id]);
  }

  Future<void> _reject(
    OutboxEntry entry,
    String message,
    Set<SyncRejection> announced,
    Map<String, List<Map<String, dynamic>>> cloudRows,
  ) async {
    store.dropOutbox([entry]);
    final rejection = SyncRejection(tbl: entry.tbl, id: entry.id, message: message);
    if (announced.add(rejection) && !_rejections.isClosed) _rejections.add(rejection);
    // Desfaz a cópia local: volta ao que a nuvem tem.
    try {
      final rows = cloudRows[entry.tbl] ??= await remote.fetchAll(entry.tbl);
      final key = store.keyOf(entry.tbl);
      Map<String, dynamic>? cloud;
      for (final r in rows) {
        if (r[key]?.toString() == entry.id) {
          cloud = r;
          break;
        }
      }
      if (!_disposed) await store.restoreFromRemote(entry.tbl, entry.id, cloud);
    } on PermanentSyncError {
      // não deu para reler: a próxima carga completa corrige
    } on Object {
      _needsRefresh = true;
      _scheduleRetry();
    }
  }

  void _scheduleFlush() {
    if (!autoFlush || _disposed || _flushTimer != null) return;
    // Offline e com nova tentativa já marcada: esperar a espera crescente, não martelar a cada escrita.
    if (!_online && _retryTimer != null) return;
    _flushTimer = Timer(flushDelay, () {
      _flushTimer = null;
      unawaited(flush());
    });
  }

  // ---------------------------------------------------------------- recebimento

  /// Recarrega todas as tabelas da nuvem (ao reconectar, ao voltar ao app) e depois envia a fila.
  Future<void> refresh() {
    if (_disposed) return Future.value();
    return _refreshing ??= _refreshOnce().whenComplete(() => _refreshing = null);
  }

  Future<void> _refreshOnce() async {
    final started = _now();
    for (final tbl in _tables) {
      if (_disposed) return;
      try {
        final rows = await remote.fetchAll(tbl);
        if (_disposed) return;
        await store.applyRemoteSnapshot(tbl, rows, startedAt: started);
      } on PermanentSyncError catch (e) {
        _lastError = e.message; // tabela inacessível: segue com as outras
        _emitState();
      } on Object catch (e) {
        _needsRefresh = true;
        _failed(e is SyncError ? e.message : e.toString());
        return;
      }
    }
    _needsRefresh = false;
    _succeeded();
    await flush();
  }

  Future<void> _onRemoteChange(String tbl, RemoteChange change) async {
    if (_disposed) return;
    switch (change.type) {
      case RemoteChangeType.upsert:
        await store.applyRemoteUpsert(tbl, change.row);
      case RemoteChangeType.delete:
        final id = change.row[store.keyOf(tbl)]?.toString();
        if (id != null) await store.applyRemoteDelete(tbl, id);
    }
  }

  /// O canal de tempo real caiu: eventos podem ter se perdido, então recarrega tudo.
  void _onChannelError() {
    if (_disposed) return;
    _needsRefresh = true;
    _scheduleRetry();
  }

  // ---------------------------------------------------------------- estado e novas tentativas

  void _succeeded() {
    _failures = 0;
    _online = true;
    _lastError = null;
    if (!_needsRefresh) {
      _retryTimer?.cancel();
      _retryTimer = null;
    }
    _emitState();
  }

  void _failed(String message) {
    _failures++;
    _online = false;
    _lastError = message;
    _scheduleRetry();
    _emitState();
  }

  void _scheduleRetry() {
    if (_disposed || _retryTimer != null) return;
    _retryTimer = Timer(_retryDelay(_failures), () {
      _retryTimer = null;
      if (_disposed) return;
      unawaited(_needsRefresh ? refresh() : flush());
    });
  }

  void _emitState() {
    if (_stateChanges.isClosed) return;
    final s = currentState;
    if (s == _lastEmitted) return;
    _lastEmitted = s;
    _stateChanges.add(s);
  }
}
