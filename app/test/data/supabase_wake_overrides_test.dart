import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:organizacional/data/repository.dart';
import 'package:organizacional/data/supabase_alexa_repository.dart';
import 'package:organizacional/domain/wake_override.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Sent {
  _Sent(this.method, this.url, this.prefer, this.body);
  final String method;
  final Uri url;
  final String? prefer;
  final Object? body;
}

SupabaseClient _client(List<_Sent> sent, {int status = 201, String reply = '[]'}) {
  final mock = MockClient((http.Request req) async {
    sent.add(_Sent(req.method, req.url, req.headers['Prefer'], req.body.isEmpty ? null : jsonDecode(req.body)));
    return http.Response(reply, status, request: req, headers: {'content-type': 'application/json'});
  });
  return SupabaseClient('http://localhost:54321', 'anon', httpClient: mock);
}

void main() {
  test('setOverride faz upsert por (plan_id, run_date) com pulo ou horário, sem user_id', () async {
    final sent = <_Sent>[];
    final repo = SupabaseAlexaRepository(_client(sent));
    await repo.setOverride(WakeOverride.skip('p1', DateTime(2026, 9, 29)));
    await repo.setOverride(WakeOverride.at('p1', DateTime(2026, 9, 30), 6, 30));
    expect(sent.map((s) => s.url.path).toSet(), {'/rest/v1/wake_overrides'});
    expect(sent.map((s) => s.method).toSet(), {'POST'});
    expect(sent[0].url.queryParameters['on_conflict'], 'plan_id,run_date');
    expect(sent[0].prefer, contains('resolution=merge-duplicates'));
    expect(sent[0].body, {'plan_id': 'p1', 'run_date': '2026-09-29', 'skip': true, 'time': null});
    expect(sent[1].body, {'plan_id': 'p1', 'run_date': '2026-09-30', 'skip': false, 'time': '06:30'});
  });

  test('clearOverride apaga só aquele plano e data', () async {
    final sent = <_Sent>[];
    final repo = SupabaseAlexaRepository(_client(sent, status: 204, reply: ''));
    await repo.clearOverride('p1', DateTime(2026, 9, 29, 23));
    expect(sent.single.method, 'DELETE');
    expect(sent.single.url.path, '/rest/v1/wake_overrides');
    expect(sent.single.url.queryParameters, {'plan_id': 'eq.p1', 'run_date': 'eq.2026-09-29'});
  });

  test('erro do servidor vira RepositoryException', () async {
    final repo = SupabaseAlexaRepository(
      _client(<_Sent>[], status: 403, reply: '{"message":"violou a política","code":"42501"}'),
    );
    await expectLater(repo.setOverride(WakeOverride.skip('p1', DateTime(2026, 9, 29))), throwsA(isA<RepositoryException>()));
    await expectLater(repo.clearOverride('p1', DateTime(2026, 9, 29)), throwsA(isA<RepositoryException>()));
  });
}
