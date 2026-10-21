import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:organizacional/sync/remote_source.dart';
import 'package:organizacional/sync/supabase_remote_source.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('classifySyncError', () {
    SyncError c(PostgrestException e) => classifySyncError(e);
    PostgrestException pg(String message, String? code) => PostgrestException(message: message, code: code);

    test('restrições e permissões são recusa definitiva', () {
      expect(c(pg('duplicate key', '23505')), isA<PermanentSyncError>());
      expect(c(pg('violates foreign key', '23503')), isA<PermanentSyncError>());
      expect(c(pg('not null', '23502')), isA<PermanentSyncError>());
      expect(c(pg('row-level security', '42501')), isA<PermanentSyncError>());
      expect(c(pg('invalid input', '22P02')), isA<PermanentSyncError>());
      expect(c(pg('coluna não existe', 'PGRST204')), isA<PermanentSyncError>());
      expect(c(pg('bad request', '400')), isA<PermanentSyncError>());
      expect(c(pg('forbidden', '403')), isA<PermanentSyncError>());
      expect(c(pg('not found', '404')), isA<PermanentSyncError>());
    });

    test('rede, servidor, limite e sessão vencida passam sozinhos', () {
      expect(c(pg('bad gateway', '502')), isA<TransientSyncError>());
      expect(c(pg('unavailable', '503')), isA<TransientSyncError>());
      expect(c(pg('too many', '429')), isA<TransientSyncError>());
      expect(c(pg('timeout', '408')), isA<TransientSyncError>());
      expect(c(pg('JWT expired', 'PGRST301')), isA<TransientSyncError>());
      expect(c(pg('JWT expired', '401')), isA<TransientSyncError>());
      expect(c(pg('JWT expired', '42501')), isA<TransientSyncError>());
      expect(c(pg('canceling statement due to statement timeout', '57014')), isA<TransientSyncError>());
      expect(c(pg('deadlock detected', '40P01')), isA<TransientSyncError>());
      expect(c(pg('connection failure', '08006')), isA<TransientSyncError>());
      expect(c(pg('pool', 'PGRST003')), isA<TransientSyncError>());
      expect(c(pg('sem código', null)), isA<TransientSyncError>());
    });

    test('erros de rede e desconhecidos são transitórios (nunca descarta alteração)', () {
      expect(classifySyncError(const SocketException('sem rede')), isA<TransientSyncError>());
      expect(classifySyncError(http.ClientException('falhou')), isA<TransientSyncError>());
      expect(classifySyncError(StateError('???')), isA<TransientSyncError>());
    });

    test('mantém o tipo de um SyncError que já veio classificado', () {
      const e = PermanentSyncError('x');
      expect(classifySyncError(e), same(e));
    });
  });

  group('SupabaseRemoteSource sobre HTTP', () {
    late List<http.Request> requests;
    late Future<http.Response> Function(http.Request) respond;
    late SupabaseClient db;
    late SupabaseRemoteSource source;

    setUp(() {
      requests = [];
      respond = (_) async => http.Response('[]', 200, headers: {'content-type': 'application/json'});
      db = SupabaseClient(
        'http://localhost:54321',
        'anon-key',
        httpClient: MockClient.streaming((request, bodyStream) async {
          final req = http.Request(request.method, request.url)..headers.addAll(request.headers);
          req.bodyBytes = await bodyStream.toBytes();
          requests.add(req);
          final res = await respond(req);
          return http.StreamedResponse(Stream.value(res.bodyBytes), res.statusCode,
              request: request, headers: res.headers);
        }),
      );
      source = SupabaseRemoteSource(db);
    });
    tearDown(() => db.dispose());

    http.Response json(Object body, [int status = 200]) =>
        http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

    test('fetchAll pagina de 1000 em 1000 ordenando pela chave', () async {
      final pages = <int>[];
      respond = (req) async {
        final from = int.parse(req.url.queryParameters['offset'] ?? '0');
        pages.add(from);
        final count = from == 0 ? 1000 : 3;
        return json([for (var i = 0; i < count; i++) {'id': '${from + i}'}]);
      };
      final rows = await source.fetchAll('tasks');
      expect(rows, hasLength(1003));
      expect(pages, [0, 1000]);
      expect(requests.first.url.queryParameters['order'], startsWith('id.asc'));
    });

    test('fetchAll de user_settings ordena por user_id', () async {
      await source.fetchAll('user_settings');
      expect(requests.single.url.queryParameters['order'], startsWith('user_id.asc'));
    });

    test('upsert manda as linhas e usa o conflito próprio de set_logs', () async {
      respond = (_) async => http.Response('', 201);
      await source.upsert('set_logs', [
        {'id': 'a', 'session_id': 's'},
      ]);
      await source.upsert('tasks', [
        {'id': 'b'},
      ]);
      expect(requests[0].url.queryParameters['on_conflict'], 'session_id,exercise_id,set_index');
      expect(requests[1].url.queryParameters.containsKey('on_conflict'), isFalse);
      expect(requests[0].headers['Prefer'], contains('resolution=merge-duplicates'));
      expect(jsonDecode(requests[0].body), [
        {'id': 'a', 'session_id': 's'},
      ]);
    });

    test('delete usa in(...) e divide em lotes de 100', () async {
      respond = (_) async => http.Response('', 204);
      await source.delete('tasks', [for (var i = 0; i < 250; i++) 'id$i']);
      expect(requests, hasLength(3));
      expect(requests.every((r) => r.method == 'DELETE'), isTrue);
      expect(requests.first.url.queryParameters['id'], startsWith('in.('));
    });

    test('wake_overrides (chave composta): fetchAll acrescenta o id, upsert tira o id e usa o conflito próprio', () async {
      respond = (req) async => req.method == 'GET'
          ? json([
              {'plan_id': 'p1', 'run_date': '2026-10-22', 'skip': true},
            ])
          : http.Response('', 201);
      final rows = await source.fetchAll('wake_overrides');
      expect(rows.single['id'], 'p1|2026-10-22');
      expect(requests.single.url.queryParameters['order'], startsWith('plan_id.asc'));

      await source.upsert('wake_overrides', [
        {'id': 'p1|2026-10-22', 'plan_id': 'p1', 'run_date': '2026-10-22', 'skip': true},
      ]);
      final post = requests.last;
      expect(post.url.queryParameters['on_conflict'], 'plan_id,run_date');
      expect(jsonDecode(post.body), [
        {'plan_id': 'p1', 'run_date': '2026-10-22', 'skip': true},
      ]);
    });

    test('wake_overrides: delete filtra por plano e data de cada id', () async {
      respond = (_) async => http.Response('', 204);
      await source.delete('wake_overrides', ['p1|2026-10-22', 'p2|2026-10-23']);
      expect(requests, hasLength(2));
      expect(requests[0].url.queryParameters['plan_id'], 'eq.p1');
      expect(requests[0].url.queryParameters['run_date'], 'eq.2026-10-22');
      expect(requests[1].url.queryParameters['plan_id'], 'eq.p2');
    });

    test('violação de restrição vira PermanentSyncError e 503 vira TransientSyncError', () async {
      respond = (_) async => json({'code': '23505', 'message': 'duplicate key', 'details': null, 'hint': null}, 409);
      await expectLater(source.upsert('tasks', [{'id': 'a'}]), throwsA(isA<PermanentSyncError>()));

      respond = (_) async => http.Response('Service Unavailable', 503);
      await expectLater(source.upsert('tasks', [{'id': 'a'}]), throwsA(isA<TransientSyncError>()));
      await expectLater(source.delete('tasks', ['a']), throwsA(isA<TransientSyncError>()));
    });

    test('falha de conexão vira TransientSyncError', () async {
      respond = (_) async => throw const SocketException('Failed host lookup');
      await expectLater(source.fetchAll('tasks'), throwsA(isA<TransientSyncError>()));
    });
  });
}
