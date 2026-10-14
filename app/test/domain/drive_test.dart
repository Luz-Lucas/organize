import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/domain/drive.dart';
import 'package:organizacional/domain/local_file.dart';

void main() {
  test('DriveState.fromMap e status desconhecido', () {
    final s = DriveState.fromMap({
      'account_email': 'a@b.c',
      'status': 'ok',
      'root_folder_id': 'pasta1',
      'message': null,
    });
    expect(s.status, DriveStatus.ok);
    expect(s.rootFolderId, 'pasta1');
    expect(s.connected, isTrue);
    expect(DriveState.fromMap({'status': 'qualquer'}).status, DriveStatus.notConnected);
    expect(DriveState.fromMap({'status': 'auth_required'}).connected, isTrue);
    expect(const DriveState().connected, isFalse);
  });

  test('DriveItem.fromMap lê pasta, arquivo, tamanho e data', () {
    final f = DriveItem.fromMap({
      'id': 'a1',
      'name': 'Edital.pdf',
      'mimeType': 'application/pdf',
      'isFolder': false,
      'size': 2048,
      'modifiedTime': '2026-10-01T10:00:00Z',
      'webViewLink': 'https://drive.google.com/file/d/a1/view',
      'shared': true,
    });
    expect(f.isFolder, isFalse);
    expect(f.size, 2048);
    expect(f.shared, isTrue);
    expect(f.modifiedTime, isNotNull);
    final d = DriveItem.fromMap({'id': 'p', 'name': 'Provas', 'mimeType': 'application/vnd.google-apps.folder', 'isFolder': true});
    expect(d.isFolder, isTrue);
    expect(d.size, isNull);
    expect(d.shared, isFalse);
  });

  test('DrivePermission: dono, link público e rótulo do papel', () {
    final owner = DrivePermission.fromMap({'id': 'o', 'email': 'eu@g.com', 'role': 'owner', 'type': 'user'});
    expect(owner.isOwner, isTrue);
    expect(owner.roleLabel, 'Dono');
    final pub = DrivePermission.fromMap({'id': 'p', 'email': null, 'role': 'reader', 'type': 'anyone'});
    expect(pub.isAnyone, isTrue);
    expect(DrivePermission.fromMap({'id': 'x', 'role': 'writer', 'type': 'user'}).roleLabel, 'Editor');
    expect(DriveRole.reader.label, 'Leitor');
    expect(DriveRole.commenter.wire, 'commenter');
  });

  test('formatBytes em português', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(900), '900 B');
    expect(formatBytes(2048), '2,0 KB');
    expect(formatBytes(5 * 1024 * 1024 + 300 * 1024), '5,3 MB');
    expect(formatBytes(3 * 1024 * 1024 * 1024), '3,0 GB');
  });

  test('mimeForFileName e classificação de texto', () {
    expect(mimeForFileName('Aula 3.PDF'), 'application/pdf');
    expect(mimeForFileName('a.docx'), 'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
    expect(mimeForFileName('foto.JPG'), 'image/jpeg');
    expect(mimeForFileName('sem-extensao'), 'application/octet-stream');
    expect(isTextFileName('notas.txt'), isTrue);
    expect(isTextFileName('LEIA.md'), isTrue);
    expect(isTextFileName('a.pdf'), isFalse);
  });

  test('texto grande (> 1 MB) não vira nota: vai para o Drive', () {
    const mb = 1024 * 1024;
    expect(LocalFile(name: 'a.txt', size: mb).becomesNote, isTrue);
    expect(LocalFile(name: 'a.md', size: mb + 1).becomesNote, isFalse);
    expect(LocalFile(name: 'a.txt', size: 0).becomesNote, isTrue);
    expect(LocalFile(name: 'a.pdf', size: 10).becomesNote, isFalse);
    expect(LocalFile.memory(name: 'x.txt', bytes: List.filled(mb + 1, 97)).becomesNote, isFalse);
    expect(maxNoteTextBytes, mb);
  });

  test('LocalFile lê bytes em memória', () async {
    final f = LocalFile.memory(name: 'a.txt', bytes: [104, 105]);
    expect(f.size, 2);
    expect(await f.readAsString(), 'hi');
    expect((await f.openRead().toList()).expand((e) => e).toList(), [104, 105]);
    expect(f.mimeType, 'text/plain');
  });

  group('DriveFileMeta', () {
    test('fromMap lê data, tamanho e md5', () {
      final m = DriveFileMeta.fromMap({
        'id': 'f1',
        'name': 'Edital.pdf',
        'mimeType': 'application/pdf',
        'size': 2048,
        'modifiedTime': '2026-10-12T09:00:00.000Z',
        'md5Checksum': 'D41D8CD98F00B204E9800998ECF8427E',
        'webViewLink': 'https://drive.google.com/file/d/f1/view',
      });
      expect(m.id, 'f1');
      expect(m.size, 2048);
      expect(m.md5, 'd41d8cd98f00b204e9800998ecf8427e');
      expect(m.modifiedTime!.toUtc(), DateTime.utc(2026, 10, 12, 9));
      expect(m.isGoogleNative, isFalse);
    });

    test('arquivo nativo do Google não tem md5 nem tamanho e não baixa', () {
      final m = DriveFileMeta.fromMap({'id': 'd', 'name': 'Doc', 'mimeType': 'application/vnd.google-apps.document'});
      expect(m.md5, isNull);
      expect(m.size, isNull);
      expect(m.isGoogleNative, isTrue);
    });

    test('sameContentAs: md5 vale quando os dois têm; senão data e tamanho', () {
      DriveFileMeta m({String? md5, int? size = 10, DateTime? at}) =>
          DriveFileMeta(id: 'f', name: 'a', mimeType: 'x/y', size: size, modifiedTime: at, md5: md5);
      final t = DateTime.utc(2026, 10, 12);
      expect(m(md5: 'aa').sameContentAs(m(md5: 'aa', at: DateTime.utc(2030))), isTrue);
      expect(m(md5: 'aa').sameContentAs(m(md5: 'bb')), isFalse);
      expect(m(at: t).sameContentAs(m(at: t)), isTrue);
      expect(m(at: t).sameContentAs(m(at: t.add(const Duration(seconds: 1)))), isFalse);
      expect(m(at: t, size: 10).sameContentAs(m(at: t, size: 11)), isFalse);
      // md5 de um lado só: cai para data + tamanho
      expect(m(md5: 'aa', at: t).sameContentAs(m(at: t)), isTrue);
      // sem nenhuma informação não dá para afirmar que é igual
      expect(m(size: null).sameContentAs(m(size: null)), isFalse);
    });
  });
}
