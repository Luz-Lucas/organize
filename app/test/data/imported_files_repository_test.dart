import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:organizacional/data/memory_imported_files_repository.dart';
import 'package:organizacional/data/repository.dart';
import 'package:organizacional/data/supabase_imported_files_repository.dart';
import 'package:organizacional/domain/imported_file.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _sha = 'c' * 64;

class _Sent {
  _Sent(this.method, this.url, this.prefer, this.body);
  final String method;
  final Uri url;
  final String? prefer;
  final Object? body;
}

SupabaseClient _client(List<_Sent> sent, {int status = 200, String reply = '[]'}) {
  final mock = MockClient((http.Request req) async {
    sent.add(_Sent(req.method, req.url, req.headers['Prefer'], req.body.isEmpty ? null : jsonDecode(req.body)));
    return http.Response(reply, status, request: req, headers: {'content-type': 'application/json'});
  });
  return SupabaseClient('http://localhost:54321', 'anon', httpClient: mock);
}

void main() {
  group('ImportedFile', () {
    test('toMap usa as colunas do contrato (sem user_id: o servidor preenche)', () {
      final f = ImportedFile(
        sha256: _sha,
        name: 'Aula.pdf',
        sizeBytes: 12,
        driveFileId: 'd1',
        noteId: 'n1',
        device: 'SM-X200',
      );
      expect(f.toMap(), {
        'sha256': _sha,
        'name': 'Aula.pdf',
        'size_bytes': 12,
        'source': 'samsung_notes',
        'drive_file_id': 'd1',
        'note_id': 'n1',
        'device': 'SM-X200',
      });
    });

    test('hash fora do formato (64 hex minúsculos) é recusado', () {
      expect(isValidSha256(_sha), isTrue);
      expect(isValidSha256('A' * 64), isFalse);
      expect(isValidSha256('a' * 63), isFalse);
      expect(isValidSha256('g' * 64), isFalse);
    });
  });

  group('MemoryImportedFilesRepository', () {
    test('has/hasName e record idempotente (o primeiro registro vence)', () async {
      final repo = MemoryImportedFilesRepository();
      expect(await repo.has(_sha), isFalse);
      await repo.record(ImportedFile(sha256: _sha, name: 'A.pdf', sizeBytes: 1, driveFileId: 'd1'));
      await repo.record(ImportedFile(sha256: _sha, name: 'B.pdf', sizeBytes: 2, driveFileId: 'd2'));
      expect(await repo.has(_sha), isTrue);
      expect(await repo.hasName('A.pdf'), isTrue);
      expect(await repo.hasName('B.pdf'), isFalse);
      expect(repo.all.single.driveFileId, 'd1');
    });

    test('falhas simuladas viram RepositoryException', () async {
      final repo = MemoryImportedFilesRepository()..fail = true;
      await expectLater(repo.has(_sha), throwsA(isA<RepositoryException>()));
      await expectLater(repo.record(ImportedFile(sha256: _sha, name: 'A', sizeBytes: 1)), throwsA(isA<RepositoryException>()));
    });
  });

  group('SupabaseImportedFilesRepository', () {
    test('has consulta imported_files pelo sha256', () async {
      final sent = <_Sent>[];
      final yes = SupabaseImportedFilesRepository(_client(sent, reply: '[{"sha256":"$_sha"}]'));
      expect(await yes.has(_sha), isTrue);
      expect(sent.single.method, 'GET');
      expect(sent.single.url.path, '/rest/v1/imported_files');
      expect(sent.single.url.queryParameters['sha256'], 'eq.$_sha');
      final no = SupabaseImportedFilesRepository(_client([], reply: '[]'));
      expect(await no.has(_sha), isFalse);
    });

    test('hasName consulta pelo nome e pela origem', () async {
      final sent = <_Sent>[];
      final repo = SupabaseImportedFilesRepository(_client(sent, reply: '[{"sha256":"$_sha"}]'));
      expect(await repo.hasName('Aula.pdf'), isTrue);
      expect(sent.single.url.queryParameters['name'], 'eq.Aula.pdf');
      expect(sent.single.url.queryParameters['source'], 'eq.samsung_notes');
    });

    test('record faz insert ignorando duplicata por (user_id, sha256)', () async {
      final sent = <_Sent>[];
      final repo = SupabaseImportedFilesRepository(_client(sent, status: 201));
      await repo.record(ImportedFile(sha256: _sha, name: 'Aula.pdf', sizeBytes: 5, driveFileId: 'd1'));
      expect(sent.single.method, 'POST');
      expect(sent.single.url.path, '/rest/v1/imported_files');
      expect(sent.single.url.queryParameters['on_conflict'], 'user_id,sha256');
      expect(sent.single.prefer, contains('resolution=ignore-duplicates'));
      expect((sent.single.body as Map)['sha256'], _sha);
      expect((sent.single.body as Map).containsKey('user_id'), isFalse);
    });

    test('erro do servidor vira RepositoryException', () async {
      final repo = SupabaseImportedFilesRepository(_client([], status: 403, reply: '{"message":"negado","code":"42501"}'));
      await expectLater(repo.has(_sha), throwsA(isA<RepositoryException>()));
      await expectLater(
        repo.record(ImportedFile(sha256: _sha, name: 'A', sizeBytes: 1)),
        throwsA(isA<RepositoryException>()),
      );
    });
  });
}
