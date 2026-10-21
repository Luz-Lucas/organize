import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

/// Coluna que identifica a linha em cada tabela; as que não aparecem aqui usam `id`.
const defaultSyncKeys = <String, String>{'user_settings': 'user_id'};

/// Coluna carimbada em toda escrita local e usada pelo servidor para decidir "o mais recente vence".
const clientUpdatedAtColumn = 'client_updated_at';

enum OutboxOp { upsert, delete }

/// Um item da fila de envio (alteração local que a nuvem ainda não confirmou).
class OutboxEntry {
  const OutboxEntry({
    required this.seq,
    required this.rev,
    required this.tbl,
    required this.op,
    required this.id,
    required this.data,
    required this.clientUpdatedAt,
    required this.attempts,
    required this.lastError,
  });

  /// Ordem de envio (cresce a cada item novo).
  final int seq;

  /// Cresce quando uma edição seguinte é juntada a este item; `ackOutbox` só remove se não mudou.
  final int rev;
  final String tbl;
  final OutboxOp op;
  final String id;

  /// A linha a enviar (`upsert`); `null` no `delete`.
  final Map<String, dynamic>? data;
  final DateTime clientUpdatedAt;
  final int attempts;
  final String? lastError;
}

/// Interpreta o carimbo de uma linha (ISO com `Z` ou com offset do Postgres); `null` se faltar/for inválido.
DateTime? parseSyncTimestamp(Object? value) {
  if (value is DateTime) return value.toUtc();
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value)?.toUtc();
}

/// Cópia local (SQLite) das tabelas da conta logada + a fila de alterações ainda não enviadas.
///
/// Toda a escrita da tela passa por aqui e é imediata; quem fala com a nuvem é o `SyncEngine`.
class LocalStore {
  LocalStore._(this._db, this._now, Map<String, String> keys) : _keys = {...defaultSyncKeys, ...keys} {
    _init();
  }

  static Future<LocalStore> open(
    String path, {
    DateTime Function()? now,
    Map<String, String> keys = const {},
  }) async {
    await File(path).parent.create(recursive: true);
    final db = sqlite3.open(path);
    try {
      db.execute('PRAGMA journal_mode = WAL');
      db.execute('PRAGMA busy_timeout = 5000');
    } catch (_) {
      db.close();
      rethrow;
    }
    return LocalStore._(db, now ?? DateTime.now, keys);
  }

  factory LocalStore.inMemory({DateTime Function()? now, Map<String, String> keys = const {}}) =>
      LocalStore._(sqlite3.openInMemory(), now ?? DateTime.now, keys);

  final Database _db;
  final DateTime Function() _now;
  final Map<String, String> _keys;
  bool _closed = false;

  final _watchers = <String, Set<_TableWatcher>>{};
  final _pendingWatchers = <_PendingWatcher>{};
  final _dirty = <String>{};
  bool _dirtyAll = false;
  bool _notifyScheduled = false;
  final _localWrites = StreamController<void>.broadcast(sync: true);

  void _init() {
    final version = _db.select('PRAGMA user_version').first.values.first as int;
    if (version < 1) {
      _db.execute('''
        CREATE TABLE rows (
          tbl TEXT NOT NULL,
          id TEXT NOT NULL,
          data_json TEXT NOT NULL,
          client_updated_at TEXT,
          PRIMARY KEY (tbl, id)
        ) WITHOUT ROWID;
        CREATE TABLE outbox (
          seq INTEGER PRIMARY KEY AUTOINCREMENT,
          tbl TEXT NOT NULL,
          op TEXT NOT NULL,
          id TEXT NOT NULL,
          data_json TEXT,
          client_updated_at TEXT NOT NULL,
          attempts INTEGER NOT NULL DEFAULT 0,
          last_error TEXT,
          rev INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX outbox_row ON outbox (tbl, id);
        PRAGMA user_version = 1;
      ''');
    }
  }

  /// Coluna-chave da tabela.
  String keyOf(String tbl) => _keys[tbl] ?? 'id';

