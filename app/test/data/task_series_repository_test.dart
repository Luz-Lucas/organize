import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/data/repository.dart';
import 'package:organizacional/data/supabase_repository.dart';
import 'package:organizacional/domain/task_item.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

TaskItem _t(String id, int day, {String? series = 's1'}) =>
    TaskItem(id: id, title: 'Lab', dueAt: DateTime(2026, 10, day, 23, 59), seriesId: series);

SupabaseClient _client(List<http.Request> sent, {int status = 200, String reply = '[]'}) {
  final mock = MockClient((http.Request req) async {
    sent.add(req);
    return http.Response(reply, status, request: req, headers: {'content-type': 'application/json'});
  });
  return SupabaseClient('http://localhost:54321', 'anon', httpClient: mock);
}

void main() {
  group('MemoryRepository', () {
    test('upsertTasks grava todas de uma vez e deleteTasks remove só os ids', () async {
      final repo = MemoryRepository();
      await repo.upsertTasks([_t('a', 20), _t('b', 27), _t('c', 28, series: null)]);
      expect((await repo.watchTasks().first).length, 3);
      await repo.deleteTasks(['a', 'c']);
      expect((await repo.watchTasks().first).map((t) => t.id), ['b']);
    });

    test('listas vazias não fazem nada nem emitem erro', () async {
      final repo = MemoryRepository()..failWrites = true;
      await repo.upsertTasks(const []);
      await repo.deleteTasks(const []);
    });

    test('listTaskSeries devolve só a série, por prazo', () async {
      final repo = MemoryRepository();
      await repo.upsertTasks([_t('c', 4), _t('a', 20), _t('x', 21, series: 'outra'), _t('b', 27)]);
      expect((await repo.listTaskSeries('s1')).map((t) => t.id), ['c', 'a', 'b']);
      expect(await repo.listTaskSeries('nada'), isEmpty);
    });

    test('falha de conexão vira RepositoryException', () async {
      final repo = MemoryRepository()..failWrites = true;
      await expectLater(repo.upsertTasks([_t('a', 20)]), throwsA(isA<RepositoryException>()));
      await expectLater(repo.deleteTasks(['a']), throwsA(isA<RepositoryException>()));
    });
  });

  group('SupabaseRepository', () {
    test('upsertTasks manda uma só requisição com o array e series_id/recurrence', () async {
      final sent = <http.Request>[];
      await SupabaseRepository(_client(sent, status: 201)).upsertTasks([_t('a', 20), _t('b', 27)]);
      expect(sent, hasLength(1));
      expect(sent.single.method, 'POST');
      expect(sent.single.url.path, '/rest/v1/tasks');
      final body = jsonDecode(sent.single.body) as List;
      expect(body.length, 2);
      expect((body.first as Map)['series_id'], 's1');
      expect((body.first as Map).containsKey('recurrence'), isTrue);
    });

    test('deleteTasks apaga em lotes para não estourar a URL', () async {
      final sent = <http.Request>[];
      final ids = [for (var i = 0; i < 250; i++) 'id$i'];
      await SupabaseRepository(_client(sent, status: 204, reply: '')).deleteTasks(ids);
      expect(sent.length, 3);
      expect(sent.every((r) => r.method == 'DELETE' && r.url.path == '/rest/v1/tasks'), isTrue);
      final all = sent.expand((r) => RegExp(r'id\d+').allMatches(r.url.queryParameters['id']!).map((m) => m[0]!));
      expect(all.toSet(), ids.toSet());
      expect(sent.every((r) => RegExp(r'id\d+').allMatches(r.url.queryParameters['id']!).length <= 100), isTrue);
    });

    test('listas vazias não chamam a rede', () async {
      final sent = <http.Request>[];
      final repo = SupabaseRepository(_client(sent));
      await repo.upsertTasks(const []);
      await repo.deleteTasks(const []);
      expect(sent, isEmpty);
    });

    test('listTaskSeries filtra por series_id e ordena por due_at', () async {
      final sent = <http.Request>[];
      final row = _t('a', 20).toMap();
      final repo = SupabaseRepository(_client(sent, reply: jsonEncode([row])));
      final out = await repo.listTaskSeries('s1');
      expect(out.single.id, 'a');
      expect(sent.single.method, 'GET');
      expect(sent.single.url.path, '/rest/v1/tasks');
      expect(sent.single.url.queryParameters['series_id'], 'eq.s1');
      expect(sent.single.url.queryParameters['order'], startsWith('due_at.asc'));
    });

    test('erro do servidor vira RepositoryException', () async {
      final sent = <http.Request>[];
      final repo = SupabaseRepository(_client(sent, status: 400, reply: '{"message":"falhou","code":"XX000"}'));
      await expectLater(repo.listTaskSeries('s'), throwsA(isA<RepositoryException>()));
      await expectLater(repo.upsertTasks([_t('a', 20)]), throwsA(isA<RepositoryException>()));
      await expectLater(repo.deleteTasks(['a']), throwsA(isA<RepositoryException>()));
    });
  });
}
