import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'local_store.dart';
import 'remote_source.dart';

/// Chave de conflito do upsert quando não é a primária: a série da Academia é única por
/// (sessão, exercício, índice), então reenviar a mesma série nunca duplica.
const defaultConflictTargets = <String, String>{
  'set_logs': 'session_id,exercise_id,set_index',
  'wake_overrides': 'plan_id,run_date',
};

/// Tabelas cuja chave primária é composta (sem coluna `id`): o aparelho guarda a linha com um `id`
/// sintético (colunas juntas por `|`), que nunca vai para a nuvem.
const defaultCompositeKeys = <String, List<String>>{
  'wake_overrides': ['plan_id', 'run_date'],
};

/// `id` local de uma linha de tabela de chave composta (ex.: `<plano>|<data>`).
String compositeId(Map<String, dynamic> row, List<String> columns) =>
    columns.map((c) => row[c]?.toString() ?? '').join('|');

/// Decide se um erro passa sozinho ([TransientSyncError]) ou é recusa definitiva ([PermanentSyncError]).
/// Na dúvida é transitório: nunca descartamos uma alteração por um erro que não conhecemos.
SyncError classifySyncError(Object error) {
  if (error is SyncError) return error;
  if (error is PostgrestException) {
    final message = error.message;
    if (message.toLowerCase().contains('jwt')) return TransientSyncError(message); // sessão renovando
    final code = error.code ?? '';
    // Sem código do banco, o PostgREST põe o status HTTP (3 dígitos); SQLSTATE tem 5 caracteres.
    final status = code.length == 3 ? int.tryParse(code) : null;
    if (status != null) {
      if (status == 401 || status == 408 || status == 429 || status >= 500) return TransientSyncError(message);
      return PermanentSyncError(message);
    }
    if (code.startsWith('PGRST')) {
      // 000-003: sem conexão/pool com o banco; 301-303: token (JWT) vencido ou inválido, a sessão renova.
      const transient = {'PGRST000', 'PGRST001', 'PGRST002', 'PGRST003', 'PGRST301', 'PGRST302', 'PGRST303'};
      return transient.contains(code) ? TransientSyncError(message) : PermanentSyncError(message);
    }
    if (code.length == 5) {
      // SQLSTATE. Transitórios: conexão (08), recursos (53), cancelado/desligando (57), disco (58),
      // serialização/deadlock (40), erro interno (XX). O resto — 22 dado inválido, 23 restrição,
      // 42 permissão/sintaxe… — é recusa.
      const transientClasses = {'08', '53', '57', '58', '40', 'XX'};
      return transientClasses.contains(code.substring(0, 2))
          ? TransientSyncError(message)
          : PermanentSyncError(message);
    }
    return TransientSyncError(message);
  }
  return TransientSyncError(error.toString());
}

/// Fala com o Supabase (REST + realtime) da conta logada.
class SupabaseRemoteSource implements RemoteSource {
  SupabaseRemoteSource(
    this._db, {
    Map<String, String> keys = const {},
    this._conflictTargets = defaultConflictTargets,
    this._compositeKeys = defaultCompositeKeys,
  }) : _keys = {...defaultSyncKeys, ...keys};

  final SupabaseClient _db;
  final Map<String, String> _keys;
  final Map<String, String> _conflictTargets;
  final Map<String, List<String>> _compositeKeys;
  int _channelSeq = 0;

  static const _pageSize = 1000;
  static const _upsertBatch = 200;
  static const _deleteBatch = 100; // o filtro `id in (...)` vai na URL

  String _keyOf(String tbl) => _compositeKeys[tbl]?.first ?? _keys[tbl] ?? 'id';

  /// Acrescenta o `id` sintético às linhas vindas da nuvem nas tabelas de chave composta.
  Map<String, dynamic> _fromCloud(String tbl, Map<String, dynamic> row) {
    final columns = _compositeKeys[tbl];
    return columns == null ? row : {...row, 'id': compositeId(row, columns)};
  }

  /// Tira o `id` sintético antes de enviar.
  Map<String, dynamic> _toCloud(String tbl, Map<String, dynamic> row) {
    if (!_compositeKeys.containsKey(tbl)) return row;
    return {...row}..remove('id');
  }

  Future<T> _guard<T>(Future<T> Function() op) async {
    try {
      return await op();
    } catch (e) {
      throw classifySyncError(e);
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchAll(String tbl) => _guard(() async {
        final out = <Map<String, dynamic>>[];
        for (var from = 0;; from += _pageSize) {
          final page = await _db.from(tbl).select().order(_keyOf(tbl), ascending: true).range(from, from + _pageSize - 1);
          out.addAll(page.map((r) => _fromCloud(tbl, Map<String, dynamic>.from(r))));
          if (page.length < _pageSize) return out;
        }
      });

  @override
  Future<void> upsert(String tbl, List<Map<String, dynamic>> rows) => _guard(() async {
        for (var i = 0; i < rows.length; i += _upsertBatch) {
          final end = i + _upsertBatch > rows.length ? rows.length : i + _upsertBatch;
          await _db
              .from(tbl)
              .upsert([for (final r in rows.sublist(i, end)) _toCloud(tbl, r)], onConflict: _conflictTargets[tbl]);
        }
      });

  @override
  Future<void> delete(String tbl, List<String> ids) => _guard(() async {
        final columns = _compositeKeys[tbl];
        if (columns != null) {
          // Sem coluna `id`: um DELETE por linha, filtrando cada coluna da chave.
          for (final id in ids) {
            final parts = id.split('|');
            if (parts.length != columns.length) continue;
            var query = _db.from(tbl).delete();
            for (var c = 0; c < columns.length; c++) {
              query = query.eq(columns[c], parts[c]);
            }
            await query;
          }
          return;
        }
        for (var i = 0; i < ids.length; i += _deleteBatch) {
          final end = i + _deleteBatch > ids.length ? ids.length : i + _deleteBatch;
          await _db.from(tbl).delete().inFilter(_keyOf(tbl), ids.sublist(i, end));
        }
      });

  @override
  Stream<RemoteChange> changes(String tbl) {
    late final StreamController<RemoteChange> controller;
    RealtimeChannel? channel;
    controller = StreamController<RemoteChange>(
      onListen: () {
        channel = _db
            .channel('sync:$tbl:${_channelSeq++}')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: tbl,
              callback: (payload) {
                if (controller.isClosed) return;
                if (payload.eventType == PostgresChangeEvent.delete) {
                  controller.add(RemoteChange(RemoteChangeType.delete, _fromCloud(tbl, payload.oldRecord)));
                } else {
                  controller.add(RemoteChange(RemoteChangeType.upsert, _fromCloud(tbl, payload.newRecord)));
                }
              },
            )
            .subscribe((status, error) {
              if (controller.isClosed) return;
              if (status == RealtimeSubscribeStatus.channelError || status == RealtimeSubscribeStatus.timedOut) {
                controller.addError(TransientSyncError(error?.toString() ?? 'Tempo real indisponível ($status)'));
              }
            });
      },
      onCancel: () async {
        final c = channel;
        channel = null;
        if (c != null) await _db.removeChannel(c);
      },
    );
    return controller.stream;
  }
}