  /// Dispara a cada escrita local (put/remove) — o sincronizador usa para enviar logo.
  Stream<void> get onLocalWrite => _localWrites.stream;

  // ---------------------------------------------------------------- leitura

  Stream<List<Map<String, dynamic>>> watch(String tbl) {
    late final StreamController<List<Map<String, dynamic>>> controller;
    late final _TableWatcher watcher;
    controller = StreamController<List<Map<String, dynamic>>>(
      onListen: () {
        watcher = _TableWatcher(controller);
        (_watchers[tbl] ??= {}).add(watcher);
        if (!_closed) controller.add(_readAll(tbl));
      },
      onCancel: () {
        _watchers[tbl]?.remove(watcher);
      },
    );
    return controller.stream;
  }

  Future<List<Map<String, dynamic>>> all(String tbl) async => _readAll(tbl);

  Future<Map<String, dynamic>?> get(String tbl, String id) async => _readOne(tbl, id);

  Stream<int> watchPending() {
    late final StreamController<int> controller;
    late final _PendingWatcher watcher;
    controller = StreamController<int>(
      onListen: () {
        watcher = _PendingWatcher(controller);
        _pendingWatchers.add(watcher);
        if (!_closed) {
          watcher.last = pendingNow;
          controller.add(watcher.last!);
        }
      },
      onCancel: () => _pendingWatchers.remove(watcher),
    );
    return controller.stream;
  }

  /// Quantos itens aguardam envio.
  int get pendingNow => _db.select('SELECT COUNT(*) AS n FROM outbox').first['n'] as int;

  List<Map<String, dynamic>> _readAll(String tbl) {
    if (_closed) return const [];
    return [
      for (final r in _db.select('SELECT data_json FROM rows WHERE tbl = ?', [tbl]))
        _decode(r['data_json'] as String),
    ];
  }

  Map<String, dynamic>? _readOne(String tbl, String id) {
    final r = _db.select('SELECT data_json FROM rows WHERE tbl = ? AND id = ?', [tbl, id]);
    return r.isEmpty ? null : _decode(r.first['data_json'] as String);
  }

  // ---------------------------------------------------------------- escrita local

  Future<void> put(String tbl, Map<String, dynamic> row) => putMany(tbl, [row]);

  /// Grava as linhas localmente (mesclando sobre a que já existe, para manter campos que só o servidor
  /// preenche, como `created_at`) e enfileira o envio. Carimba `client_updated_at` com o relógio.
  Future<void> putMany(String tbl, List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    final key = keyOf(tbl);
    final ids = [
      for (final row in rows)
        row[key]?.toString() ?? (throw ArgumentError('A linha de "$tbl" precisa de "$key": $row')),
    ];
    _txn(() {
      final now = _now().toUtc();
      for (var i = 0; i < rows.length; i++) {
        final id = ids[i];
        final existing = _db.select(
          'SELECT data_json, client_updated_at FROM rows WHERE tbl = ? AND id = ?',
          [tbl, id],
        );
        var stamp = now;
        Map<String, dynamic>? existingData;
        if (existing.isNotEmpty) {
          existingData = _decode(existing.first['data_json'] as String);
          final previous = parseSyncTimestamp(existing.first['client_updated_at']);
          // Cada alteração da linha tem de ser mais nova que a anterior, mesmo com relógio parado ou atrasado.
          if (previous != null && !stamp.isAfter(previous)) stamp = previous.add(const Duration(microseconds: 1));
        }
        final iso = stamp.toIso8601String();
        final sent = {...rows[i], clientUpdatedAtColumn: iso};
        _writeRow(tbl, id, {...?existingData, ...sent}, iso);
        _enqueueUpsert(tbl, id, sent, iso);
      }
    });
    _touch(tbl);
    _localWrites.add(null);
  }

  Future<void> remove(String tbl, String id) => removeMany(tbl, [id]);

