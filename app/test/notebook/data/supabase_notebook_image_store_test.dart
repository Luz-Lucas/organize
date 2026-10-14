import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:organizacional/data/repository.dart';
import 'package:organizacional/notebook/data/supabase_notebook_image_store.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Req {
  _Req(this.method, this.path, this.contentType, this.bodyLength, this.json, this.rawHead);
  final String method;
  final String path;
  final String? contentType;
  final int bodyLength;
  final Object? json;
  final String rawHead;
}

void main() {
  late List<_Req> reqs;
  late int signCounter;
  late DateTime now;
  late SupabaseNotebookImageStore store;

  setUp(() {
    reqs = [];
    signCounter = 0;
    now = DateTime(2026, 10, 13, 10);
    final mock = MockClient((http.Request r) async {
      Object? json;
      try {
        json = jsonDecode(utf8.decode(r.bodyBytes));
      } catch (_) {}
      reqs.add(_Req(r.method, r.url.path, r.headers['content-type'], r.bodyBytes.length, json,
          String.fromCharCodes(r.bodyBytes.take(400)).toLowerCase()));
      if (r.url.path.contains('/object/sign/')) {
        signCounter++;
        return http.Response(
          jsonEncode({'signedURL': '/object/sign/notebook-images/x?token=t$signCounter'}),
          200,
          request: r,
          headers: {'content-type': 'application/json'},
        );
      }
      if (r.url.path.contains('/object/list/')) {
        return http.Response(
          jsonEncode([
            {'name': 'a.png'},
            {'name': 'b.jpg'},
          ]),
          200,
          request: r,
          headers: {'content-type': 'application/json'},
        );
      }
      if (r.method == 'DELETE') {
        return http.Response('[]', 200, request: r, headers: {'content-type': 'application/json'});
      }
      return http.Response(jsonEncode({'Key': 'notebook-images/ok'}), 200, request: r, headers: {'content-type': 'application/json'});
    });
    final client = SupabaseClient('http://localhost:54321', 'anon', httpClient: mock);
    store = SupabaseNotebookImageStore(client, noteId: 'note-1', userId: () => 'user-1', clock: () => now);
  });

  test('upload grava em <user>/<nota>/<uuid>.<ext> com o content-type certo e devolve o caminho', () async {
    final path = await store.upload(Uint8List.fromList([1, 2, 3]), 'png');
    expect(path, matches(RegExp(r'^user-1/note-1/[0-9a-f-]{36}\.png$')));
    final post = reqs.single;
    expect(post.method, 'POST');
    expect(post.path, '/storage/v1/object/notebook-images/$path');
    expect(post.rawHead, contains('content-type: image/png'));
  });

  test('jpg vira image/jpeg e a extensão aceita maiúsculas e ponto', () async {
    final path = await store.upload(Uint8List(4), '.JPG');
    expect(path, endsWith('.jpg'));
    expect(reqs.single.rawHead, contains('content-type: image/jpeg'));
  });

  test('formatos não aceitos pelo bucket e imagens acima de 10 MB são recusados antes de enviar', () async {
    await expectLater(store.upload(Uint8List(4), 'bmp'), throwsA(isA<RepositoryException>()));
    await expectLater(store.upload(Uint8List(10 * 1024 * 1024 + 1), 'png'), throwsA(isA<RepositoryException>()));
    expect(reqs, isEmpty);
    await store.upload(Uint8List(10 * 1024 * 1024), 'png'); // exatamente 10 MB passa
    expect(reqs, hasLength(1));
  });

  test('load assina a URL uma vez e reaproveita até perto de expirar', () async {
    final a = await store.load('user-1/note-1/a.png') as NetworkImage;
    final b = await store.load('user-1/note-1/a.png') as NetworkImage;
    expect(a.url, b.url);
    expect(a.url, contains('token=t1'));
    expect(signCounter, 1);
    now = now.add(const Duration(minutes: 50)); // 1 h de validade, renova com 10 min de folga
    final c = await store.load('user-1/note-1/a.png') as NetworkImage;
    expect(c.url, contains('token=t2'));
    expect(signCounter, 2);
    await store.load('user-1/note-1/outra.png');
    expect(signCounter, 3);
  });

  test('delete remove o objeto pela API do Storage', () async {
    await store.delete('user-1/note-1/a.png');
    final del = reqs.single;
    expect(del.method, 'DELETE');
    expect(del.path, '/storage/v1/object/notebook-images');
    expect((del.json as Map)['prefixes'], ['user-1/note-1/a.png']);
  });

  test('purgeAll lista a pasta <user>/<nota> e apaga cada imagem pela API do Storage', () async {
    await store.purgeAll();
    final list = reqs.firstWhere((r) => r.path.contains('/object/list/'));
    expect((list.json as Map)['prefix'], 'user-1/note-1');
    final del = reqs.firstWhere((r) => r.method == 'DELETE');
    expect((del.json as Map)['prefixes'], ['user-1/note-1/a.png', 'user-1/note-1/b.jpg']);
  });

  test('purgeAll pagina a listagem: mais de 100 imagens são todas apagadas', () async {
    final names = [for (var i = 0; i < 250; i++) 'img-$i.png'];
    final listCalls = <Map>[];
    final deleted = <String>[];
    final client = SupabaseClient(
      'http://localhost:54321',
      'anon',
      httpClient: MockClient((r) async {
        final json = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
        if (r.url.path.contains('/object/list/')) {
          listCalls.add(json);
          final limit = (json['limit'] as num?)?.toInt() ?? 100;
          final offset = (json['offset'] as num?)?.toInt() ?? 0;
          final page = names.skip(offset).take(limit).toList();
          return http.Response(jsonEncode([for (final n in page) {'name': n}]), 200,
              request: r, headers: {'content-type': 'application/json'});
        }
        if (r.method == 'DELETE') {
          deleted.addAll((json['prefixes'] as List).cast<String>());
          return http.Response('[]', 200, request: r, headers: {'content-type': 'application/json'});
        }
        return http.Response('{}', 200, request: r);
      }),
    );
    final big = SupabaseNotebookImageStore(client, noteId: 'note-1', userId: () => 'user-1');
    await big.purgeAll();
    expect(deleted.toSet(), {for (final n in names) 'user-1/note-1/$n'});
    expect(deleted, hasLength(250));
    expect(listCalls.map((c) => c['offset']), [0, 100, 200]);
  });

  test('falha do Storage vira RepositoryException', () async {
    final failing = SupabaseNotebookImageStore(
      SupabaseClient('http://localhost:54321', 'anon',
          httpClient: MockClient((r) async => http.Response('{"message":"x","statusCode":"400","error":"e"}', 400, request: r))),
      noteId: 'n',
      userId: () => 'u',
    );
    await expectLater(failing.upload(Uint8List(2), 'png'), throwsA(isA<RepositoryException>()));
    await expectLater(failing.load('u/n/a.png'), throwsA(isA<RepositoryException>()));
  });

  test('sem usuário logado não envia', () async {
    final anon = SupabaseNotebookImageStore(
      SupabaseClient('http://localhost:54321', 'anon', httpClient: MockClient((r) async => http.Response('{}', 200, request: r))),
      noteId: 'n',
      userId: () => null,
    );
    await expectLater(anon.upload(Uint8List(2), 'png'), throwsA(isA<RepositoryException>()));
  });
}
