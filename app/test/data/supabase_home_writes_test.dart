import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:organizacional/data/repository.dart';
import 'package:organizacional/data/supabase_location_repository.dart';
import 'package:organizacional/data/supabase_settings_repository.dart';
import 'package:organizacional/location/location_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Sent {
  _Sent(this.method, this.path, this.prefer, this.body);
  final String method;
  final String path;
  final String? prefer;
  final Object? body;
}

SupabaseClient _client(List<_Sent> sent, {int status = 201, String reply = '[]'}) {
  final mock = MockClient((http.Request req) async {
    sent.add(_Sent(req.method, req.url.path, req.headers['Prefer'],
        req.body.isEmpty ? null : jsonDecode(req.body)));
    return http.Response(reply, status, request: req, headers: {'content-type': 'application/json'});
  });
  return SupabaseClient('http://localhost:54321', 'anon', httpClient: mock);
}

void main() {
  test('setHome / clearHome / setRequireHome gravam só as suas colunas, com o user_id', () async {
    final sent = <_Sent>[];
    final repo = SupabaseSettingsRepository(_client(sent), userId: () => 'u1');
    await repo.setHome(-19.9167, -45.7);
    await repo.clearHome();
    await repo.setRequireHome(false);
    expect(sent.map((s) => s.path).toSet(), {'/rest/v1/user_settings'});
    expect(sent.map((s) => s.method).toSet(), {'POST'});
    expect(sent[0].prefer, contains('resolution=merge-duplicates'));
    expect(sent[0].body, {'user_id': 'u1', 'home_lat': -19.9167, 'home_lon': -45.7});
    expect(sent[1].body, {'user_id': 'u1', 'home_lat': null, 'home_lon': null});
    expect(sent[2].body, {'user_id': 'u1', 'require_home': false});
  });

  test('setNotebookPrefs grava só a coluna notebook_prefs, com o user_id', () async {
    final sent = <_Sent>[];
    final repo = SupabaseSettingsRepository(_client(sent), userId: () => 'u1');
    await repo.setNotebookPrefs({'v': 1, 'compact': true});
    expect(sent.single.path, '/rest/v1/user_settings');
    expect(sent.single.prefer, contains('resolution=merge-duplicates'));
    expect(sent.single.body, {
      'user_id': 'u1',
      'notebook_prefs': {'v': 1, 'compact': true},
    });
  });

  test('erro do servidor vira RepositoryException', () async {
    final sent = <_Sent>[];
    final repo = SupabaseSettingsRepository(
      _client(sent, status: 400, reply: '{"message":"violou o check","code":"23514"}'),
      userId: () => 'u1',
    );
    await expectLater(repo.setHome(1, 2), throwsA(isA<RepositoryException>()));
  });

  test('report faz upsert de user_id, lat, lon e accuracy_m, sem reported_at', () async {
    final sent = <_Sent>[];
    final repo = SupabaseLocationRepository(_client(sent), userId: () => 'u1');
    await repo.report(const GeoFix(lat: -19.9167, lon: -45.7, accuracyM: 12.5), DateTime(2020));
    await repo.report(const GeoFix(lat: 1, lon: 2), DateTime(2020));
    expect(sent.map((s) => s.path).toSet(), {'/rest/v1/user_locations'});
    expect(sent[0].prefer, contains('resolution=merge-duplicates'));
    expect(sent[0].body, {'user_id': 'u1', 'lat': -19.9167, 'lon': -45.7, 'accuracy_m': 12.5});
    expect(sent[1].body, {'user_id': 'u1', 'lat': 1, 'lon': 2, 'accuracy_m': null});
    for (final s in sent) {
      expect((s.body as Map).containsKey('reported_at'), isFalse);
    }
  });

  test('falha do servidor ao reportar vira RepositoryException', () async {
    final repo = SupabaseLocationRepository(
      _client(<_Sent>[], status: 500, reply: '{"message":"boom"}'),
      userId: () => 'u1',
    );
    await expectLater(repo.report(const GeoFix(lat: 1, lon: 2), DateTime(2020)), throwsA(isA<RepositoryException>()));
  });
}
