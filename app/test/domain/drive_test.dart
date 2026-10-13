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

  test('LocalFile lê bytes em memória', () async {
    final f = LocalFile.memory(name: 'a.txt', bytes: [104, 105]);
    expect(f.size, 2);
    expect(await f.readAsString(), 'hi');
    expect((await f.openRead().toList()).expand((e) => e).toList(), [104, 105]);
    expect(f.mimeType, 'text/plain');
  });
}
