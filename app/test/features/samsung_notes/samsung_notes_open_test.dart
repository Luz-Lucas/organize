import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_drive_repository.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/note.dart';
import 'package:organizacional/domain/space.dart';
import 'package:organizacional/features/import/importer.dart';
import 'package:organizacional/features/samsung_notes/edit_in_samsung_notes.dart';

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

  group('driveFileIdFromLink e driveLinkFileName', () {
    test('lê o id do link do Drive (/file/d/ID/..., ?id=ID) e recusa o resto', () {
      expect(driveFileIdFromLink('https://drive.google.com/file/d/1AbC_-x9/view?usp=drivesdk'), '1AbC_-x9');
      expect(driveFileIdFromLink('https://drive.google.com/open?id=1AbC_-x9'), '1AbC_-x9');
      expect(driveFileIdFromLink('https://drive.google.com/file/d/abc'), 'abc');
      expect(driveFileIdFromLink('https://drive.google.com/drive/folders/xyz'), isNull);
      expect(driveFileIdFromLink('https://drive.example/file/7'), isNull);
      expect(driveFileIdFromLink('não é link'), isNull);
      expect(driveFileIdFromLink('https://drive.google.com/file/d/a%2Fb/view'), isNull);
    });

    test('lê o nome do arquivo da nota-link', () {
      expect(driveLinkFileName(driveLinkNoteBody('Aula 1.sdocx', 'https://drive.google.com/file/d/a/view')), 'Aula 1.sdocx');
      expect(driveLinkFileName('texto\n\nArquivo no Google Drive: [b (2026-10-13).pdf](https://drive.google.com/x)'), 'b (2026-10-13).pdf');
      expect(driveLinkFileName('Arquivo enviado ao Google Drive: a.pdf'), isNull);
      expect(driveLinkFileName(''), isNull);
    });
  });

  group('Editar no Samsung Notes', () {
    const link = 'https://drive.google.com/file/d/SDOCX1/view?usp=drivesdk';

    Future<MemoryRepository> repoWith(String fileName, {String space = 'Samsung Notes', String url = link}) async {
      final repo = MemoryRepository();
      await repo.upsertSpace(Space(id: 's1', name: space));
      await repo.upsertNote(Note(id: 'n1', title: fileName, body: driveLinkNoteBody(fileName, url), spaceId: 's1'));
      return repo;
    }

    final written = <String, List<int>>{};

    Future<MemoryDriveRepository> drive({String name = 'Aula.sdocx', MemoryDriveRepository? base}) async {
      final d = base ?? MemoryDriveRepository();
      d.addFile(name, d.rootFolderId, mimeType: 'application/octet-stream', bytes: [1, 2, 3], id: 'SDOCX1');
      return d;
    }

    setUp(written.clear);

    Future<void> open(
      WidgetTester tester, {
      required MemoryRepository repo,
      required FakeSamsungPlatform platform,
      required MemoryDriveRepository driveRepo,
      List<Uri>? opened,
    }) =>
        pumpApp(
          tester,
          repo,
          location: '/nota/n1',
          size: _phone,
          samsungPlatform: platform,
          driveRepo: driveRepo,
          openLink: (u) async {
            opened?.add(u);
            return true;
          },
          overrides: [samsungFileWriterProvider.overrideWithValue((path, bytes) async => written[path] = List<int>.from(bytes))],
        );

    testWidgets('nota-link de .sdocx com Samsung Notes instalado (Android): mostra o botão', (tester) async {
      await open(tester, repo: await repoWith('Aula.sdocx'), platform: FakeSamsungPlatform(), driveRepo: await drive());
      expect(find.byKey(const Key('edit-in-samsung-notes')), findsOneWidget);
      expect(find.text('Editar no Samsung Notes'), findsOneWidget);
      expect(find.byKey(const Key('samsung-open-drive')), findsOneWidget);
    });

    testWidgets('a extensão vale em qualquer caixa e com data no nome', (tester) async {
      await open(tester, repo: await repoWith('Aula (2026-10-13).SDOCX'), platform: FakeSamsungPlatform(), driveRepo: await drive());
      expect(find.byKey(const Key('edit-in-samsung-notes')), findsOneWidget);
    });

    testWidgets('nota-link de PDF não tem o botão', (tester) async {
      await open(tester, repo: await repoWith('Aula.pdf'), platform: FakeSamsungPlatform(), driveRepo: await drive());
      expect(find.byKey(const Key('edit-in-samsung-notes')), findsNothing);
      expect(find.byKey(const Key('samsung-open-drive')), findsOneWidget);
    });

    testWidgets('sem o Samsung Notes instalado não tem o botão', (tester) async {
      await open(tester, repo: await repoWith('Aula.sdocx'), platform: FakeSamsungPlatform()..installed = false, driveRepo: await drive());
      expect(find.byKey(const Key('edit-in-samsung-notes')), findsNothing);
    });

    testWidgets('fora do Android não tem o botão', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await open(tester, repo: await repoWith('Aula.sdocx'), platform: FakeSamsungPlatform(), driveRepo: await drive());
        expect(find.byKey(const Key('edit-in-samsung-notes')), findsNothing);
        expect(find.byKey(const Key('samsung-open-drive')), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('link sem id de arquivo do Drive não tem o botão', (tester) async {
      await open(
        tester,
        repo: await repoWith('Aula.sdocx', url: 'https://drive.example/file/7'),
        platform: FakeSamsungPlatform(),
        driveRepo: await drive(),
      );
      expect(find.byKey(const Key('edit-in-samsung-notes')), findsNothing);
    });

    testWidgets('fora do espaço Samsung Notes não tem o botão', (tester) async {
      await open(tester, repo: await repoWith('Aula.sdocx', space: 'Outro'), platform: FakeSamsungPlatform(), driveRepo: await drive());
      expect(find.byKey(const Key('edit-in-samsung-notes')), findsNothing);
    });

    testWidgets('toque: baixa, grava na pasta de trabalho e manda o caminho ao Samsung Notes', (tester) async {
      final platform = FakeSamsungPlatform();
      final d = await drive();
      await open(tester, repo: await repoWith('Aula.sdocx'), platform: platform, driveRepo: d);
      await tester.tap(find.byKey(const Key('edit-in-samsung-notes')));
      await tester.pumpAndSettle();
      expect(d.downloads, ['SDOCX1']);
      expect(written, {'/cache/samsung_open/Aula.sdocx': [1, 2, 3]});
      expect(platform.openedFiles, ['/cache/samsung_open/Aula.sdocx']);
      expect(find.byKey(const Key('edit-in-samsung-error')), findsNothing);
      expect(find.byKey(const Key('edit-in-samsung-notice')), findsNothing);
      expect(tester.widget<OutlinedButton>(find.byKey(const Key('edit-in-samsung-notes'))).onPressed, isNotNull);
    });

    testWidgets('durante o download mostra progresso e desabilita o botão', (tester) async {
      final gate = Completer<void>();
      final d = _SlowDrive(gate.future);
      await drive(base: d);
      final platform = FakeSamsungPlatform();
      await open(tester, repo: await repoWith('Aula.sdocx'), platform: platform, driveRepo: d);
      await tester.tap(find.byKey(const Key('edit-in-samsung-notes')));
      await tester.pump();
      expect(find.byKey(const Key('edit-in-samsung-progress')), findsOneWidget);
      expect(find.text('Baixando…'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(find.byKey(const Key('edit-in-samsung-notes'))).onPressed, isNull);
      expect(platform.openedFiles, isEmpty);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('edit-in-samsung-progress')), findsNothing);
      expect(platform.openedFiles, hasLength(1));
    });

    testWidgets('falha no download: mostra o erro e não abre nada', (tester) async {
      final platform = FakeSamsungPlatform();
      final d = await drive();
      d.authRequired = true;
      await open(tester, repo: await repoWith('Aula.sdocx'), platform: platform, driveRepo: d);
      await tester.tap(find.byKey(const Key('edit-in-samsung-notes')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('edit-in-samsung-error')), findsOneWidget);
      expect(find.textContaining('O acesso ao Google Drive expirou'), findsOneWidget);
      expect(platform.openedFiles, isEmpty);
      expect(written, isEmpty);
      // Dá para tentar de novo.
      d.authRequired = false;
      await tester.tap(find.byKey(const Key('edit-in-samsung-notes')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('edit-in-samsung-error')), findsNothing);
      expect(platform.openedFiles, hasLength(1));
    });

    testWidgets('openFile = false: avisa e oferece "Abrir no Drive"', (tester) async {
      final platform = FakeSamsungPlatform()..openFileResult = false;
      final opened = <Uri>[];
      await open(tester, repo: await repoWith('Aula.sdocx'), platform: platform, driveRepo: await drive(), opened: opened);
      await tester.tap(find.byKey(const Key('edit-in-samsung-notes')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('edit-in-samsung-notice')), findsOneWidget);
      expect(find.textContaining('Não encontrei um app para abrir'), findsOneWidget);
      await tester.tap(find.byKey(const Key('edit-in-samsung-open-drive')));
      await tester.pumpAndSettle();
      expect(opened, [Uri.parse(link)]);
    });
  });
}

class _SlowDrive extends MemoryDriveRepository {
  _SlowDrive(this.gate);

  final Future<void> gate;

  @override
  Future<Uint8List> download(String id) async {
    await gate;
    return super.download(id);
  }
}