  /// Apaga localmente e enfileira o `delete` (descartando upserts pendentes dessas linhas).
  Future<void> removeMany(String tbl, List<String> ids) async {
    if (ids.isEmpty) return;
    _txn(() {
      final iso = _now().toUtc().toIso8601String();
      for (final id in ids) {
        _db.execute('DELETE FROM rows WHERE tbl = ? AND id = ?', [tbl, id]);
        _db.execute("DELETE FROM outbox WHERE tbl = ? AND id = ? AND op = 'upsert'", [tbl, id]);
        final last = _lastOutbox();
        if (last != null && last.op == OutboxOp.delete && last.tbl == tbl && last.id == id) continue;
        _db.execute(
          "INSERT INTO outbox (tbl, op, id, client_updated_at) VALUES (?, 'delete', ?, ?)",
          [tbl, id, iso],
        );
      }
    });
    _touch(tbl);
    _localWrites.add(null);
  }

  /// Apaga tudo (linhas e fila). Ao sair da conta.
  Future<void> wipe() async {
    _txn(() {
      _db.execute('DELETE FROM rows');
      _db.execute('DELETE FROM outbox');
    });
    _touch(null);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final set in _watchers.values) {
      for (final w in set.toList()) {
        await w.controller.close();
      }
    }
    _watchers.clear();
    for (final w in _pendingWatchers.toList()) {
      await w.controller.close();
    }
    _pendingWatchers.clear();
    await _localWrites.close();
    _db.close();
  }

  // ---------------------------------------------------------------- fila (uso do sincronizador)

  /// Os itens mais antigos da fila, em ordem de envio.
  List<OutboxEntry> pendingOutbox({int limit = 500}) => [
        for (final r in _db.select('SELECT * FROM outbox ORDER BY seq LIMIT ?', [limit])) _entry(r),
      ];

  /// Remove os itens enviados — exceto os que receberam uma edição enquanto eram enviados (`rev` mudou).
  void ackOutbox(List<OutboxEntry> entries) {
    _txn(() {
      for (final e in entries) {
        _db.execute('DELETE FROM outbox WHERE seq = ? AND rev = ?', [e.seq, e.rev]);
      }
    });
    _touchPending();
  }

  /// Tira os itens da fila de qualquer jeito (recusados pelo servidor, tabela só de leitura).
  void dropOutbox(List<OutboxEntry> entries) {
    _txn(() {
      for (final e in entries) {
        _db.execute('DELETE FROM outbox WHERE seq = ?', [e.seq]);
      }
    });
    _touchPending();
  }

  void markOutboxFailed(List<OutboxEntry> entries, String error) {
    _txn(() {
      for (final e in entries) {
        _db.execute('UPDATE outbox SET attempts = attempts + 1, last_error = ? WHERE seq = ?', [error, e.seq]);
      }
    });
  }

  // ---------------------------------------------------------------- dados remotos (uso do sincronizador)

  /// Aplica uma linha recebida em tempo real. Não gera fila. Devolve se a cópia local mudou.
  ///
  /// Não substitui se há apagamento pendente da linha, ou upsert pendente igual/mais novo, ou se a
  /// cópia local já é mais nova (eco atrasado). Se o remoto é mais novo que o pendente, ele vence e a
  /// pendência é descartada (o servidor a ignoraria mesmo).
  Future<bool> applyRemoteUpsert(String tbl, Map<String, dynamic> row) async {
    final id = row[keyOf(tbl)]?.toString();
    if (id == null) return false;
    final remoteTs = parseSyncTimestamp(row[clientUpdatedAtColumn]);
    var applied = false;
    _txn(() {
      final pending = _pendingFor(tbl, id);
      if (pending.hasDelete) return;
      if (pending.upsertTs != null) {
        if (remoteTs == null || !remoteTs.isAfter(pending.upsertTs!)) return;
        _db.execute("DELETE FROM outbox WHERE tbl = ? AND id = ? AND op = 'upsert'", [tbl, id]);
      } else {
        final localTs = _localTs(tbl, id);
        if (localTs != null && remoteTs != null && remoteTs.isBefore(localTs)) return;
      }
      final existing = _readOne(tbl, id);
      _writeRow(tbl, id, {...?existing, ...row}, remoteTs?.toIso8601String());
      applied = true;
    });
    if (applied) _touch(tbl);
    return applied;
  }

  /// Aplica um apagamento recebido em tempo real: apaga e descarta os upserts pendentes da linha.
  Future<void> applyRemoteDelete(String tbl, String id) async {
    _txn(() {
      _db.execute('DELETE FROM rows WHERE tbl = ? AND id = ?', [tbl, id]);
      _db.execute("DELETE FROM outbox WHERE tbl = ? AND id = ? AND op = 'upsert'", [tbl, id]);
    });
    _touch(tbl);
  }

  /// Aplica a carga completa de uma tabela. [startedAt] é o instante em que a busca começou: linhas
  /// gravadas localmente depois dele (que a busca pode não ter visto) são preservadas.
  Future<void> applyRemoteSnapshot(
    String tbl,
    List<Map<String, dynamic>> rows, {
    required DateTime startedAt,
  }) async {
    final key = keyOf(tbl);
    final start = startedAt.toUtc();
    _txn(() {
      final remoteIds = <String>{};
      for (final row in rows) {
        final id = row[key]?.toString();
        if (id == null) continue;
        remoteIds.add(id);
        final remoteTs = parseSyncTimestamp(row[clientUpdatedAtColumn]);
        final pending = _pendingFor(tbl, id);
        if (pending.hasDelete) continue;
        if (pending.upsertTs != null) {
          if (remoteTs == null || !remoteTs.isAfter(pending.upsertTs!)) continue;
          _db.execute("DELETE FROM outbox WHERE tbl = ? AND id = ? AND op = 'upsert'", [tbl, id]);
        } else {
          final localTs = _localTs(tbl, id);
          if (localTs != null && !localTs.isBefore(start) && remoteTs != null && remoteTs.isBefore(localTs)) {
            continue;
          }
        }
        _writeRow(tbl, id, row, remoteTs?.toIso8601String());
      }
      final locals = _db.select('SELECT id, client_updated_at FROM rows WHERE tbl = ?', [tbl]);
      for (final r in locals) {
        final id = r['id'] as String;
        if (remoteIds.contains(id)) continue;
        if (_pendingFor(tbl, id).upsertTs != null) continue;
        final localTs = parseSyncTimestamp(r['client_updated_at']);
        if (localTs != null && !localTs.isBefore(start)) continue;
        _db.execute('DELETE FROM rows WHERE tbl = ? AND id = ?', [tbl, id]);
      }
    });
    _touch(tbl);
  }

  /// Faz a cópia local de uma linha voltar a ser a da nuvem ([row]; `null` = não existe na nuvem).
  /// Se a linha ainda tem alteração pendente, ela continua valendo (a pendência é mais nova).
  Future<void> restoreFromRemote(String tbl, String id, Map<String, dynamic>? row) async {
    _txn(() {
      final pending = _pendingFor(tbl, id);
      if (pending.hasDelete || pending.upsertTs != null) return;
      if (row == null) {
        _db.execute('DELETE FROM rows WHERE tbl = ? AND id = ?', [tbl, id]);
      } else {
        _writeRow(tbl, id, row, parseSyncTimestamp(row[clientUpdatedAtColumn])?.toIso8601String());
      }
    });
    _touch(tbl);
  }

  // ---------------------------------------------------------------- internos

  void _txn(void Function() body) {
    _db.execute('BEGIN IMMEDIATE');
    try {
      body();
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  void _writeRow(String tbl, String id, Map<String, dynamic> data, String? ts) {
    _db.execute(
      'INSERT OR REPLACE INTO rows (tbl, id, data_json, client_updated_at) VALUES (?, ?, ?, ?)',
      [tbl, id, _encode(data), ts],
    );
  }

  /// Junta a edição ao último item da fila quando ele é um upsert da mesma linha (digitar numa nota não
  /// gera dezenas de envios). Só o último: juntar a um item mais antigo quebraria a ordem pai/filho.
  void _enqueueUpsert(String tbl, String id, Map<String, dynamic> sent, String iso) {
    final last = _lastOutbox();
    if (last != null && last.op == OutboxOp.upsert && last.tbl == tbl && last.id == id) {
      _db.execute(
        'UPDATE outbox SET data_json = ?, client_updated_at = ?, rev = rev + 1 WHERE seq = ?',
        [_encode({...?last.data, ...sent}), iso, last.seq],
      );
      return;
    }
    _db.execute(
      "INSERT INTO outbox (tbl, op, id, data_json, client_updated_at) VALUES (?, 'upsert', ?, ?, ?)",
      [tbl, id, _encode(sent), iso],
    );
  }

  OutboxEntry? _lastOutbox() {
    final r = _db.select('SELECT * FROM outbox ORDER BY seq DESC LIMIT 1');
    return r.isEmpty ? null : _entry(r.first);
  }

  OutboxEntry _entry(Row r) => OutboxEntry(
        seq: r['seq'] as int,
        rev: r['rev'] as int,
        tbl: r['tbl'] as String,
        op: r['op'] == 'delete' ? OutboxOp.delete : OutboxOp.upsert,
        id: r['id'] as String,
        data: r['data_json'] == null ? null : _decode(r['data_json'] as String),
        clientUpdatedAt: parseSyncTimestamp(r['client_updated_at']) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        attempts: r['attempts'] as int,
        lastError: r['last_error'] as String?,
      );

  ({bool hasDelete, DateTime? upsertTs}) _pendingFor(String tbl, String id) {
    var hasDelete = false;
    DateTime? upsertTs;
    for (final r in _db.select('SELECT op, client_updated_at FROM outbox WHERE tbl = ? AND id = ?', [tbl, id])) {
      if (r['op'] == 'delete') {
        hasDelete = true;
      } else {
        final ts = parseSyncTimestamp(r['client_updated_at']) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
        if (upsertTs == null || ts.isAfter(upsertTs)) upsertTs = ts;
      }
    }
    return (hasDelete: hasDelete, upsertTs: upsertTs);
  }

  DateTime? _localTs(String tbl, String id) {
    final r = _db.select('SELECT client_updated_at FROM rows WHERE tbl = ? AND id = ?', [tbl, id]);
    return r.isEmpty ? null : parseSyncTimestamp(r.first['client_updated_at']);
  }

  static String _encode(Map<String, dynamic> data) =>
      jsonEncode(data, toEncodable: (o) => o is DateTime ? o.toUtc().toIso8601String() : o.toString());

  static Map<String, dynamic> _decode(String json) => Map<String, dynamic>.from(jsonDecode(json) as Map);

  /// Avisa os ouvintes (uma vez por volta do laço de eventos, mesmo com muitas escritas).
  void _touch(String? tbl) {
    if (tbl == null) {
      _dirtyAll = true;
    } else {
      _dirty.add(tbl);
    }
    if (_notifyScheduled || _closed) return;
    _notifyScheduled = true;
    scheduleMicrotask(_emit);
  }

  void _touchPending() => _touch('');

  void _emit() {
    _notifyScheduled = false;
    if (_closed) return;
    final tables = _dirtyAll ? _watchers.keys.toSet() : _dirty.where(_watchers.containsKey).toSet();
    _dirty.clear();
    _dirtyAll = false;
    for (final tbl in tables) {
      for (final w in (_watchers[tbl] ?? const {}).toList()) {
        if (!w.controller.isClosed) w.controller.add(_readAll(tbl));
      }
    }
    if (_pendingWatchers.isNotEmpty) {
      final n = pendingNow;
      for (final w in _pendingWatchers.toList()) {
        if (w.last != n && !w.controller.isClosed) {
          w.last = n;
          w.controller.add(n);
        }
      }
    }
  }
}

class _TableWatcher {
  _TableWatcher(this.controller);
  final StreamController<List<Map<String, dynamic>>> controller;
}

class _PendingWatcher {
  _PendingWatcher(this.controller);
  final StreamController<int> controller;
  int? last;
}
