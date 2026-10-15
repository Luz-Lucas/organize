import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_drive_repository.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/drive.dart';
import 'package:organizacional/files/drive_file_opener.dart';
import 'package:organizacional/files/files_platform.dart';

import '../files/fakes.dart';
import '../helpers.dart';

const _phone = Size(400, 800);

void main() {
  late MemoryDriveRepository drive;
  late FakeDriveFileOpener opener;
  late List<Uri> links;

  setUp(() {
    drive = MemoryDriveRepository();
    opener = FakeDriveFileOpener();
    links = [];
  });

  Future<void> pump(WidgetTester tester, {bool supported = true}) => pumpApp(
        tester,
        MemoryRepository(),
        driveRepo: drive,
        location: '/documentos',
        size: _phone,
        openLink: (u) async {
          links.add(u);
          return true;
        },
        overrides: [
          driveFileOpenerProvider.overrideWithValue(opener),
          filesPlatformProvider.overrideWithValue(FakeFilesPlatform(supported: supported)),
        ],
      );

  testWidgets('tocar num arquivo abre pelo aparelho (cache), sem usar o link do Drive', (tester) async {
    final f = drive.addFile('Aula.pdf', drive.rootFolderId);
    await pump(tester);
    await tester.tap(find.text('Aula.pdf'));
    await tester.pumpAndSettle();
    expect(opener.opened, [f.id]);
    expect(links, isEmpty);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byKey(const Key('docs-download-progress')), findsNothing);
  });

  testWidgets('sem suporte a arquivos locais (ex.: web), cai no link do Drive como antes', (tester) async {
    final f = drive.addFile('Aula.pdf', drive.rootFolderId);
    await pump(tester, supported: false);
    await tester.tap(find.text('Aula.pdf'));
    await tester.pumpAndSettle();
    expect(opener.opened, isEmpty);
    expect(links.single.toString(), f.webViewLink);
  });

  testWidgets('arquivo nativo do Google (Docs) abre no navegador, não baixa', (tester) async {
    final f = drive.addFile('Plano', drive.rootFolderId, mimeType: 'application/vnd.google-apps.document');
    await pump(tester);
    await tester.tap(find.text('Plano'));
    await tester.pumpAndSettle();
    expect(opener.opened, isEmpty);
    expect(links.single.toString(), f.webViewLink);
  });

  testWidgets('baixando: mostra nome e tamanho com progresso e "Cancelar"; cancelar encerra sem abrir nada', (tester) async {
    final f = drive.addFile('Aula.pdf', drive.rootFolderId, size: 5 * 1024 * 1024);
    final gate = Completer<void>();
    opener
      ..downloading = DriveFileMeta(id: f.id, name: 'Aula.pdf', size: 5 * 1024 * 1024)
      ..gate = gate.future;
    await pump(tester);
    await tester.tap(find.text('Aula.pdf'));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('docs-download-progress')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('docs-download-text'))).data, 'Baixando Aula.pdf (5,0 MB)…');

    // enquanto baixa, outro toque no mesmo arquivo não abre de novo
    await tester.tap(find.text('Aula.pdf'), warnIfMissed: false);
    await tester.pump();
    expect(opener.opened, hasLength(1));

    await tester.tap(find.byKey(const Key('docs-download-cancel')));
    await tester.pump();
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('docs-download-progress')), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(links, isEmpty);
  });

  testWidgets('falha: mostra a mensagem; cópia possivelmente desatualizada: avisa', (tester) async {
    drive.addFile('Aula.pdf', drive.rootFolderId);
    await pump(tester);
    opener.result = const OpenResult(OpenOutcome.failed, 'Sem conexão (simulado)');
    await tester.tap(find.text('Aula.pdf'));
    await tester.pumpAndSettle();
    expect(find.text('Sem conexão (simulado)'), findsOneWidget);

    ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first)).clearSnackBars();
    await tester.pumpAndSettle();
    opener.result = const OpenResult(OpenOutcome.openedStale, 'Sem conexão: abri a cópia guardada no aparelho, que pode estar desatualizada.');
    await tester.tap(find.text('Aula.pdf'));
    await tester.pumpAndSettle();
    expect(find.textContaining('pode estar desatualizada'), findsOneWidget);
  });

  testWidgets('nenhum app abriu o arquivo: avisa e oferece "Abrir no Drive"', (tester) async {
    final f = drive.addFile('Aula.pdf', drive.rootFolderId);
    opener.result = const OpenResult(OpenOutcome.notOpened);
    await pump(tester);
    await tester.tap(find.text('Aula.pdf'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Não encontrei um app para abrir'), findsOneWidget);
    await tester.tap(find.byKey(const Key('docs-open-in-drive')));
    await tester.pumpAndSettle();
    expect(links.single.toString(), f.webViewLink);
  });

  testWidgets('needsBrowser vindo do abridor também abre o link', (tester) async {
    final f = drive.addFile('Aula.pdf', drive.rootFolderId);
    opener.result = const OpenResult(OpenOutcome.needsBrowser);
    await pump(tester);
    await tester.tap(find.text('Aula.pdf'));
    await tester.pumpAndSettle();
    expect(links.single.toString(), f.webViewLink);
  });

  testWidgets('menu do arquivo: "Abrir" (aparelho) e "Abrir no Drive" (link) são ações separadas', (tester) async {
    final f = drive.addFile('Aula.pdf', drive.rootFolderId);
    await pump(tester);
    await tester.tap(find.byKey(Key('doc-menu-${f.id}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('doc-act-open-local')), findsOneWidget);
    await tester.tap(find.byKey(const Key('doc-act-open')));
    await tester.pumpAndSettle();
    expect(links.single.toString(), f.webViewLink);
    expect(opener.opened, isEmpty);

    await tester.tap(find.byKey(Key('doc-menu-${f.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('doc-act-open-local')));
    await tester.pumpAndSettle();
    expect(opener.opened, [f.id]);
  });

  testWidgets('sem suporte a arquivos locais o menu não oferece "Abrir" pelo aparelho', (tester) async {
    final f = drive.addFile('Aula.pdf', drive.rootFolderId);
    await pump(tester, supported: false);
    await tester.tap(find.byKey(Key('doc-menu-${f.id}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('doc-act-open-local')), findsNothing);
    expect(find.byKey(const Key('doc-act-open')), findsOneWidget);
  });
}
