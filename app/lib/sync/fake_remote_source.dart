import 'dart:async';

import 'local_store.dart';
import 'remote_source.dart';

/// Uma chamada que o sincronizador fez à nuvem falsa.
class FakeCall {
  const FakeCall(this.op, this.tbl, [this.ids = const []]);

  /// `fetch`, `upsert` ou `delete`.
  final String op;
  final String tbl;
  final List<String> ids;

  @override
  String toString() => '$op $tbl $ids';
}

/// Nuvem em memória para testes: guarda as linhas por tabela, aplica "o mais recente vence" como o
/// gatilho do banco, emite os eventos de tempo real e simula falha de rede e recusa definitiva.
class FakeRemoteSource implements RemoteSource {
  FakeRemoteSource({DateTime Function()? now, Map<String, String> keys = const {}})
      : _now = now ?? DateTime.now,
        _keys = {...defaultSyncKeys, ...keys};

  final DateTime Function() _now;
  final Map<String, String> _keys;
  final Map<String, Map<String, Map<String, dynamic>>> _tables = {};
  final Map<String, StreamController<RemoteChange>> _controllers = {};
  final List<FakeCall> calls = [];

  /// `false`: toda chamada falha com [TransientSyncError] (sem rede).
  bool online = true;

  /// `false`: o tempo real não entrega nada (simula eventos perdidos); a carga completa continua funcionando.
  bool realtime = true;

  /// Devolve uma mensagem para recusar de vez a gravação (`op` = `upsert`/`delete`); `null` aceita.
  /// Um lote com qualquer linha recusada é recusado inteiro, como uma instrução SQL.
  String? Function(String tbl, String op, Map<String, dynamic> row)? reject;

  int _failNext = 0;
  Completer<void>? _gate;

  /// As próximas [times] chamadas falham como erro transitório.
  void failNext([int times = 1]) => _failNext = times;

  /// Segura as chamadas (antes de aplicá-las) até [release].
  void hold() => _gate = Completer<void>();

  void release() {
    _gate?.complete();
    _gate = null;
  }

  String _keyOf(String tbl) => _keys[tbl] ?? 'id';

  Map<String, Map<String, dynamic>> _table(String tbl) => _tables.putIfAbsent(tbl, () => {});

  /// As linhas atuais da tabela na "nuvem".
  List<Map<String, dynamic>> rows(String tbl) => [for (final r in _table(tbl).values) {...r}];

  Map<String, dynamic>? row(String tbl, String id) {
    final r = _table(tbl)[id];
    return r == null ? null : {...r};
  }

  /// Escrita feita por outro aparelho/ponte/MCP: segue as mesmas regras do banco e dispara tempo real.
  void serverUpsert(String tbl, Map<String, dynamic> row) => _apply(tbl, row);

  void serverDelete(String tbl, String id) => _applyDelete(tbl, id);

  /// Entrega um erro no stream de tempo real da tabela (canal caiu).
  void failRealtime(String tbl) => _controller(tbl).addError(const TransientSyncError('tempo real caiu'));

  StreamController<RemoteChange> _controller(String tbl) =>
      _controllers.putIfAbsent(tbl, () => StreamController<RemoteChange>.broadcast());

  void _emit(String tbl, RemoteChange change) {
    if (realtime) _controller(tbl).add(change);
  }

  void _apply(String tbl, Map<String, dynamic> incoming) {
    final id = incoming[_keyOf(tbl)].toString();
    final table = _table(tbl);
    final existing = table[id];
    final incomingTs = parseSyncTimestamp(incoming[clientUpdatedAtColumn]);
    final existingTs = existing == null ? null : parseSyncTimestamp(existing[clientUpdatedAtColumn]);
    if (existing != null && incomingTs != null && existingTs != null && incomingTs.isBefore(existingTs)) {
      return; // gatilho `before update`: atualização mais velha é ignorada
    }
    final stored = {...?existing, ...incoming};
    // escrita sem o carimbo (ponte/MCP) vira "agora"
    if (incomingTs == null) stored[clientUpdatedAtColumn] = _now().toUtc().toIso8601String();
    table[id] = stored;
    _emit(tbl, RemoteChange(RemoteChangeType.upsert, {...stored}));
  }

  void _applyDelete(String tbl, String id) {
    if (_table(tbl).remove(id) != null) {
      _emit(tbl, RemoteChange(RemoteChangeType.delete, {_keyOf(tbl): id}));
    }
  }

  Future<void> _enter(String op, String tbl, List<String> ids) async {
    calls.add(FakeCall(op, tbl, ids));
    final gate = _gate;
    if (gate != null) await gate.future;
    if (!online) throw const TransientSyncError('sem rede');
    if (_failNext > 0) {
      _failNext--;
      throw const TransientSyncError('falha temporária');
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchAll(String tbl) async {
    await _enter('fetch', tbl, const []);
    return rows(tbl);
  }

  @override
  Future<void> upsert(String tbl, List<Map<String, dynamic>> rows) async {
    await _enter('upsert', tbl, [for (final r in rows) r[_keyOf(tbl)].toString()]);
    final check = reject;
    if (check != null) {
      for (final r in rows) {
        final message = check(tbl, 'upsert', r);
        if (message != null) throw PermanentSyncError(message);
      }
    }
    for (final r in rows) {
      _apply(tbl, {...r});
    }
  }

  @override
  Future<void> delete(String tbl, List<String> ids) async {
    await _enter('delete', tbl, ids);
    final check = reject;
    if (check != null) {
      for (final id in ids) {
        final message = check(tbl, 'delete', {_keyOf(tbl): id});
        if (message != null) throw PermanentSyncError(message);
      }
    }
    for (final id in ids) {
      _applyDelete(tbl, id);
    }
  }

  @override
  Stream<RemoteChange> changes(String tbl) => _controller(tbl).stream;

  Future<void> close() async {
    for (final c in _controllers.values) {
      await c.close();
    }
  }
}
