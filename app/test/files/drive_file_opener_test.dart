import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/drive_repository.dart';
import 'package:organizacional/data/memory_drive_repository.dart';
import 'package:organizacional/data/repository.dart';
import 'package:organizacional/domain/drive.dart';
import 'package:organizacional/files/drive_cache.dart';
import 'package:organizacional/files/drive_file_opener.dart';

import 'fakes.dart';

void main() {
  late Directory tmp;
  late String root;
  late FakeFilesPlatform platform;
  late DriveCache cache;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('opener_test');
    root = '${tmp.path}/drive_cache';
    platform = FakeFilesPlatform(root: root);
    cache = DriveCache.at(root);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  DriveFileOpener opener(MemoryDriveRepository drive, {DriveCache? c}) =>
      DriveFileOpener(drive: drive, platform: platform, cache: c ?? cache);

  (MemoryDriveRepository, DriveItem) withFile({String name = 'Edital.pdf', String mime = 'application/pdf', List<int> bytes = const [1, 2, 3]}) {
    final d = MemoryDriveRepository();
    return (d, d.addFile(name, d.rootFolderId, mimeType: mime, bytes: bytes));
  }

  test('primeira abertura: baixa, guarda no cache persistente e abre com o tipo certo', () async {
    final (d, f) = withFile();
    final r = await opener(d).open(f.id);
    expect(r.outcome, OpenOutcome.opened);
    expect(d.downloads, [f.id]);
    expect(platform.opened, hasLength(1));
    expect(platform.opened.single.path, '$root/${f.id}/Edital.pdf');
    expect(platform.opened.single.mime, 'application/pdf');
    expect(File(platform.opened.single.path).readAsBytesSync(), [1, 2, 3]);
  });

  test('segunda abertura com o mesmo md5: abre direto do cache, sem baixar de novo', () async {
    final (d, f) = withFile();
    await opener(d).open(f.id);
    final r = await opener(d).open(f.id);
    expect(r.outcome, OpenOutcome.opened);
    expect(d.downloads, [f.id]);
    expect(d.metaCalls, [f.id, f.id]);
    expect(platform.opened, hasLength(2));
  });

  test('arquivo mudou no Drive: baixa de novo e abre a versão nova', () async {
    final (d, f) = withFile();
    await opener(d).open(f.id);
    d.setContent(f.id, [9, 9, 9, 9]);
    final r = await opener(d).open(f.id);
    expect(r.outcome, OpenOutcome.opened);
    expect(d.downloads, [f.id, f.id]);
    expect(File(platform.opened.last.path).readAsBytesSync(), [9, 9, 9, 9]);
    expect((await cache.lookup(f.id))!.size, 4);
  });

  test('sem rede, com cópia no aparelho: abre a cópia e avisa que pode estar desatualizada', () async {
    final (d, f) = withFile();
    await opener(d).open(f.id);
    d.failActions = true;
    final r = await opener(d).open(f.id);
    expect(r.outcome, OpenOutcome.openedStale);
    expect(r.message, contains('desatualizada'));
    expect(d.downloads, [f.id]);
    expect(platform.opened, hasLength(2));
  });

  test('acesso ao Drive expirado, com cópia no aparelho: também abre a cópia', () async {
    final (d, f) = withFile();
    await opener(d).open(f.id);
    d.authRequired = true;
    final r = await opener(d).open(f.id);
    expect(r.outcome, OpenOutcome.openedStale);
  });

  test('sem rede e sem cópia: falha com a mensagem do erro, nada aberto', () async {
    final (d, f) = withFile();
    d.failActions = true;
    final r = await opener(d).open(f.id);
    expect(r.outcome, OpenOutcome.failed);
    expect(r.message, 'Sem conexão (simulado)');
    expect(platform.opened, isEmpty);
  });

  test('arquivo apagado do Drive (not_found): não abre nem a cópia antiga', () async {
    final (d, f) = withFile();
    await opener(d).open(f.id);
    await d.trash(f.id);
    final r = await opener(d).open(f.id);
    expect(r.outcome, OpenOutcome.failed);
    expect(r.message, 'Item não encontrado no Google Drive.');
    expect(platform.opened, hasLength(1));
  });

  test('.sdocx não tem tratamento especial: tipo opaco, quem abre é o app padrão do sistema', () async {
    final (d, f) = withFile(name: 'Aula.sdocx', mime: 'application/octet-stream');
    final r = await opener(d).open(f.id);
    expect(r.outcome, OpenOutcome.opened);
    expect(platform.opened.single.mime, 'application/octet-stream');
    expect(platform.opened.single.path, '$root/${f.id}/Aula.sdocx');
  });

  test('tipo genérico do Drive: o tipo sai da extensão', () async {
    final (d, f) = withFile(name: 'Trabalho.docx', mime: 'application/octet-stream');
    await opener(d).open(f.id);
    expect(platform.opened.single.mime, 'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
  });

  test('arquivo nativo do Google (Docs, Planilhas): não baixa, pede para abrir no navegador', () async {
    final (d, f) = withFile(name: 'Plano', mime: 'application/vnd.google-apps.document');
    final r = await opener(d).open(f.id);
    expect(r.outcome, OpenOutcome.needsBrowser);
    expect(d.downloads, isEmpty);
    expect(platform.opened, isEmpty);
  });

  test('onDownloading só é chamado quando vai baixar, com o tamanho', () async {
    final (d, f) = withFile();
    final seen = <DriveFileMeta>[];
    await opener(d).open(f.id, onDownloading: seen.add);
    expect(seen.map((m) => m.size), [3]);
    await opener(d).open(f.id, onDownloading: seen.add);
    expect(seen, hasLength(1));
  });

  test('cancelar durante o download: nada é guardado nem aberto', () async {
    final gate = Completer<void>();
    final d = ControlledDrive(gate: gate.future);
    final f = d.addFile('Edital.pdf', d.rootFolderId, bytes: [1, 2, 3]);
    final cancel = OpenCancel();
    final future = opener(d).open(f.id, cancel: cancel, onDownloading: (_) => cancel.cancel());
    gate.complete();
    final r = await future;
    expect(r.outcome, OpenOutcome.cancelled);
    expect(platform.opened, isEmpty);
    expect(await cache.lookup(f.id), isNull);
    expect(await cache.totalBytes(), 0);
  });

  test('download incompleto ou diferente do que o Drive anunciou: erro e nada guardado', () async {
    final d = ControlledDrive(bytesOverride: [1, 2]);
    final f = d.addFile('Edital.pdf', d.rootFolderId, bytes: [1, 2, 3]);
    final r = await opener(d).open(f.id);
    expect(r.outcome, OpenOutcome.failed);
    expect(r.message, contains('incompleto'));
    expect(await cache.lookup(f.id), isNull);

    final same = ControlledDrive(bytesOverride: [1, 2, 4]); // mesmo tamanho, md5 diferente
    final g = same.addFile('Edital.pdf', same.rootFolderId, bytes: [1, 2, 3]);
    final r2 = await opener(same).open(g.id);
    expect(r2.outcome, OpenOutcome.failed);
    expect(await cache.lookup(g.id), isNull);
    expect(platform.opened, isEmpty);
  });

  test('falha no download: com cópia antiga abre a cópia; sem cópia mostra o erro', () async {
    final d = ControlledDrive();
    final f = d.addFile('Edital.pdf', d.rootFolderId, bytes: [1, 2, 3]);
    await opener(d).open(f.id);
    d.setContent(f.id, [4, 5, 6, 7]);
    d.downloadError = const RepositoryException('Falha de conexão. Verifique a internet e tente de novo.');
    final stale = await opener(d).open(f.id);
    expect(stale.outcome, OpenOutcome.openedStale);

    final other = ControlledDrive(downloadError: const DriveException('O arquivo é grande demais para baixar pelo app (máximo de 50 MB). Abra no Google Drive.', code: 'too_large'));
    final big = other.addFile('Grande.pdf', other.rootFolderId, bytes: [1]);
    final r = await opener(other).open(big.id);
    expect(r.outcome, OpenOutcome.failed);
    expect(r.message, contains('50 MB'));
    expect(platform.opened, hasLength(2));
  });

  test('nenhum app abre o arquivo: notOpened, e a cópia continua no aparelho', () async {
    final (d, f) = withFile();
    platform.openResult = false;
    final r = await opener(d).open(f.id);
    expect(r.outcome, OpenOutcome.notOpened);
    expect(await cache.lookup(f.id), isNotNull);
  });

  test('sem pasta para guardar (cache indisponível): falha com mensagem, nada aberto', () async {
    final (d, f) = withFile();
    final r = await opener(d, c: DriveCache.lazy(() async => null)).open(f.id);
    expect(r.outcome, OpenOutcome.failed);
    expect(r.message, 'Não foi possível guardar o arquivo no aparelho.');
    expect(platform.opened, isEmpty);
  });

  test('plataforma sem suporte: falha clara sem baixar nada', () async {
    final (d, f) = withFile();
    platform.supported = false;
    final r = await opener(d).open(f.id);
    expect(r.outcome, OpenOutcome.failed);
    expect(r.message, contains('neste aparelho'));
    expect(d.metaCalls, isEmpty);
  });

  test('abrir marca o último uso (o mais antigo sai primeiro quando passa do limite)', () async {
    final (d, f) = withFile();
    var clock = DateTime.utc(2026, 10, 13, 8);
    final c = DriveCache.at(root, now: () => clock);
    await opener(d, c: c).open(f.id);
    clock = DateTime.utc(2026, 10, 14, 8);
    await opener(d, c: c).open(f.id);
    expect((await c.lookup(f.id))!.lastOpened, DateTime.utc(2026, 10, 14, 8));
  });
}
