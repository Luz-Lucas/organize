import 'dart:convert';

// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class Sent {
  Sent(this.method, this.path, this.query, this.prefer, this.body);
  final String method;
  final String path;
  final Map<String, String> query;
  final String? prefer;
  final Object? body;

  @override
  String toString() => '$method $path $query $body';
}

/// PostgREST mínimo para `note_pages` e `notes`: filtros `eq`, `order`, `limit`,
/// unique (note_id, idx) imediata (a pior hipótese: não adiada) e versão otimista
/// feita pelo cliente. Registra tudo em [sent].
class FakePostgrest {
  final sent = <Sent>[];
  final pages = <String, Map<String, dynamic>>{};
  final notes = <String, Map<String, dynamic>>{};

  /// Faz a próxima requisição que casar com [when] falhar com [status].
  bool Function(Sent)? failWhen;
  int failStatus = 500;
  String failCode = 'XX000';

  /// Executa antes de cada requisição (para simular outro aparelho gravando no meio).
  void Function(Sent)? beforeRequest;

  SupabaseClient client() => SupabaseClient(
        'http://localhost:54321',
        'anon',
        httpClient: MockClient(_handle),
      );

  http.Response _json(http.Request req, Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status,
          request: req, headers: {'content-type': 'application/json; charset=utf-8'});

  bool _matches(Map<String, dynamic> row, Map<String, String> q) {
    for (final e in q.entries) {
      if (const {'select', 'order', 'limit', 'columns'}.contains(e.key)) continue;
      if (e.value.startsWith('neq.')) {
        if ('${row[e.key]}' == e.value.substring(4)) return false;
        continue;
      }
      if (!e.value.startsWith('eq.')) throw StateError('filtro não suportado: ${e.key}=${e.value}');
      if ('${row[e.key]}' != e.value.substring(3)) return false;
    }
    return true;
  }

  Future<http.Response> _handle(http.Request req) async {
    final body = req.body.isEmpty ? null : jsonDecode(req.body);
    final s = Sent(req.method, req.url.path, req.url.queryParameters, req.headers['Prefer'], body);
    beforeRequest?.call(s);
    sent.add(s);
    if (failWhen != null && failWhen!(s)) {
      return _json(req, {'message': 'falhou', 'code': failCode}, failStatus);
    }
    final table = req.url.path.split('/').last;
    final rows = table == 'note_pages' ? pages : notes;
    final q = req.url.queryParameters;
    switch (req.method) {
      case 'GET':
        var out = [for (final r in rows.values) if (_matches(r, q)) r];
        final order = q['order'];
        if (order != null) {
          final parts = order.split('.');
          out.sort((a, b) => (a[parts[0]] as Comparable).compareTo(b[parts[0]]));
          if (parts.length > 1 && parts[1] == 'desc') out = out.reversed.toList();
        }
        final limit = int.tryParse(q['limit'] ?? '');
        if (limit != null && out.length > limit) out = out.sublist(0, limit);
        return _json(req, out);
      case 'PATCH':
        final hit = [for (final r in rows.values) if (_matches(r, q)) r];
        for (final r in hit) {
          r.addAll((body as Map).cast<String, dynamic>());
          r['updated_at'] = '2026-10-13T10:00:00Z';
          if (table == 'note_pages') {
            final clash = pages.values.any((o) => o['id'] != r['id'] && o['note_id'] == r['note_id'] && o['idx'] == r['idx']);
            if (clash) {
              // desfaz e falha como o Postgres (a constraint real é adiada, mas só no fim da transação).
              return _json(req, {'message': 'duplicate key value violates unique constraint', 'code': '23505'}, 409);
            }
          }
        }
        return (req.headers['Prefer'] ?? '').contains('return=representation')
            ? _json(req, hit)
            : http.Response('', 204, request: req);
      case 'POST':
        final list = body is List ? body : [body];
        final out = <Map<String, dynamic>>[];
        for (final raw in list) {
          final r = (raw as Map).cast<String, dynamic>();
          if (table == 'note_pages') {
            if (pages.containsKey(r['id'])) {
              return _json(req, {'message': 'duplicate key value violates unique constraint "note_pages_pkey"', 'code': '23505'}, 409);
            }
            if (pages.values.any((o) => o['note_id'] == r['note_id'] && o['idx'] == r['idx'])) {
              return _json(req, {'message': 'duplicate key value violates unique constraint "note_pages_note_idx_uq"', 'code': '23505'}, 409);
            }
            r.putIfAbsent('background', () => 'lined');
            r.putIfAbsent('data', () => '');
            r.putIfAbsent('recognized_text', () => '');
            r.putIfAbsent('version', () => 0);
            r['updated_at'] = '2026-10-13T10:00:00Z';
          }
          rows[r['id'] as String] = r;
          out.add(r);
        }
        return (req.headers['Prefer'] ?? '').contains('return=representation')
            ? _json(req, out, 201)
            : http.Response('', 201, request: req);
      case 'DELETE':
        final ids = [for (final r in rows.values) if (_matches(r, q)) r['id'] as String];
        ids.forEach(rows.remove);
        return http.Response('', 204, request: req);
    }
    return _json(req, {'message': 'método não suportado'}, 405);
  }
}
