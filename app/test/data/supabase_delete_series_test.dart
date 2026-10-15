import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:organizacional/data/repository.dart';
import 'package:organizacional/data/supabase_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

SupabaseClient _client(List<http.Request> sent, {int status = 204, String reply = ''}) {
  final mock = MockClient((http.Request req) async {
    sent.add(req);
    return http.Response(reply, status, request: req, headers: {'content-type': 'application/json'});
  });
  return SupabaseClient('http://localhost:54321', 'anon', httpClient: mock);
}

void main() {
  test('deleteSeries apaga por series_id numa só requisição, sem lista de ids', () async {
    final sent = <http.Request>[];
    await SupabaseRepository(_client(sent)).deleteSeries('serie-1');
    expect(sent, hasLength(1));
    expect(sent.single.method, 'DELETE');
    expect(sent.single.url.path, '/rest/v1/events');
    expect(sent.single.url.queryParameters, {'series_id': 'eq.serie-1'});
  });

  test('deleteSeries com from filtra starts_at >= from (UTC)', () async {
    final sent = <http.Request>[];
    final from = DateTime.utc(2026, 10, 10, 11, 30);
    await SupabaseRepository(_client(sent)).deleteSeries('serie-1', from: from);
    expect(sent.single.url.queryParameters['series_id'], 'eq.serie-1');
    expect(sent.single.url.queryParameters['starts_at'], 'gte.${from.toIso8601String()}');
  });

  test('erro do servidor vira RepositoryException', () async {
    final sent = <http.Request>[];
    final repo = SupabaseRepository(_client(sent, status: 400, reply: '{"message":"falhou","code":"XX000"}'));
    await expectLater(repo.deleteSeries('s'), throwsA(isA<RepositoryException>()));
  });
}
