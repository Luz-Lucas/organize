import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/drive_repository.dart';
import 'package:organizacional/data/memory_drive_repository.dart';
import 'package:organizacional/data/repository.dart';
import 'package:organizacional/domain/drive.dart';

void main() {
  test('list sem pasta abre a raiz Organizacional; "root" abre o Meu Drive', () async {
    final repo = MemoryDriveRepository();
    final org = await repo.list();
    expect(org.folder.name, 'Organizacional');
    expect(org.folder.id, repo.rootFolderId);
    final my = await repo.list(folderId: 'root');
    expect(my.folder.name, 'Meu Drive');
    expect(my.items.map((i) => i.name), contains('Organizacional'));
  });

  test('pastas primeiro, depois nome ascendente; lixeira não aparece', () async {
    final repo = MemoryDriveRepository();
    final root = repo.rootFolderId;
    repo.addFile('b.txt', root);
    repo.addFolder('Zeta', root);
    repo.addFile('a.txt', root);
    final gone = repo.addFile('c.txt', root);
    repo.addFolder('Alfa', root);
    await repo.trash(gone.id);
    final names = (await repo.list()).items.map((i) => i.name).toList();
    expect(names, ['Alfa', 'Zeta', 'a.txt', 'b.txt']);
    await repo.restore(gone.id);
    expect((await repo.list()).items.map((i) => i.name), contains('c.txt'));
  });

  test('createFolder, ensureFolder (idempotente), rename e move', () async {
    final repo = MemoryDriveRepository();
    final root = repo.rootFolderId;
    final a = await repo.createFolder(root, 'Provas');
    expect(a.isFolder, isTrue);
    final again = await repo.ensureFolder(root, 'Provas');
    expect(again.id, a.id);
    final novo = await repo.ensureFolder(root, 'Importados');
    expect(novo.id, isNot(a.id));
    final f = repo.addFile('x.pdf', root);
    await repo.rename(f.id, 'y.pdf');
    await repo.move(f.id, a.id);
    expect((await repo.list(folderId: a.id)).items.single.name, 'y.pdf');
    expect((await repo.list()).items.map((i) => i.name), isNot(contains('y.pdf')));
    expect((await repo.list(folderId: a.id)).folder.parents, [root]);
  });

  test('search acha por parte do nome sem diferenciar maiúsculas e ignora lixeira', () async {
    final repo = MemoryDriveRepository();
    final root = repo.rootFolderId;
    repo.addFile('Edital Concurso.pdf', root);
    final t = repo.addFile('edital velho.pdf', root);
    repo.addFile('outro.txt', root);
    await repo.trash(t.id);
    expect((await repo.search('EDITAL')).items.map((i) => i.name), ['Edital Concurso.pdf']);
  });

  test('compartilhar: link público liga/desliga e convites aparecem em permissions', () async {
    final repo = MemoryDriveRepository();
    final f = repo.addFile('x.pdf', repo.rootFolderId);
    final link = await repo.setLinkSharing(f.id, true);
    expect(link, isNotNull);
    await repo.share(f.id, 'amiga@exemplo.com', DriveRole.writer);
    var perms = await repo.permissions(f.id);
    expect(perms.any((p) => p.isAnyone), isTrue);
    final invited = perms.firstWhere((p) => p.email == 'amiga@exemplo.com');
    expect(invited.role, 'writer');
    await repo.unshare(f.id, invited.id);
    await repo.setLinkSharing(f.id, false);
    perms = await repo.permissions(f.id);
    expect(perms.where((p) => !p.isOwner), isEmpty);
  });

  test('upload registra a chamada, cria o arquivo e reporta progresso', () async {
    final repo = MemoryDriveRepository();
    final progress = <int>[];
    final up = await repo.upload(
      parentId: repo.rootFolderId,
      name: 'Aula.pdf',
      mimeType: 'application/pdf',
      size: 10,
      data: Stream.value([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
      onProgress: (sent, total) => progress.add(sent),
    );
    expect(up.name, 'Aula.pdf');
    expect(up.webViewLink, startsWith('https://'));
    expect(repo.uploads.single.name, 'Aula.pdf');
    expect(progress.last, 10);
    expect((await repo.list()).items.single.name, 'Aula.pdf');
  });

  test('watchState reflete disconnect e falhas simuladas viram RepositoryException', () async {
    final repo = MemoryDriveRepository();
    expect((await repo.watchState().first)?.status, DriveStatus.ok);
    await repo.disconnect();
    expect((await repo.watchState().first)?.status, DriveStatus.notConnected);
    expect(repo.disconnectCalls, 1);
    repo.failActions = true;
    expect(() => repo.list(), throwsA(isA<RepositoryException>()));
    expect(() => repo.connectUrl(), throwsA(isA<RepositoryException>()));
  });

  test('modo auth_required faz as chamadas falharem com código auth_required', () async {
    final repo = MemoryDriveRepository(state: const DriveState(status: DriveStatus.authRequired, rootFolderId: 'r'));
    repo.authRequired = true;
    await expectLater(
      repo.list(),
      throwsA(isA<DriveException>().having((e) => e.code, 'code', 'auth_required')),
    );
  });

  test('itemLimit corta list e search e marca truncated', () async {
    final repo = MemoryDriveRepository()..itemLimit = 2;
    for (var i = 0; i < 5; i++) {
      repo.addFile('arq $i.pdf', repo.rootFolderId);
    }
    final l = await repo.list();
    expect(l.items.length, 2);
    expect(l.truncated, isTrue);
    final s = await repo.search('arq');
    expect(s.items.length, 2);
    expect(s.truncated, isTrue);
    repo.itemLimit = null;
    expect((await repo.list()).truncated, isFalse);
    expect((await repo.search('arq')).truncated, isFalse);
  });

  test('ensurePath cria cada nível a partir do Meu Drive e reaproveita o que existe', () async {
    final repo = MemoryDriveRepository();
    final id = await repo.ensurePath(['Organizacional', 'Samsung Notes']);
    final again = await repo.ensurePath(['Organizacional', 'Samsung Notes']);
    expect(again, id);
    // "Organizacional" já existia (a raiz) e foi reaproveitada, não duplicada.
    final my = await repo.list(folderId: 'root');
    expect(my.items.where((i) => i.name == 'Organizacional'), hasLength(1));
    final org = await repo.list();
    expect(org.items.map((i) => i.name), contains('Samsung Notes'));
    final other = await repo.ensurePath(['Outra', 'Pasta']);
    expect(other, isNot(id));
  });

  test('upload guarda o sha256 de appProperties e findBySha256 acha (e ignora a lixeira)', () async {
    final repo = MemoryDriveRepository();
    final sha = 'b' * 64;
    expect(await repo.findBySha256(sha), isNull);
    final up = await repo.upload(
      parentId: repo.rootFolderId,
      name: 'a.pdf',
      mimeType: 'application/pdf',
      size: 2,
      data: Stream.value([1, 2]),
      appProperties: {'sha256': sha},
    );
    expect(repo.uploads.single.appProperties, {'sha256': sha});
    expect((await repo.findBySha256(sha))!.id, up.id);
    await repo.trash(up.id);
    expect(await repo.findBySha256(sha), isNull);
  });
}
