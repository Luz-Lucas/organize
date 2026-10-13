import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/note.dart';
import 'package:organizacional/domain/space.dart';
import 'package:organizacional/features/import/importer.dart';

import '../../helpers.dart';
import 'fakes.dart';

const _phone = Size(400, 800);

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('notes-menu')));
  await tester.pumpAndSettle();
}

Future<MemoryRepository> _repoWithSamsungNote({String space = 'Samsung Notes', String? link = 'https://drive.google.com/file/d/abc/view'}) async {
  final repo = MemoryRepository();
  await repo.upsertSpace(Space(id: 's1', name: space));
  await repo.upsertNote(Note(
    id: 'n1',
    title: 'Aula 1.pdf',
    body: driveLinkNoteBody('Aula 1.pdf', link),
    spaceId: 's1',
  ));
  return repo;
}

void main() {
  group('menu das Notas', () {
    testWidgets('Samsung Notes instalado: aparece "Abrir Samsung Notes" e abre o app', (tester) async {
      final platform = FakeSamsungPlatform();
      await pumpApp(tester, MemoryRepository(), location: '/notas', size: _phone, samsungPlatform: platform);
      await _openMenu(tester);
      expect(find.byKey(const Key('open-samsung-notes')), findsOneWidget);
      await tester.tap(find.byKey(const Key('open-samsung-notes')));
      await tester.pumpAndSettle();
      expect(platform.openCalls, 1);
    });

    testWidgets('Samsung Notes não instalado (ou fora do Android): a ação não existe', (tester) async {
      await pumpApp(tester, MemoryRepository(), location: '/notas', size: _phone, samsungPlatform: FakeSamsungPlatform()..installed = false);
      await _openMenu(tester);
      expect(find.byKey(const Key('notes-import')), findsOneWidget);
      expect(find.byKey(const Key('open-samsung-notes')), findsNothing);
    });

    testWidgets('Importar arquivos continua funcionando no mesmo menu', (tester) async {
      await pumpApp(tester, MemoryRepository(), location: '/notas', size: _phone, samsungPlatform: FakeSamsungPlatform());
      await _openMenu(tester);
      expect(find.byKey(const Key('notes-import')), findsOneWidget);
    });
  });

  group('nota-link do Samsung Notes', () {
    testWidgets('mostra "Abrir no Drive" e "Abrir Samsung Notes"', (tester) async {
      final platform = FakeSamsungPlatform();
      final opened = <Uri>[];
      await pumpApp(tester, await _repoWithSamsungNote(), location: '/nota/n1', size: _phone, samsungPlatform: platform, openLink: (u) async {
        opened.add(u);
        return true;
      });
      expect(find.byKey(const Key('samsung-open-drive')), findsOneWidget);
      expect(find.byKey(const Key('samsung-open-app')), findsOneWidget);
      await tester.tap(find.byKey(const Key('samsung-open-drive')));
      await tester.pumpAndSettle();
      expect(opened, [Uri.parse('https://drive.google.com/file/d/abc/view')]);
      await tester.tap(find.byKey(const Key('samsung-open-app')));
      await tester.pumpAndSettle();
      expect(platform.openCalls, 1);
    });

    testWidgets('sem o app da Samsung instalado só sobra "Abrir no Drive"', (tester) async {
      await pumpApp(tester, await _repoWithSamsungNote(), location: '/nota/n1', size: _phone, samsungPlatform: FakeSamsungPlatform()..installed = false);
      expect(find.byKey(const Key('samsung-open-drive')), findsOneWidget);
      expect(find.byKey(const Key('samsung-open-app')), findsNothing);
    });

    testWidgets('nota comum (fora do espaço Samsung Notes) não ganha os botões', (tester) async {
      await pumpApp(tester, await _repoWithSamsungNote(space: 'Outro'), location: '/nota/n1', size: _phone, samsungPlatform: FakeSamsungPlatform());
      expect(find.byKey(const Key('samsung-open-drive')), findsNothing);
      expect(find.byKey(const Key('samsung-open-app')), findsNothing);
    });

    testWidgets('nota do espaço Samsung Notes sem link do Drive não ganha os botões', (tester) async {
      final repo = MemoryRepository();
      await repo.upsertSpace(const Space(id: 's1', name: 'Samsung Notes'));
      await repo.upsertNote(const Note(id: 'n1', title: 'Rascunho', body: 'texto livre', spaceId: 's1'));
      await pumpApp(tester, repo, location: '/nota/n1', size: _phone, samsungPlatform: FakeSamsungPlatform());
      expect(find.byKey(const Key('samsung-open-drive')), findsNothing);
    });

    test('driveLinkInBody lê o link da nota-link e ignora outros textos', () {
      expect(driveLinkInBody('Arquivo no Google Drive: [a.pdf](https://drive.google.com/x)'), 'https://drive.google.com/x');
      expect(driveLinkInBody('texto\n\nArquivo no Google Drive: [a b.pdf](https://drive.google.com/y?z=1)'), 'https://drive.google.com/y?z=1');
      expect(driveLinkInBody('Arquivo enviado ao Google Drive: a.pdf'), isNull);
      expect(driveLinkInBody('Arquivo no Google Drive: [a](http://inseguro.example/x)'), isNull);
      expect(driveLinkInBody(''), isNull);
    });
  });
}
