import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:organizacional/data/repository.dart';
import 'package:organizacional/data/supabase_repository.dart';
import 'package:organizacional/domain/calendar_event.dart';
import 'package:organizacional/domain/event_tag.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

SupabaseClient _client(List<http.Request> sent, {int status = 200, String reply = '[]'}) {
  final mock = MockClient((http.Request req) async {
    sent.add(req);
    return http.Response(reply, status, request: req, headers: {'content-type': 'application/json'});
  });
  return SupabaseClient('http://localhost:54321', 'anon', httpClient: mock);
}

void main() {
  const tag = EventTag(id: 't1', name: 'Aula', color: '#3E63DD', role: EventTagRole.main, position: 1);

  test('upsertTag faz upsert em event_tags com os campos da etiqueta', () async {
    final sent = <http.Request>[];
    await SupabaseRepository(_client(sent, status: 201)).upsertTag(tag);
    expect(sent, hasLength(1));
    expect(sent.single.method, 'POST');
    expect(sent.single.url.path, '/rest/v1/event_tags');
    expect(sent.single.headers['Prefer'], contains('resolution=merge-duplicates'));
    expect(jsonDecode(sent.single.body), tag.toMap());
  });

  test('upsertTag com nome repetido vira RepositoryException(duplicate: true)', () async {
    final sent = <http.Request>[];
    final repo = SupabaseRepository(_client(sent, status: 409, reply: '{"message":"duplicate key","code":"23505"}'));
    await expectLater(
      repo.upsertTag(tag),
      throwsA(isA<RepositoryException>().having((e) => e.duplicate, 'duplicate', isTrue)),
    );
  });

  test('deleteTag apaga por id', () async {
    final sent = <http.Request>[];
    await SupabaseRepository(_client(sent, status: 204, reply: '')).deleteTag('t1');
    expect(sent.single.method, 'DELETE');
    expect(sent.single.url.path, '/rest/v1/event_tags');
    expect(sent.single.url.queryParameters, {'id': 'eq.t1'});
  });

  test('reorderTags grava as posições novas numa só requisição', () async {
    final sent = <http.Request>[];
    final b = tag.copyWith(id: 't2', name: 'Academia');
    final c = tag.copyWith(id: 't3', name: 'Sazonal');
    await SupabaseRepository(_client(sent, status: 201)).reorderTags([c, tag, b]);
    expect(sent, hasLength(1));
    expect(sent.single.url.path, '/rest/v1/event_tags');
    final rows = (jsonDecode(sent.single.body) as List).cast<Map<String, dynamic>>();
    expect(rows.map((r) => r['id']), ['t3', 't1', 't2']);
    expect(rows.map((r) => r['position']), [0, 1, 2]);
    expect(rows.map((r) => r['name']), ['Sazonal', 'Aula', 'Academia']);
  });

  test('seedEventTags chama a RPC seed_my_event_tags e devolve quantas criou', () async {
    final sent = <http.Request>[];
    final n = await SupabaseRepository(_client(sent, reply: '4')).seedEventTags();
    expect(n, 4);
    expect(sent.single.method, 'POST');
    expect(sent.single.url.path, '/rest/v1/rpc/seed_my_event_tags');
  });

  test('erro da RPC vira RepositoryException', () async {
    final repo = SupabaseRepository(_client([], status: 400, reply: '{"message":"falhou","code":"XX000"}'));
    await expectLater(repo.seedEventTags(), throwsA(isA<RepositoryException>()));
  });

  test('upsertEvents grava tag_id junto', () async {
    final sent = <http.Request>[];
    final e = CalendarEvent(
        id: 'e1',
        title: 'Aula',
        startsAt: DateTime.utc(2026, 10, 12, 13),
        endsAt: DateTime.utc(2026, 10, 12, 14),
        tagId: 't1');
    await SupabaseRepository(_client(sent, status: 201)).upsertEvents([e, e.copyWith(id: 'e2', clearTag: true)]);
    final rows = (jsonDecode(sent.single.body) as List).cast<Map<String, dynamic>>();
    expect(rows.map((r) => r['tag_id']), ['t1', null]);
  });
}
