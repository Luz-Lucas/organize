import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/app/app.dart';
import 'package:organizacional/app/providers.dart';
import 'package:organizacional/app/router.dart';
import 'package:organizacional/data/drive_repository.dart';
import 'package:organizacional/data/email_repository.dart';
import 'package:organizacional/data/github_repository.dart';
import 'package:organizacional/data/location_repository.dart';
import 'package:organizacional/data/memory_alexa_repository.dart';
import 'package:organizacional/data/memory_drive_repository.dart';
import 'package:organizacional/data/memory_email_repository.dart';
import 'package:organizacional/data/memory_github_repository.dart';
import 'package:organizacional/data/memory_location_repository.dart';
import 'package:organizacional/data/memory_news_repository.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/data/memory_settings_repository.dart';
import 'package:organizacional/data/share_intent_service.dart';
import 'package:organizacional/domain/drive.dart';
import 'package:organizacional/domain/local_file.dart';
import 'package:organizacional/domain/space.dart';
import 'package:organizacional/features/import/share_listener.dart';

import '../helpers.dart';

class _FakeShare implements ShareIntentService {
  _FakeShare([this.initialContent]);
  SharedContent? initialContent;
  final controller = StreamController<SharedContent>.broadcast();
  @override
  Future<SharedContent?> initial() async => initialContent;
  @override
  Stream<SharedContent> get stream => controller.stream;
}

