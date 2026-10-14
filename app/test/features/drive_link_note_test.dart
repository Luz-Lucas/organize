import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/drive.dart';
import 'package:organizacional/domain/note.dart';
import 'package:organizacional/features/import/importer.dart';
import 'package:organizacional/files/drive_file_opener.dart';
import 'package:organizacional/files/files_platform.dart';

import '../files/fakes.dart';
import '../helpers.dart';

const _phone = Size(400, 800);
const _link = 'https://drive.google.com/file/d/FILE1/view?usp=drivesdk';

void main() {
  group('driveLinkInBody', () {
    test('lê o link da nota-link e ignora outros textos', () {
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
      expect(driveLinkFileName(driveLinkNoteBody('Aula 1.pdf', 'https://drive.google.com/file/d/a/view')), 'Aula 1.pdf');
      expect(driveLinkFileName('texto\n\nArquivo no Google Drive: [b (2026-10-13).pdf](https://drive.google.com/x)'), 'b (2026-10-13).pdf');
      expect(driveLinkFileName('Arquivo enviado ao Google Drive: a.pdf'), isNull);
      expect(driveLinkFileName(''), isNull);
    });
  });

  group('botões da nota-link', () {
    late FakeDriveFileOpener opener;

    setUp(() => opener = FakeDriveFileOpener());

    Future<MemoryRepository> repoWith(String fileName, {String url = _link, String? body}) async {
      final repo = MemoryRepository();
      await repo.upsertNote(Note(id: 'n1', title: fileName, body: body ?? driveLinkNoteBody(fileName, url)));
      return repo;
    }

    Future<void> open(WidgetTester tester, MemoryRepository repo, {bool supported = true, List<Uri>? links}) => pumpApp(
          tester,
          repo,
          location: '/nota/n1',
          size: _phone,
          openLink: (u) async {
            links?.add(u);
            return true;
          },
          overrides: [
            driveFileOpenerProvider.overrideWithValue(opener),
            filesPlatformProvider.overrideWithValue(FakeFilesPlatform(supported: supported)),
          ],
        );

    testWidgets('mostra "Abrir no Drive" e "Abrir" (arquivo pelo aparelho), sem nada de Samsung Notes', (tester) async {
      final links = <Uri>[];
      await open(tester, await repoWith('Aula.pdf'), links: links);
      expect(find.byKey(const Key('open-drive-link')), findsOneWidget);
      expect(find.byKey(const Key('open-drive-file')), findsOneWidget);
      expect(find.textContaining('Samsung'), findsNothing);
      await tester.tap(find.byKey(const Key('open-drive-link')));
      await tester.pumpAndSettle();
      expect(links, [Uri.parse(_link)]);
    });

    testWidgets('qualquer tipo de arquivo (inclusive .sdocx) usa o mesmo botão, sem tratamento especial', (tester) async {
      await open(tester, await repoWith('Aula.sdocx'));
      expect(find.byKey(const Key('open-drive-file')), findsOneWidget);
      await tester.tap(find.byKey(const Key('open-drive-file')));
      await tester.pumpAndSettle();
      expect(opener.opened, ['FILE1']);
    });

    testWidgets('a nota-link não precisa estar em nenhum espaço especial', (tester) async {
      await open(tester, await repoWith('Aula.pdf'));
      expect(find.byKey(const Key('open-drive-file')), findsOneWidget);
    });

    testWidgets('nota comum (sem link do Drive) não ganha os botões', (tester) async {
      await open(tester, await repoWith('Rascunho', body: 'texto livre'));
      expect(find.byKey(const Key('open-drive-link')), findsNothing);
      expect(find.byKey(const Key('open-drive-file')), findsNothing);
    });

    testWidgets('sem suporte a arquivos locais (web) só sobra "Abrir no Drive"', (tester) async {
      await open(tester, await repoWith('Aula.pdf'), supported: false);
      expect(find.byKey(const Key('open-drive-file')), findsNothing);
      expect(find.byKey(const Key('open-drive-link')), findsOneWidget);
    });

    testWidgets('link sem id de arquivo do Drive não tem o botão de abrir', (tester) async {
      await open(tester, await repoWith('Aula.pdf', url: 'https://drive.example/file/7'));
      expect(find.byKey(const Key('open-drive-file')), findsNothing);
    });

    testWidgets('durante o download mostra progresso e "Cancelar" e desabilita o botão', (tester) async {
      final gate = Completer<void>();
      opener
        ..downloading = const DriveFileMeta(id: 'FILE1', name: 'Aula.pdf', size: 3)
        ..gate = gate.future;
      await open(tester, await repoWith('Aula.pdf'));
      await tester.tap(find.byKey(const Key('open-drive-file')));
      await tester.pump();
      expect(find.byKey(const Key('open-drive-progress')), findsOneWidget);
      expect(find.text('Baixando…'), findsOneWidget);
      expect(find.byKey(const Key('drive-open-cancel')), findsOneWidget);
      expect(tester.widget<OutlinedButton>(find.byKey(const Key('open-drive-file'))).onPressed, isNull);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('open-drive-progress')), findsNothing);
      expect(find.byKey(const Key('drive-open-cancel')), findsNothing);
    });

    testWidgets('cancelar volta o botão ao normal, sem erro nem aviso', (tester) async {
      final gate = Completer<void>();
      opener
        ..downloading = const DriveFileMeta(id: 'FILE1', name: 'Aula.pdf', size: 3)
        ..gate = gate.future;
      await open(tester, await repoWith('Aula.pdf'));
      await tester.tap(find.byKey(const Key('open-drive-file')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('drive-open-cancel')));
      await tester.pump();
      expect(find.byKey(const Key('open-drive-progress')), findsNothing);
      expect(tester.widget<OutlinedButton>(find.byKey(const Key('open-drive-file'))).onPressed, isNotNull);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('open-drive-error')), findsNothing);
      expect(find.byKey(const Key('open-drive-notice')), findsNothing);
    });

    testWidgets('falha: mostra o erro e dá para tentar de novo', (tester) async {
      opener.result = const OpenResult(OpenOutcome.failed, 'O acesso ao Google Drive expirou. Reconecte em Ajustes.');
      await open(tester, await repoWith('Aula.pdf'));
      await tester.tap(find.byKey(const Key('open-drive-file')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('open-drive-error')), findsOneWidget);
      expect(find.textContaining('O acesso ao Google Drive expirou'), findsOneWidget);
      opener.result = const OpenResult(OpenOutcome.opened);
      await tester.tap(find.byKey(const Key('open-drive-file')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('open-drive-error')), findsNothing);
      expect(opener.opened, hasLength(2));
    });

    testWidgets('cópia possivelmente desatualizada (sem rede): avisa', (tester) async {
      opener.result = const OpenResult(OpenOutcome.openedStale, 'Sem conexão: abri a cópia guardada no aparelho, que pode estar desatualizada.');
      await open(tester, await repoWith('Aula.pdf'));
      await tester.tap(find.byKey(const Key('open-drive-file')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('open-drive-stale')), findsOneWidget);
      expect(find.textContaining('pode estar desatualizada'), findsOneWidget);
    });

    testWidgets('nenhum app abre o arquivo: avisa e oferece "Abrir no Drive"', (tester) async {
      opener.result = const OpenResult(OpenOutcome.notOpened);
      final links = <Uri>[];
      await open(tester, await repoWith('Aula.pdf'), links: links);
      await tester.tap(find.byKey(const Key('open-drive-file')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Não encontrei um app para abrir'), findsOneWidget);
      await tester.tap(find.byKey(const Key('open-drive-notice-link')));
      await tester.pumpAndSettle();
      expect(links, [Uri.parse(_link)]);
    });

    testWidgets('arquivo nativo do Google (needsBrowser): abre o link do Drive', (tester) async {
      opener.result = const OpenResult(OpenOutcome.needsBrowser);
      final links = <Uri>[];
      await open(tester, await repoWith('Plano.pdf'), links: links);
      await tester.tap(find.byKey(const Key('open-drive-file')));
      await tester.pumpAndSettle();
      expect(links, [Uri.parse(_link)]);
    });
  });
}
