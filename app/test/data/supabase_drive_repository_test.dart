import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:organizacional/data/repository.dart';
import 'package:organizacional/data/supabase_drive_repository.dart';
import 'package:organizacional/domain/drive.dart';

class _Call {
  _Call(this.function, this.body);
  final String function;
  final Map<String, dynamic> body;
}

SupabaseDriveRepository _repo(
  List<_Call> calls,
  Map<String, dynamic> Function(_Call) reply, {
  http.Client? client,
}) =>
    SupabaseDriveRepository.test(
      invoke: (fn, body) async {
        final c = _Call(fn, body);
        calls.add(c);
        return reply(c);
      },
      httpClient: client,
    );

void main() {
  test('list manda {action:list,folderId} e converte o resultado', () async {
    final calls = <_Call>[];
    final repo = _repo(calls, (_) => {
          'folder': {'id': 'r', 'name': 'Organizacional', 'parents': ['m']},
          'items': [
            {'id': 'a', 'name': 'Provas', 'mimeType': driveFolderMime, 'isFolder': true},
            {'id': 'b', 'name': 'x.pdf', 'mimeType': 'application/pdf', 'isFolder': false, 'size': 10},
          ],
        });
    final l = await repo.list();
    expect(calls.single.function, 'drive');
    expect(calls.single.body, {'action': 'list'});
    expect(l.folder.name, 'Organizacional');
    expect(l.folder.parents, ['m']);
    expect(l.items.map((i) => i.name), ['Provas', 'x.pdf']);
    await repo.list(folderId: 'root');
    expect(calls.last.body, {'action': 'list', 'folderId': 'root'});
  });

  test('ações simples mandam os parâmetros certos', () async {
    final calls = <_Call>[];
    final repo = _repo(calls, (c) => switch (c.body['action']) {
          'create_folder' || 'ensure_folder' => {
              'item': {'id': 'n', 'name': c.body['name'], 'mimeType': driveFolderMime}
            },
          'search' => {'items': []},
          'permissions' => {
              'permissions': [
                {'id': 'p', 'email': 'a@b.com', 'role': 'writer', 'type': 'user'}
              ]
            },
          'share_link' => {'webViewLink': 'https://drive.google.com/x'},
          _ => {'ok': true},
        });
    await repo.createFolder('P', 'Nova');
    expect(calls.last.body, {'action': 'create_folder', 'parentId': 'P', 'name': 'Nova'});
    expect((await repo.ensureFolder('P', 'Importados')).id, 'n');
    expect(calls.last.body['action'], 'ensure_folder');
    await repo.rename('i', 'Outro');
    expect(calls.last.body, {'action': 'rename', 'id': 'i', 'name': 'Outro'});
    await repo.move('i', 'D');
    expect(calls.last.body, {'action': 'move', 'id': 'i', 'toFolderId': 'D'});
    await repo.trash('i');
    expect(calls.last.body, {'action': 'trash', 'id': 'i'});
    await repo.restore('i');
    expect(calls.last.body, {'action': 'restore', 'id': 'i'});
    await repo.search('edital');
    expect(calls.last.body, {'action': 'search', 'q': 'edital'});
    await repo.share('i', 'a@b.com', DriveRole.commenter, notify: true);
    expect(calls.last.body, {'action': 'share', 'id': 'i', 'email': 'a@b.com', 'role': 'commenter', 'notify': true});
    expect(await repo.setLinkSharing('i', true), 'https://drive.google.com/x');
    expect(calls.last.body, {'action': 'share_link', 'id': 'i', 'enabled': true});
    final p = await repo.permissions('i');
    expect(p.single.roleLabel, 'Editor');
    await repo.unshare('i', 'p');
    expect(calls.last.body, {'action': 'unshare', 'id': 'i', 'permissionId': 'p'});
  });

  test('driveErrorFrom usa a mensagem e o código do servidor; sem corpo usa texto genérico', () {
    final e = driveErrorFrom(409, {'error': 'O acesso ao Google Drive expirou. Reconecte em Ajustes.', 'code': 'auth_required'});
    expect(e.message, contains('expirou'));
    expect(e.code, 'auth_required');
    expect(e.needsReconnect, isTrue);
    final g = driveErrorFrom(500, '<html>');
    expect(g.message, 'Falha ao chamar o servidor (500).');
    expect(g.code, isNull);
    expect(driveErrorFrom(0, null).message, contains('conexão'));
  });

  test('upload: cria a sessão, faz PUT dos bytes na URL devolvida e lê o resultado', () async {
    final calls = <_Call>[];
    late http.BaseRequest sent;
    late List<int> sentBody;
    final client = MockClient.streaming((req, body) async {
      sent = req;
      sentBody = (await body.toList()).expand((e) => e).toList();
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({'id': 'f1', 'name': 'a.pdf', 'webViewLink': 'https://drive.google.com/file/d/f1/view'}))),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final repo = _repo(calls, (_) => {'uploadUrl': 'https://www.googleapis.com/upload/drive/v3/files?upload_id=X'}, client: client);
    final progress = <int>[];
    final up = await repo.upload(
      parentId: 'P',
      name: 'a.pdf',
      mimeType: 'application/pdf',
      size: 6,
      data: Stream.fromIterable([
        [1, 2, 3],
        [4, 5, 6],
      ]),
      onProgress: (s, t) => progress.add(s),
    );
    expect(calls.single.body, {'action': 'upload_session', 'parentId': 'P', 'name': 'a.pdf', 'mimeType': 'application/pdf', 'size': 6});
    expect(sent.method, 'PUT');
    expect(sent.url.toString(), 'https://www.googleapis.com/upload/drive/v3/files?upload_id=X');
    expect(sent.headers['content-type'], 'application/pdf');
    expect(sent.contentLength, 6);
    expect(sentBody, [1, 2, 3, 4, 5, 6]);
    expect(progress.last, 6);
    expect(up.id, 'f1');
    expect(up.webViewLink, contains('f1'));
  });

  test('upload: resposta de erro vira RepositoryException e URL que não é do Google é recusada', () async {
    final bad = MockClient.streaming((req, body) async {
      await body.drain<void>();
      return http.StreamedResponse(const Stream.empty(), 500);
    });
    final repo = _repo([], (_) => {'uploadUrl': 'https://www.googleapis.com/upload/drive/v3/files?upload_id=X'}, client: bad);
    await expectLater(
      repo.upload(parentId: 'P', name: 'a', mimeType: 'a/b', size: 1, data: Stream.value([1])),
      throwsA(isA<RepositoryException>()),
    );
    final evil = _repo([], (_) => {'uploadUrl': 'https://evil.example/up'});
    await expectLater(
      evil.upload(parentId: 'P', name: 'a', mimeType: 'a/b', size: 1, data: Stream.value([1])),
      throwsA(isA<RepositoryException>()),
    );
  });

  test('upload: se os bytes lidos não batem com o tamanho, falha sem enviar lixo', () async {
    final client = MockClient.streaming((req, body) async {
      await body.drain<void>();
      return http.StreamedResponse(Stream.value(utf8.encode('{"id":"x","name":"a"}')), 200);
    });
    final repo = _repo([], (_) => {'uploadUrl': 'https://www.googleapis.com/upload/drive/v3/files?upload_id=X'}, client: client);
    await expectLater(
      repo.upload(parentId: 'P', name: 'a', mimeType: 'a/b', size: 10, data: Stream.value([1, 2])),
      throwsA(isA<RepositoryException>()),
    );
  });

  test('list e search repassam truncated do servidor (padrão false)', () async {
    final repo = _repo([], (c) => switch (c.body['action']) {
          'list' => {
              'folder': {'id': 'r', 'name': 'O', 'parents': []},
              'items': [],
              'truncated': true,
            },
          'search' => {'items': [], 'truncated': true},
          _ => {},
        });
    expect((await repo.list()).truncated, isTrue);
    expect((await repo.search('x')).truncated, isTrue);
    final none = _repo([], (c) => c.body['action'] == 'list' ? {'folder': {'id': 'r', 'name': 'O'}, 'items': []} : {'items': []});
    expect((await none.list()).truncated, isFalse);
    expect((await none.search('x')).truncated, isFalse);
  });

  test('upload só aceita URL de sessão em https://www.googleapis.com (sem usuário, porta ou host parecido)', () async {
    for (final url in [
      'https://storage.googleapis.com/up',
      'https://evilgoogleapis.com/up',
      'https://www.googleapis.com.evil.example/up',
      'http://www.googleapis.com/up',
      'https://user:pw@www.googleapis.com/up',
      'https://www.googleapis.com:8443/up',
    ]) {
      final repo = _repo([], (_) => {'uploadUrl': url});
      await expectLater(
        repo.upload(parentId: 'P', name: 'a', mimeType: 'a/b', size: 1, data: Stream.value([1])),
        throwsA(isA<RepositoryException>()),
        reason: url,
      );
    }
  });

  test('upload: erro de rede não vaza URL nem upload_id na mensagem ao usuário', () async {
    const secret = 'https://www.googleapis.com/upload/drive/v3/files?upload_id=SEGREDO-123';
    final client = MockClient.streaming((req, body) async {
      await body.drain<void>();
      throw http.ClientException('Connection reset by peer', Uri.parse(secret));
    });
    final repo = _repo([], (_) => {'uploadUrl': secret}, client: client);
    final e = await repo.upload(parentId: 'P', name: 'a', mimeType: 'a/b', size: 1, data: Stream.value([1])).then<Object>((_) => 'sem erro', onError: (Object e) => e);
    expect(e, isA<RepositoryException>());
    final msg = (e as RepositoryException).message;
    expect(msg, isNot(contains('SEGREDO')));
    expect(msg, isNot(contains('upload_id')));
    expect(msg, isNot(contains('googleapis')));
    expect(msg, isNot(contains('Connection reset')));
    expect(msg, contains('conexão'));
  });

  final sha = 'a' * 64;

  test('ensurePath manda {action:ensure_path,path} e devolve o folderId', () async {
    final calls = <_Call>[];
    final repo = _repo(calls, (_) => {'folderId': 'F9'});
    expect(await repo.ensurePath(['Organizacional', 'Samsung Notes']), 'F9');
    expect(calls.single.function, 'drive');
    expect(calls.single.body, {
      'action': 'ensure_path',
      'path': ['Organizacional', 'Samsung Notes'],
    });
  });

  test('ensurePath com resposta sem folderId é erro', () async {
    final repo = _repo([], (_) => {});
    await expectLater(repo.ensurePath(['A']), throwsA(isA<RepositoryException>()));
  });

  test('findBySha256 manda {action:find_by_sha256,sha256}; file nulo vira null', () async {
    final calls = <_Call>[];
    final found = _repo(calls, (_) => {
          'file': {'id': 'f1', 'name': 'a.pdf', 'webViewLink': 'https://drive.google.com/file/d/f1/view'},
        });
    final item = await found.findBySha256(sha);
    expect(calls.single.body, {'action': 'find_by_sha256', 'sha256': sha});
    expect(item!.id, 'f1');
    expect(item.name, 'a.pdf');
    expect(item.webViewLink, contains('f1'));
    final none = _repo([], (_) => {'file': null});
    expect(await none.findBySha256(sha), isNull);
  });

  test('upload com appProperties manda no upload_session; sem appProperties o corpo não muda', () async {
    final calls = <_Call>[];
    final client = MockClient.streaming((req, body) async {
      await body.drain<void>();
      return http.StreamedResponse(Stream.value(utf8.encode('{"id":"f1","name":"a.pdf"}')), 200);
    });
    final repo = _repo(calls, (_) => {'uploadUrl': 'https://www.googleapis.com/upload/drive/v3/files?upload_id=X'}, client: client);
    await repo.upload(
      parentId: 'P',
      name: 'a.pdf',
      mimeType: 'application/pdf',
      size: 1,
      data: Stream.value([1]),
      appProperties: {'sha256': sha},
    );
    expect(calls.last.body['appProperties'], {'sha256': sha});
    await repo.upload(parentId: 'P', name: 'a.pdf', mimeType: 'application/pdf', size: 1, data: Stream.value([1]));
    expect(calls.last.body.containsKey('appProperties'), isFalse);
  });
}