Future<void> _pump(
  WidgetTester tester, {
  required MemoryRepository repo,
  required MemoryDriveRepository drive,
  required ShareIntentService share,
  bool signedIn = true,
}) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final router = buildRouter(isSignedIn: () => signedIn);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      repositoryProvider.overrideWithValue(repo),
      clockProvider.overrideWithValue(() => defaultNow),
      newsRepositoryProvider.overrideWithValue(MemoryNewsRepository()),
      linkOpenerProvider.overrideWithValue((_) async => true),
      alexaRepositoryProvider.overrideWithValue(MemoryAlexaRepository()),
      settingsRepositoryProvider.overrideWithValue(MemorySettingsRepository()),
      locationRepositoryProvider.overrideWithValue(MemoryLocationRepository()),
      emailRepositoryProvider.overrideWithValue(MemoryEmailRepository()),
      githubRepositoryProvider.overrideWithValue(MemoryGithubRepository()),
      driveRepositoryProvider.overrideWithValue(drive),
      shareIntentServiceProvider.overrideWithValue(share),
      googleFontsEnabledProvider.overrideWithValue(false),
    ],
    child: ShareIntentListener(router: router, isSignedIn: () => signedIn, child: OrganizacionalApp(router: router)),
  ));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  test('SharedContent.fromMap lê texto, assunto e arquivos', () {
    final c = SharedContent.fromMap({
      'text': 'Oi\nmundo',
      'subject': 'Assunto',
      'files': [
        {'path': '/cache/a.pdf', 'name': 'a.pdf', 'mimeType': 'application/pdf', 'size': 12},
        {'path': null, 'name': 'sem-caminho'},
      ],
    });
    expect(c.text, 'Oi\nmundo');
    expect(c.files.single.name, 'a.pdf');
    expect(c.files.single.size, 12);
    expect(c.hasText, isTrue);
    expect(SharedContent.fromMap({'text': '  '}).hasText, isFalse);
    expect(SharedContent.fromMap({}).isEmpty, isTrue);
  });

  testWidgets('texto compartilhado com o app fechado: abre a folha, salva como nota em "Importadas"', (tester) async {
    final repo = MemoryRepository();
    final share = _FakeShare(const SharedContent(text: 'Resumo da aula\nTópico 1\nTópico 2'));
    await _pump(tester, repo: repo, drive: MemoryDriveRepository(), share: share);
    expect(find.byKey(const Key('share-sheet')), findsOneWidget);
    expect(find.byKey(const Key('share-help')), findsOneWidget);
    expect(find.textContaining('Samsung Notes'), findsOneWidget);
    expect(find.textContaining('Resumo da aula'), findsWidgets);
    await _tap(tester, 'share-save');
    expect(find.byKey(const Key('share-sheet')), findsNothing);
    final notes = await repo.watchNotes().first;
    expect(notes.single.title, 'Resumo da aula');
    expect(notes.single.body, 'Tópico 1\n\nTópico 2');
    final spaces = await repo.watchSpaces().first;
    expect(spaces.single.name, 'Importadas');
    expect(notes.single.spaceId, spaces.single.id);
    expect(find.textContaining('criada'), findsOneWidget);
  });

  testWidgets('app aberto: a folha aparece quando chega um novo compartilhamento e dá para escolher o espaço', (tester) async {
    final repo = MemoryRepository();
    await repo.upsertSpace(const Space(id: 'sp1', name: 'Faculdade'));
    final share = _FakeShare();
    await _pump(tester, repo: repo, drive: MemoryDriveRepository(), share: share);
    expect(find.byKey(const Key('share-sheet')), findsNothing);
    share.controller.add(const SharedContent(text: 'Ideia solta'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('share-sheet')), findsOneWidget);
    await _tap(tester, 'share-space');
    await tester.tap(find.text('Faculdade').last);
    await tester.pumpAndSettle();
    await _tap(tester, 'share-save');
    final n = (await repo.watchNotes().first).single;
    expect(n.spaceId, 'sp1');
    expect((await repo.watchSpaces().first).length, 1); // não criou "Importadas"
  });

  testWidgets('arquivo: vai ao Drive em Importados e cria nota com o link', (tester) async {
    final repo = MemoryRepository();
    final drive = MemoryDriveRepository();
    final share = _FakeShare(SharedContent(files: [LocalFile.memory(name: 'Prova.pdf', bytes: [1, 2, 3])]));
    await _pump(tester, repo: repo, drive: drive, share: share);
    expect(find.byKey(const Key('share-sheet')), findsOneWidget);
    expect(find.text('Prova.pdf'), findsWidgets);
    await _tap(tester, 'share-save');
    expect(drive.uploads.single.name, 'Prova.pdf');
    final note = (await repo.watchNotes().first).single;
    expect(note.title, 'Prova.pdf');
    expect(note.body, contains('https://drive.example/'));
    expect(find.byKey(const Key('share-sheet')), findsNothing);
    expect(find.textContaining('1 nota criada, 1 arquivo enviado'), findsOneWidget);
  });

  testWidgets('arquivo sem Drive conectado: explica e oferece abrir Ajustes; nada é salvo', (tester) async {
    final repo = MemoryRepository();
    final drive = MemoryDriveRepository(state: const DriveState());
    final share = _FakeShare(SharedContent(files: [LocalFile.memory(name: 'Prova.pdf', bytes: [1])]));
    await _pump(tester, repo: repo, drive: drive, share: share);
    expect(find.byKey(const Key('share-drive-missing')), findsOneWidget);
    expect(find.byKey(const Key('share-save')), findsNothing);
    await _tap(tester, 'share-open-settings');
    expect(find.byKey(const Key('share-sheet')), findsNothing);
    await tester.scrollUntilVisible(find.byKey(const Key('drive-card')), 300, scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const Key('drive-card')), findsOneWidget);
    expect(drive.uploads, isEmpty);
    expect(await repo.watchNotes().first, isEmpty);
  });

  testWidgets('texto + arquivo sem Drive: salva só o texto e avisa que o arquivo ficou de fora', (tester) async {
    final repo = MemoryRepository();
    final drive = MemoryDriveRepository(state: const DriveState());
    final share = _FakeShare(SharedContent(text: 'Anotação', files: [LocalFile.memory(name: 'x.pdf', bytes: [1])]));
    await _pump(tester, repo: repo, drive: drive, share: share);
    expect(find.byKey(const Key('share-drive-missing')), findsOneWidget);
    await _tap(tester, 'share-save');
    expect((await repo.watchNotes().first).single.title, 'Anotação');
    expect(drive.uploads, isEmpty);
  });

  testWidgets('falha ao salvar mantém a folha aberta com o erro', (tester) async {
    final repo = MemoryRepository()..failWrites = true;
    final share = _FakeShare(const SharedContent(text: 'Algo'));
    await _pump(tester, repo: repo, drive: MemoryDriveRepository(), share: share);
    await _tap(tester, 'share-save');
    expect(find.byKey(const Key('share-sheet')), findsOneWidget);
    expect(find.byKey(const Key('share-error')), findsOneWidget);
  });

  testWidgets('sem login: avisa para entrar e não oferece salvar', (tester) async {
    final share = _FakeShare(const SharedContent(text: 'Algo'));
    await _pump(tester, repo: MemoryRepository(), drive: MemoryDriveRepository(), share: share, signedIn: false);
    expect(find.byKey(const Key('share-sheet')), findsOneWidget);
    expect(find.byKey(const Key('share-signin-required')), findsOneWidget);
    expect(find.byKey(const Key('share-save')), findsNothing);
  });
}
