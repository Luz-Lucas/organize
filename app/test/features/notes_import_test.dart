import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/file_picker_service.dart';
import 'package:organizacional/data/memory_drive_repository.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/drive.dart';
import 'package:organizacional/domain/local_file.dart';

import '../helpers.dart';

class _Picker implements FilePickerService {
  _Picker(this.files);
  final List<LocalFile> files;
  bool? lastMultiple;
  @override
  Future<List<LocalFile>> pickFiles({bool multiple = true}) async {
    lastMultiple = multiple;
    return files;
  }
}

Future<void> _import(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('notes-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('notes-import')));
  await tester.pumpAndSettle();
}

void main() {
  for (final (label, size) in [('celular', const Size(400, 800)), ('computador (Linux)', const Size(1000, 800))]) {
    testWidgets('Notas > Importar arquivos no $label: txt/md viram notas, pdf vai ao Drive; resumo no fim', (tester) async {
      final repo = MemoryRepository();
      final drive = MemoryDriveRepository();
      final picker = _Picker([
        LocalFile.memory(name: 'aula.txt', bytes: 'Tópico A\nTópico B'.codeUnits),
        LocalFile.memory(name: 'guia.md', bytes: '# Guia\n\ntexto'.codeUnits),
        LocalFile.memory(name: 'Edital.pdf', bytes: [1, 2, 3]),
      ]);
      await pumpApp(tester, repo, location: '/notas', size: size, driveRepo: drive, filePicker: picker);
      await _import(tester);
      expect(picker.lastMultiple, isTrue);
      expect(find.byKey(const Key('import-summary')), findsOneWidget);
      expect(find.text('3 notas criadas, 1 arquivo enviado'), findsOneWidget);
      final notes = await repo.watchNotes().first;
      expect(notes.map((n) => n.title), containsAll(['aula', 'guia', 'Edital.pdf']));
      expect(drive.uploads.single.name, 'Edital.pdf');
      await tester.tap(find.byKey(const Key('import-summary-ok')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('import-summary')), findsNothing);
      expect(find.text('Importadas'), findsWidgets); // o espaço novo aparece na árvore
    });
  }

  testWidgets('cancelar a escolha não faz nada', (tester) async {
    final repo = MemoryRepository();
    await pumpApp(tester, repo, location: '/notas', size: const Size(400, 800), filePicker: _Picker(const []));
    await _import(tester);
    expect(find.byKey(const Key('import-summary')), findsNothing);
    expect(await repo.watchNotes().first, isEmpty);
  });

  testWidgets('sem Drive: o resumo lista o arquivo que falhou e as notas de texto continuam', (tester) async {
    final repo = MemoryRepository();
    final picker = _Picker([
      LocalFile.memory(name: 'a.txt', bytes: 'oi'.codeUnits),
      LocalFile.memory(name: 'b.pdf', bytes: [1]),
    ]);
    await pumpApp(tester, repo, location: '/notas', size: const Size(400, 800), driveRepo: MemoryDriveRepository(state: const DriveState()), filePicker: picker);
    await _import(tester);
    expect(find.text('1 nota criada, 0 arquivos enviados, 1 com erro'), findsOneWidget);
    expect(find.textContaining('b.pdf'), findsOneWidget);
    expect((await repo.watchNotes().first).single.title, 'a');
  });
}
