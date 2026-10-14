import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:organizacional/data/repository.dart';
import 'package:organizacional/update/release_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late List<http.Request> reqs;
  late List<Map<String, dynamic>> rows;
  late int status;
  late SupabaseReleaseRepository repo;

  setUp(() {
    reqs = [];
    status = 200;
    rows = [];
    final mock = MockClient((r) async {
      reqs.add(r);
      if (r.url.path.contains('/object/sign/')) {
        if (status != 200) {
          return http.Response(jsonEncode({'message': 'negado', 'statusCode': '403', 'error': 'x'}), status,
              request: r, headers: {'content-type': 'application/json'});
        }
        return http.Response(jsonEncode({'signedURL': '/object/sign/app-releases/android/7/x.apk?token=abc'}), 200,
            request: r, headers: {'content-type': 'application/json'});
      }
      return http.Response(jsonEncode(rows), status, request: r, headers: {'content-type': 'application/json'});
    });
    repo = SupabaseReleaseRepository(SupabaseClient('http://localhost:54321', 'anon', httpClient: mock));
  });

  Map<String, dynamic> row(int build) => {
        'id': 'r$build', 'platform': 'android', 'version': '1.0.$build', 'build': build,
        'storage_path': 'android/$build/x.apk', 'sha256': 'a' * 64, 'size_bytes': 10, 'notes': 'n',
      };

  test('latest consulta só a plataforma pedida, por build decrescente, com limite 1', () async {
    rows = [row(7)];
    final r = await repo.latest('android');
    expect(r?.build, 7);
    final q = reqs.single.url.queryParameters;
    expect(reqs.single.url.path, '/rest/v1/app_releases');
    expect(q['platform'], 'eq.android');
    expect(q['order'], startsWith('build.desc'));
    expect(q['limit'], '1');
  });

  test('latest devolve null quando não há release', () async {
    expect(await repo.latest('windows'), isNull);
  });

  test('latest troca falha de rede/servidor por RepositoryException', () async {
    status = 500;
    await expectLater(repo.latest('android'), throwsA(isA<RepositoryException>()));
  });

  test('signedUrl pede URL assinada de curta duração no bucket app-releases', () async {
    final url = await repo.signedUrl('android/7/x.apk');
    final req = reqs.single;
    expect(req.url.path, '/storage/v1/object/sign/app-releases/android/7/x.apk');
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    expect(body['expiresIn'], lessThanOrEqualTo(600));
    expect(url.toString(), contains('token=abc'));
    expect(url.hasScheme, isTrue);
  });

  test('signedUrl com erro do Storage vira RepositoryException', () async {
    status = 403;
    await expectLater(repo.signedUrl('android/7/x.apk'), throwsA(isA<RepositoryException>()));
  });
}
