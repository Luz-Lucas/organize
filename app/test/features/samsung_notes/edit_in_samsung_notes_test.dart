import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_drive_repository.dart';
import 'package:organizacional/features/samsung_notes/edit_in_samsung_notes.dart';

import 'fakes.dart';

class _Env {
  _Env() {
    editor = SamsungEditor(
      drive: drive,
      platform: platform,
      writeFile: (path, bytes) async => written[path] = List<int>.from(bytes),
    );
    file = drive.addFile('Aula.sdocx', drive.rootFolderId, mimeType: 'application/octet-stream', bytes: [1, 2, 3, 4]);
  }

  final drive = MemoryDriveRepository();
  final platform = FakeSamsungPlatform();
  final written = <String, List<int>>{};
  late final SamsungEditor editor;
  late final dynamic file;

  Future<EditResult> run([String name = 'Aula.sdocx']) => editor.edit(fileId: file.id as String, fileName: name);
}

void main() {
  test('baixa o arquivo, grava na pasta de trabalho e abre no Samsung Notes', () async {
    final e = _Env();
    final r = await e.run();
    expect(r.outcome, EditOutcome.opened);
    expect(e.drive.downloads, [e.file.id]);
    expect(e.written, {'/cache/samsung_open/Aula.sdocx': [1, 2, 3, 4]});
    expect(e.platform.openedFiles, ['/cache/samsung_open/Aula.sdocx']);
  });

  test('falha no download: mensagem clara, nada gravado nem aberto', () async {
    final e = _Env();
    e.drive.authRequired = true;
    final r = await e.run();
    expect(r.outcome, EditOutcome.failed);
    expect(r.message, 'O acesso ao Google Drive expirou. Reconecte em Ajustes.');
    expect(e.written, isEmpty);
    expect(e.platform.openedFiles, isEmpty);

    e.drive.authRequired = false;
    e.drive.failActions = true;
    final r2 = await e.run();
    expect(r2.outcome, EditOutcome.failed);
    expect(r2.message, 'Sem conexão (simulado)');
  });

  test('falha inesperada no download vira mensagem genérica em pt-BR', () async {
    final e = SamsungEditor(drive: _ThrowingDrive(), platform: FakeSamsungPlatform(), writeFile: (p, b) async {});
    final r = await e.edit(fileId: 'x', fileName: 'a.sdocx');
    expect(r.outcome, EditOutcome.failed);
    expect(r.message, 'Não foi possível baixar o arquivo. Tente de novo.');
  });

  test('nenhum app abre o arquivo: notOpened (o app oferece "Abrir no Drive")', () async {
    final e = _Env();
    e.platform.openFileResult = false;
    final r = await e.run();
    expect(r.outcome, EditOutcome.notOpened);
    expect(e.written, hasLength(1));
  });

  test('sem pasta de trabalho ou erro ao gravar: falha com mensagem, sem abrir', () async {
    final e = _Env();
    e.platform.openDirPath = null;
    final r = await e.run();
    expect(r.outcome, EditOutcome.failed);
    expect(r.message, 'Não foi possível guardar o arquivo no aparelho.');
    expect(e.platform.openedFiles, isEmpty);

    final broken = SamsungEditor(
      drive: e.drive,
      platform: FakeSamsungPlatform(),
      writeFile: (p, b) async => throw const FileSystemException('disco cheio'),
    );
    final r2 = await broken.edit(fileId: e.file.id as String, fileName: 'Aula.sdocx');
    expect(r2.outcome, EditOutcome.failed);
    expect(r2.message, 'Não foi possível guardar o arquivo no aparelho.');
  });

  test('o nome do arquivo no disco não escapa da pasta de trabalho', () async {
    final e = _Env();
    await e.run('../../etc/passwd\\x:*?.sdocx');
    final path = e.written.keys.single;
    expect(path.startsWith('/cache/samsung_open/'), isTrue);
    expect(path.substring('/cache/samsung_open/'.length).contains('/'), isFalse);
    expect(path.endsWith('.sdocx'), isTrue);
    expect(path.contains('..'), isFalse);
  });

  test('safeSdocxFileName: troca caracteres perigosos, limita o tamanho e garante .sdocx', () {
    expect(safeSdocxFileName('Aula (2026-10-13).sdocx'), 'Aula (2026-10-13).sdocx');
    expect(safeSdocxFileName('a/b\\c.sdocx'), 'a_b_c.sdocx');
    expect(safeSdocxFileName('.oculto.sdocx'), 'oculto.sdocx');
    expect(safeSdocxFileName('...'), 'nota.sdocx');
    expect(safeSdocxFileName('sem extensao'), 'sem extensao.sdocx');
    expect(safeSdocxFileName('Prova.SDOCX'), 'Prova.SDOCX');
    final long = safeSdocxFileName('${'x' * 300}.sdocx');
    expect(long.length <= 120, isTrue);
    expect(long.endsWith('.sdocx'), isTrue);
  });

  test('writeFileToDisk cria a pasta e grava os bytes', () async {
    final dir = Directory.systemTemp.createTempSync('sdocx_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/sub/Aula.sdocx';
    await writeFileToDisk(path, [5, 6, 7]);
    expect(File(path).readAsBytesSync(), [5, 6, 7]);
  });
}

class _ThrowingDrive extends MemoryDriveRepository {
  @override
  Future<Uint8List> download(String id) async => throw StateError('boom');
}
