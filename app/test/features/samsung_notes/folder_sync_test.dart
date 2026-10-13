import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/drive_repository.dart';
import 'package:organizacional/domain/drive.dart';
import 'package:organizacional/data/memory_imported_files_repository.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/imported_file.dart';
import 'package:organizacional/domain/local_file.dart';
import 'package:organizacional/features/import/importer.dart' show driveLinkInBody;
import 'package:organizacional/features/samsung_notes/folder_sync.dart';
import 'package:organizacional/features/samsung_notes/samsung_folder.dart';

import 'fakes.dart';

final _now = DateTime(2026, 10, 13, 10);
const _folder = SamsungFolder(path: '/storage/emulated/0/Documents/Samsung Notes');

String _sha(List<int> bytes) => sha256.convert(bytes).toString();

class _Env {
  _Env() {
    sync = FolderSync(
      repo: repo,
      drive: drive,
      imported: imported,
      fs: fs,
      now: () => _now,
      device: 'SM-X200',
    );
  }

  final repo = MemoryRepository();
  final drive = CountingDriveRepository();
  final imported = MemoryImportedFilesRepository();
  final fs = FakeFolderFileSystem();
  late final FolderSync sync;

  Future<SyncResult> run() => sync.run(_folder);
}

void main() {
  test('arquivo novo: sobe com appProperties.sha256, cria a nota-link no espaço "Samsung Notes" e registra', () async {
    final e = _Env();
    final bytes = utf8.encode('conteudo do pdf');
    e.fs.put('Aula 1.pdf', bytes);
    final r = await e.run();

    expect(r.uploaded, 1);
    expect(r.errors, isEmpty);
    final up = e.drive.uploads.single;
    expect(up.name, 'Aula 1.pdf');
    expect(up.mimeType, 'application/pdf');
    expect(up.size, bytes.length);
    expect(up.appProperties, {'sha256': _sha(bytes)});
    // Caminho fixo do contrato: Organizacional/Samsung Notes (o servidor resolve a partir do Meu Drive).
    final target = await e.drive.ensurePath(['Organizacional', 'Samsung Notes']);
    expect(up.parentId, target);

    final spaces = await e.repo.watchSpaces().first;
    expect(spaces.single.name, 'Samsung Notes');
    final notes = await e.repo.watchNotes().first;
    expect(notes.single.title, 'Aula 1.pdf');
    expect(notes.single.spaceId, spaces.single.id);
    expect(notes.single.body, startsWith('Arquivo no Google Drive: [Aula 1.pdf](https://drive.example/file/'));

    final rec = e.imported.all.single;
    expect(rec.sha256, _sha(bytes));
    expect(rec.name, 'Aula 1.pdf');
    expect(rec.sizeBytes, bytes.length);
    expect(rec.source, 'samsung_notes');
    expect(rec.driveFileId, isNotNull);
    expect(rec.noteId, notes.single.id);
    expect(rec.device, 'SM-X200');
    expect(e.fs.closed, 1);
  });

  test('o espaço "Samsung Notes" é reaproveitado, não duplicado', () async {
    final e = _Env();
    e.fs.put('a.pdf', [1, 2, 3, 4]);
    await e.run();
    e.fs.put('b.pdf', [5, 6, 7, 8]);
    await e.run();
    expect((await e.repo.watchSpaces().first), hasLength(1));
    expect((await e.repo.watchNotes().first), hasLength(2));
  });

  test('mesmo sha já registrado: pula sem subir nem criar nota', () async {
    final e = _Env();
    final bytes = [9, 9, 9, 9];
    await e.imported.record(ImportedFile(sha256: _sha(bytes), name: 'Antigo.pdf', sizeBytes: 4));
    e.fs.put('Copia.pdf', bytes);
    final r = await e.run();
    expect(r.uploaded, 0);
    expect(r.skipped, 1);
    expect(e.drive.uploads, isEmpty);
    expect(e.drive.findCalls, 0, reason: 'já registrado: nem consulta o Drive');
    expect(await e.repo.watchNotes().first, isEmpty);
  });

  test('existe só no Drive (outro aparelho caiu no meio): pula o envio e registra a linha', () async {
    final e = _Env();
    final bytes = [1, 1, 2, 2, 3];
    final onDrive = e.drive.addFile('Aula.pdf', e.drive.rootFolderId);
    // simula o arquivo já enviado com o sha nas propriedades
    await e.drive.upload(
      parentId: e.drive.rootFolderId,
      name: 'Aula.pdf',
      mimeType: 'application/pdf',
      size: bytes.length,
      data: Stream.value(bytes),
      appProperties: {'sha256': _sha(bytes)},
    );
    e.drive.uploads.clear();
    expect(onDrive.id, isNotEmpty);
    e.fs.put('Aula.pdf', bytes);

    final r = await e.run();
    expect(r.uploaded, 0);
    expect(r.skipped, 1);
    expect(e.drive.uploads, isEmpty);
    expect(e.imported.all.single.sha256, _sha(bytes));
    expect(e.imported.all.single.driveFileId, isNotNull);
  });

  test('.sdocx sobe como application/octet-stream, com sha256, e ganha nota-link (mesmo fluxo dos PDFs)', () async {
    final e = _Env();
    final bytes = utf8.encode('conteudo de uma nota editavel');
    e.fs.put('Aula 2.sdocx', bytes);
    final r = await e.run();

    expect(r.uploaded, 1);
    expect(r.ignored, 0);
    expect(r.errors, isEmpty);
    final up = e.drive.uploads.single;
    expect(up.name, 'Aula 2.sdocx');
    expect(up.mimeType, 'application/octet-stream');
    expect(up.appProperties, {'sha256': _sha(bytes)});
    final note = (await e.repo.watchNotes().first).single;
    expect(note.title, 'Aula 2.sdocx');
    expect(driveLinkInBody(note.body), isNotNull);
    expect(e.imported.all.single.name, 'Aula 2.sdocx');
    expect(e.imported.all.single.noteId, note.id);

    // Segunda rodada: mesmo conteúdo, nada novo.
    final r2 = await e.run();
    expect(r2.uploaded, 0);
    expect(r2.skipped, 1);
  });

  test('formatos não suportados (xlsx, zip...) continuam ignorados, sem ler o arquivo', () async {
    final e = _Env();
    e.fs.put('Planilha.xlsx', [1, 2, 3]);
    e.fs.put('Pacote.zip', [1, 2, 3]);
    e.fs.put('Ok.pdf', [4, 5, 6]);
    final r = await e.run();
    expect(r.ignored, 2);
    expect(r.uploaded, 1);
    expect(e.fs.opened, ['Ok.pdf']);
  });

  test('extensões aceitas: pdf docx doc txt md png jpg jpeg sdocx (qualquer caixa)', () {
    for (final n in ['a.pdf', 'a.DOCX', 'a.doc', 'a.txt', 'a.md', 'a.png', 'a.jpg', 'a.JPEG', 'a.sdocx', 'a.SDOCX']) {
      expect(isSyncableName(n), isTrue, reason: n);
    }
    for (final n in ['a.zip', 'semextensao', '.pdf.tmp', '.a.sdocx', 'a.gif', 'a.sdocx.tmp']) {
      expect(isSyncableName(n), isFalse, reason: n);
    }
  });

  test('mimeForFileName: .sdocx é application/octet-stream (o servidor recusa curingas e tipos nativos do Google)', () {
    final mime = mimeForFileName('Nota.SDOCX');
    expect(mime, 'application/octet-stream');
    expect(mime.contains('*'), isFalse);
    expect(mime.startsWith('application/vnd.google-apps.'), isFalse);
  });

  test('erro no upload não grava registro; a próxima rodada tenta de novo', () async {
    final e = _Env();
    e.fs.put('Aula.pdf', [1, 2, 3, 4]);
    e.drive.failUploads = true;
    final r1 = await e.run();
    expect(r1.uploaded, 0);
    expect(r1.errors, hasLength(1));
    expect(r1.errors.single, startsWith('Aula.pdf:'));
    expect(e.imported.all, isEmpty);
    expect(await e.repo.watchNotes().first, isEmpty);
    expect(e.fs.closed, 1, reason: 'fecha a origem mesmo com erro');

    e.drive.failUploads = false;
    final r2 = await e.run();
    expect(r2.uploaded, 1);
    expect(r2.errors, isEmpty);
    expect(e.imported.all, hasLength(1));
  });

  test('erro de um arquivo não interrompe os outros', () async {
    final e = _Env();
    e.fs.put('a.pdf', [1, 2, 3]);
    e.fs.put('b.pdf', [4, 5, 6]);
    final flaky = _FlakyDrive(failFirst: true);
    final sync = FolderSync(repo: e.repo, drive: flaky, imported: e.imported, fs: e.fs, now: () => _now);
    final r = await sync.run(_folder);
    expect(r.errors, hasLength(1));
    expect(r.uploaded, 1);
    expect(flaky.uploads, hasLength(1));
  });

  test('.txt de até 1 MB vira nota com o texto E sobe ao Drive', () async {
    final e = _Env();
    e.fs.put('Ideias.txt', utf8.encode('Primeira linha\n- item\nSegunda'));
    final r = await e.run();
    expect(r.uploaded, 1);
    final up = e.drive.uploads.single;
    expect(up.name, 'Ideias.txt');
    expect(up.mimeType, 'text/plain');
    final note = (await e.repo.watchNotes().first).single;
    expect(note.title, 'Ideias');
    expect(note.body, contains('Primeira linha'));
    expect(note.body, contains(r'\- item'), reason: 'marca de lista escapada, como na importação');
    expect(note.body, contains('Arquivo no Google Drive: [Ideias.txt]('));
    expect(e.imported.all.single.noteId, note.id);
  });

  test('.md mantém o Markdown original na nota', () async {
    final e = _Env();
    e.fs.put('Resumo.md', utf8.encode('# Título\n\n- a\n- b\n'));
    await e.run();
    final note = (await e.repo.watchNotes().first).single;
    expect(note.title, 'Resumo');
    expect(note.body, startsWith('# Título\n\n- a\n- b'));
  });

  test('.txt acima de 1 MB não vira texto: só nota-link', () async {
    final e = _Env();
    e.fs.put('Grande.txt', List.filled(1024 * 1024 + 1, 65));
    await e.run();
    final note = (await e.repo.watchNotes().first).single;
    expect(note.title, 'Grande.txt');
    expect(note.body, startsWith('Arquivo no Google Drive: [Grande.txt]('));
    expect(e.drive.uploads, hasLength(1));
  });

  test('mesmo nome com outro conteúdo é versão nova: título e arquivo ganham a data', () async {
    final e = _Env();
    e.fs.put('Aula.pdf', [1, 2, 3, 4]);
    await e.run();
    e.fs.put('Aula.pdf', [1, 2, 3, 4, 5]);
    final r = await e.run();
    expect(r.uploaded, 1);
    expect(e.drive.uploads.map((u) => u.name), ['Aula.pdf', 'Aula (2026-10-13).pdf']);
    final titles = (await e.repo.watchNotes().first).map((n) => n.title).toSet();
    expect(titles, {'Aula.pdf', 'Aula (2026-10-13).pdf'});
    expect(e.imported.all.map((f) => f.name), ['Aula.pdf', 'Aula.pdf']);
  });

  test('dois arquivos com o mesmo conteúdo na mesma rodada sobem uma vez só', () async {
    final e = _Env();
    e.fs.put('a.pdf', [7, 7, 7, 7]);
    e.fs.put('b.pdf', [7, 7, 7, 7]);
    final r = await e.run();
    expect(r.uploaded, 1);
    expect(r.skipped, 1);
    expect(e.drive.uploads, hasLength(1));
  });

  test('o caminho no Drive é resolvido uma vez por rodada', () async {
    final e = _Env();
    e.fs.put('a.pdf', [1, 2, 3]);
    e.fs.put('b.pdf', [4, 5, 6]);
    e.fs.put('c.pdf', [7, 8, 9]);
    await e.run();
    expect(e.drive.ensurePathCalls, 1);
  });

  test('arquivo recém-modificado (ainda sendo gravado) fica para a próxima rodada', () async {
    final e = _Env();
    e.fs.put('Gravando.pdf', [1, 2, 3], modified: _now.subtract(const Duration(seconds: 3)));
    e.fs.put('Pronto.pdf', [4, 5, 6], modified: _now.subtract(const Duration(minutes: 1)));
    final r = await e.run();
    expect(r.uploaded, 1);
    expect(r.pending, 1);
    expect(e.drive.uploads.single.name, 'Pronto.pdf');
  });

  test('arquivo acima do teto de envio é ignorado', () async {
    final e = _Env();
    final sync = FolderSync(
      repo: e.repo,
      drive: e.drive,
      imported: e.imported,
      fs: e.fs,
      now: () => _now,
      maxFileBytes: 5,
    );
    e.fs.put('Enorme.pdf', [1, 2, 3, 4, 5, 6]);
    final r = await sync.run(_folder);
    expect(r.ignored, 1);
    expect(r.uploaded, 0);
  });

  test('acesso ao Drive expirado interrompe a rodada e sinaliza reconexão', () async {
    final e = _Env();
    e.fs.put('a.pdf', [1, 2, 3]);
    e.fs.put('b.pdf', [4, 5, 6]);
    e.drive.uploadError = const DriveException('expirou', code: 'auth_required');
    final r = await e.run();
    expect(r.needsReconnect, isTrue);
    expect(e.fs.opened, ['a.pdf'], reason: 'não insiste nos outros arquivos');
    expect(e.imported.all, isEmpty);
  });

  test('pasta ilegível vira erro da rodada, sem exceção', () async {
    final e = _Env();
    e.fs.listError = const FolderAccessException('Sem acesso à pasta.');
    final r = await e.run();
    expect(r.errors.single, 'Sem acesso à pasta.');
    expect(r.uploaded, 0);
  });

  test('SyncResult.text resume: "12 enviados, 2 ignorados" (+ erros)', () {
    final r = SyncResult()
      ..uploaded = 12
      ..ignored = 2;
    expect(r.text, '12 enviados, 2 ignorados');
    r.errors.add('x');
    expect(r.text, '12 enviados, 2 ignorados, 1 com erro');
    expect((SyncResult()..uploaded = 1).text, '1 enviado, 0 ignorados');
  });

  test('sem nenhum arquivo, nada é criado (nem o espaço nem a pasta no Drive)', () async {
    final e = _Env();
    final r = await e.run();
    expect(r.uploaded, 0);
    expect(await e.repo.watchSpaces().first, isEmpty);
    expect(e.drive.ensurePathCalls, 0);
  });
}

class _FlakyDrive extends CountingDriveRepository {
  _FlakyDrive({required this.failFirst});

  final bool failFirst;
  bool _failed = false;

  @override
  Future<UploadedFile> upload({
    required String parentId,
    required String name,
    required String mimeType,
    required int size,
    required Stream<List<int>> data,
    void Function(int sent, int total)? onProgress,
    Map<String, String>? appProperties,
  }) {
    if (failFirst && !_failed) {
      _failed = true;
      throw StateError('primeira falha');
    }
    return super.upload(
      parentId: parentId,
      name: name,
      mimeType: mimeType,
      size: size,
      data: data,
      onProgress: onProgress,
      appProperties: appProperties,
    );
  }
}
