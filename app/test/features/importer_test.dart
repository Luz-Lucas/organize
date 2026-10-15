import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_drive_repository.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/drive.dart';
import 'package:organizacional/domain/local_file.dart';
import 'package:organizacional/domain/note.dart';
import 'package:organizacional/features/import/importer.dart';

Future<List<Note>> _notes(MemoryRepository r) => r.watchNotes().first;

Importer _importer(MemoryRepository repo, MemoryDriveRepository drive, {DriveState? state}) => Importer(
      repo: repo,
      drive: drive,
      driveState: state ?? const DriveState(status: DriveStatus.ok, rootFolderId: 'org-root'),
    );

void main() {
  group('splitSharedText', () {
    test('título = primeira linha, corpo = resto', () {
      final (title, body) = splitSharedText('Lista de compras\nleite\novo');
      expect(title, 'Lista de compras');
      expect(body, 'leite\n\novo');
    });

    test('primeira linha longa é cortada em 80 e o resto continua no corpo', () {
      final long = 'a' * 100;
      final (title, body) = splitSharedText('$long\noutra');
      expect(title.length, 80);
      expect(body, '${'a' * 20}\n\noutra');
    });

    test('ignora linhas em branco no início; texto vazio vira título padrão', () {
      expect(splitSharedText('\n\n  Oi  \nfim').$1, 'Oi');
      expect(splitSharedText('   \n ').$1, 'Nota importada');
      expect(splitSharedText('só uma linha').$2, '');
    });
  });

  test('plainTextToMarkdown escapa início de bloco e separa linhas em parágrafos', () {
    expect(plainTextToMarkdown('# não é título\n- nem lista\n1. nem item\n> nem citação'),
        '\\# não é título\n\n\\- nem lista\n\n1\\. nem item\n\n\\> nem citação');
    expect(plainTextToMarkdown('a\r\n\r\n\r\nb'), 'a\n\nb');
  });

  test('saveText cria a nota no espaço "Importadas" (criado se faltar, reaproveitado depois)', () async {
    final repo = MemoryRepository();
    final imp = _importer(repo, MemoryDriveRepository());
    final n1 = await imp.saveText('Reunião\nPauta do dia');
    final n2 = await imp.saveText('Outra\ncoisa');
    final spaces = await repo.watchSpaces().first;
    expect(spaces.where((s) => s.name == 'Importadas').length, 1);
    expect(n1.spaceId, spaces.single.id);
    expect(n2.spaceId, n1.spaceId);
    final notes = await _notes(repo);
    expect(notes.firstWhere((n) => n.id == n1.id).title, 'Reunião');
    expect(notes.firstWhere((n) => n.id == n1.id).body, 'Pauta do dia');
  });

  test('saveText respeita um espaço escolhido e deixa o título único', () async {
    final repo = MemoryRepository();
    final imp = _importer(repo, MemoryDriveRepository());
    await imp.saveText('Ideia\num', spaceId: null);
    final n = await imp.saveText('Ideia\ndois');
    expect(n.title, 'Ideia 2');
  });

  test('importFiles: .txt e .md viram notas; pdf vai ao Drive em Organize/Importados com nota-link', () async {
    final repo = MemoryRepository();
    final drive = MemoryDriveRepository();
    final imp = _importer(repo, drive);
    final summary = await imp.importFiles([
      LocalFile.memory(name: 'resumo.txt', bytes: 'Linha 1\nLinha 2'.codeUnits),
      LocalFile.memory(name: 'guia.md', bytes: '# Guia\n\n- item'.codeUnits),
      LocalFile.memory(name: 'Edital.pdf', bytes: [1, 2, 3]),
      LocalFile.memory(name: 'foto.jpg', bytes: [4, 5]),
    ]);
    expect(summary.notes, 4);
    expect(summary.files, 2);
    expect(summary.errors, isEmpty);
    expect(summary.text, '4 notas criadas, 2 arquivos enviados');

    final notes = await _notes(repo);
    expect(notes.firstWhere((n) => n.title == 'resumo').body, 'Linha 1\n\nLinha 2');
    expect(notes.firstWhere((n) => n.title == 'guia').body, '# Guia\n\n- item');
    final pdfNote = notes.firstWhere((n) => n.title == 'Edital.pdf');
    expect(pdfNote.body, contains('[Edital.pdf](https://drive.example/'));

    expect(drive.uploads.map((u) => u.name), ['Edital.pdf', 'foto.jpg']);
    final importados = (await drive.list()).items.singleWhere((i) => i.name == 'Importados');
    expect(importados.isFolder, isTrue);
    expect(drive.uploads.every((u) => u.parentId == importados.id), isTrue);
    expect(drive.uploads.first.mimeType, 'application/pdf');
  });

  test('sem Drive conectado: arquivos que precisam do Drive dão erro, texto continua', () async {
    final repo = MemoryRepository();
    final drive = MemoryDriveRepository();
    final imp = _importer(repo, drive, state: const DriveState());
    final summary = await imp.importFiles([
      LocalFile.memory(name: 'a.txt', bytes: 'oi'.codeUnits),
      LocalFile.memory(name: 'b.pdf', bytes: [1]),
    ]);
    expect(summary.notes, 1);
    expect(summary.files, 0);
    expect(summary.errors.single, contains('b.pdf'));
    expect(summary.text, '1 nota criada, 0 arquivos enviados, 1 com erro');
    expect(drive.uploads, isEmpty);
  });

  test('falha de um arquivo não interrompe os demais', () async {
    final repo = MemoryRepository();
    final drive = MemoryDriveRepository();
    final imp = _importer(repo, drive);
    drive.failActions = true;
    final summary = await imp.importFiles([
      LocalFile.memory(name: 'a.pdf', bytes: [1]),
      LocalFile.memory(name: 'b.txt', bytes: 'oi'.codeUnits),
    ]);
    expect(summary.files, 0);
    expect(summary.notes, 1);
    expect(summary.errors.length, 1);
  });

  test('progresso é reportado a cada arquivo', () async {
    final imp = _importer(MemoryRepository(), MemoryDriveRepository());
    final seen = <(int, int)>[];
    await imp.importFiles(
      [LocalFile.memory(name: 'a.txt', bytes: [97]), LocalFile.memory(name: 'b.txt', bytes: [98])],
      onProgress: (d, t) => seen.add((d, t)),
    );
    expect(seen.last, (2, 2));
  });

  test('.txt/.md acima de 1 MB vão para o Drive (com nota-link) em vez de virar nota de texto', () async {
    final repo = MemoryRepository();
    final drive = MemoryDriveRepository();
    final imp = _importer(repo, drive);
    final big = List.filled(1024 * 1024 + 1, 97);
    final summary = await imp.importFiles([
      LocalFile.memory(name: 'enorme.txt', bytes: big),
      LocalFile.memory(name: 'cabe.txt', bytes: List.filled(1024 * 1024, 98)),
    ]);
    expect(summary.errors, isEmpty);
    expect(summary.files, 1);
    expect(drive.uploads.map((u) => u.name), ['enorme.txt']);
    final notes = await _notes(repo);
    expect(notes.firstWhere((n) => n.title == 'enorme.txt').body, contains('Google Drive'));
    expect(notes.where((n) => n.title == 'cabe').length, 1);
  });

  test('texto grande sem Drive conectado dá erro e não carrega o arquivo como nota', () async {
    final repo = MemoryRepository();
    final imp = _importer(repo, MemoryDriveRepository(), state: const DriveState());
    final summary = await imp.importFiles([LocalFile.memory(name: 'enorme.md', bytes: List.filled(1024 * 1024 + 1, 97))]);
    expect(summary.notes, 0);
    expect(summary.errors.single, contains('enorme.md'));
    expect(await _notes(repo), isEmpty);
  });
}
