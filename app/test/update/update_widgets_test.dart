import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/update/app_release.dart';
import 'package:organizacional/update/release_repository.dart';
import 'package:organizacional/update/update_downloader.dart';
import 'package:organizacional/update/update_installer.dart';
import 'package:organizacional/update/update_prefs.dart';
import 'package:organizacional/update/update_providers.dart';

import '../helpers.dart';
import 'fakes.dart';

void main() {
  late MemoryReleaseRepository repo;
  late FakeInstaller installer;
  late FakeDownloader downloader;
  late MemoryUpdatePrefs prefs;
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('upd-w-');
    repo = MemoryReleaseRepository([release(build: 5)]);
    installer = FakeInstaller(dir: tmp);
    downloader = FakeDownloader();
    prefs = MemoryUpdatePrefs();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  List<Override> overrides({UpdateDownloader? dl}) => [
        releaseRepositoryProvider.overrideWithValue(repo),
        updateInstallerProvider.overrideWithValue(installer),
        updateDownloaderProvider.overrideWithValue(dl ?? downloader),
        updatePrefsProvider.overrideWithValue(prefs),
        installedVersionLoaderProvider.overrideWithValue(() async => const InstalledVersion('1.0.0', 3)),
      ];

  Future<void> open(WidgetTester t, {String location = '/', UpdateDownloader? dl}) =>
      pumpApp(t, MemoryRepository(), location: location, overrides: overrides(dl: dl));

  /// A lista de Ajustes é preguiçosa: rola até o widget existir na tela.
  Future<void> reveal(WidgetTester t, Finder f) =>
      t.scrollUntilVisible(f, 300, scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first);

  group('banner', () {
    testWidgets('aparece na Início com versão, novidades e os botões Atualizar e Depois', (t) async {
      await open(t);
      expect(find.byKey(const Key('update-banner')), findsOneWidget);
      expect(find.text('Atualização 1.1.0 disponível'), findsOneWidget);
      expect(find.text('Caderno novo'), findsOneWidget);
      expect(find.byKey(const Key('update-install')), findsOneWidget);
      expect(find.byKey(const Key('update-later')), findsOneWidget);
      expect(find.text('Atualizar'), findsOneWidget);
      expect(find.text('Depois'), findsOneWidget);
    });

    testWidgets('fica no shell: continua visível em outras telas', (t) async {
      await open(t, location: '/agenda');
      expect(find.byKey(const Key('update-banner')), findsOneWidget);
    });

    testWidgets('não aparece quando já está na versão mais nova', (t) async {
      repo.releases
        ..clear()
        ..add(release(build: 3, version: '1.0.0'));
      await open(t);
      expect(find.byKey(const Key('update-banner')), findsNothing);
    });

    testWidgets('não aparece em aparelho sem suporte a atualização', (t) async {
      installer.supported = false;
      await open(t);
      expect(find.byKey(const Key('update-banner')), findsNothing);
    });

    testWidgets('Depois esconde o aviso e ele não volta na próxima abertura', (t) async {
      await open(t);
      await t.tap(find.byKey(const Key('update-later')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('update-banner')), findsNothing);
      expect(await prefs.dismissedBuild(), 5);

      await t.pumpWidget(const SizedBox());
      await open(t); // "reabre" o app com as mesmas preferências do aparelho
      expect(find.byKey(const Key('update-banner')), findsNothing);
    });

    testWidgets('mostra o progresso do download e o Cancelar volta ao aviso', (t) async {
      downloader.gate = Completer<void>();
      await open(t);
      await t.tap(find.byKey(const Key('update-install')));
      await t.pump();
      await t.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.textContaining('50%'), findsOneWidget);
      expect(find.byKey(const Key('update-cancel')), findsOneWidget);
      expect(find.byKey(const Key('update-install')), findsNothing);

      await t.tap(find.byKey(const Key('update-cancel')));
      await t.pumpAndSettle();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byKey(const Key('update-install')), findsOneWidget);
      expect(installer.installs, isEmpty);
    });

    testWidgets('SHA-256 errado: erro claro, fechar volta ao aviso e nada é instalado', (t) async {
      // A conferência em si (e a limpeza do arquivo) é testada em update_downloader_test.dart.
      downloader.error = const UpdateIntegrityException(
          'A verificação de integridade (SHA-256) não confere: o arquivo baixado foi descartado. Nada foi instalado.');
      await open(t);
      await t.tap(find.byKey(const Key('update-install')));
      await t.pumpAndSettle();
      expect(find.textContaining('não confere'), findsOneWidget);
      expect(find.byKey(const Key('update-retry')), findsOneWidget);
      expect(installer.installs, isEmpty);

      await t.tap(find.byKey(const Key('update-close')));
      await t.pumpAndSettle();
      expect(find.textContaining('não confere'), findsNothing);
      expect(find.byKey(const Key('update-install')), findsOneWidget);
    });

    testWidgets('sem permissão no Android: explica e oferece Tentar de novo', (t) async {
      installer.outcomes = [
        const InstallOutcome(InstallResult.needsPermission, 'Permita “Instalar apps desconhecidos” para o Organize e volte.'),
        const InstallOutcome(InstallResult.started),
      ];
      await open(t);
      await t.tap(find.byKey(const Key('update-install')));
      await t.pumpAndSettle();
      expect(find.textContaining('Instalar apps desconhecidos'), findsOneWidget);

      await t.tap(find.byKey(const Key('update-retry')));
      await t.pumpAndSettle();
      expect(installer.installs.map((i) => i.prompt), [true, true]);
      expect(find.textContaining('instalador do Android'), findsOneWidget);
    });

    testWidgets('voltar ao app depois de liberar a permissão retoma a instalação sem reabrir os ajustes', (t) async {
      installer.outcomes = [
        const InstallOutcome(InstallResult.needsPermission, 'Permita.'),
        const InstallOutcome(InstallResult.started),
      ];
      await open(t);
      await t.tap(find.byKey(const Key('update-install')));
      await t.pumpAndSettle();

      for (final s in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        t.binding.handleAppLifecycleStateChanged(s);
      }
      await t.pumpAndSettle();
      expect(installer.installs.map((i) => i.prompt), [true, false]);
    });
  });

  group('Ajustes > Sobre', () {
    testWidgets('mostra a versão atual e "Procurar atualização"', (t) async {
      await open(t, location: '/ajustes');
      await reveal(t, find.byKey(const Key('about-card')));
      expect(find.byKey(const Key('about-card')), findsOneWidget);
      expect(find.text('Sobre'), findsOneWidget);
      expect(find.textContaining('1.0.0'), findsWidgets);
      expect(find.byKey(const Key('check-update')), findsOneWidget);
      expect(find.text('Procurar atualização'), findsOneWidget);
    });

    testWidgets('sem novidade: "Procurar atualização" diz que está em dia', (t) async {
      repo.releases
        ..clear()
        ..add(release(build: 3, version: '1.0.0', notes: 'Primeira versão'));
      await open(t, location: '/ajustes');
      await reveal(t, find.byKey(const Key('check-update')));
      await t.tap(find.byKey(const Key('check-update')));
      await t.pumpAndSettle();
      expect(find.text('Você já está na versão mais recente.'), findsOneWidget);
      expect(find.text('Primeira versão'), findsOneWidget, reason: 'novidades da versão instalada');
      expect(find.byKey(const Key('about-update')), findsNothing);
    });

    testWidgets('com novidade: mostra a versão nova, as novidades e o botão Atualizar', (t) async {
      await open(t, location: '/ajustes');
      await reveal(t, find.byKey(const Key('about-card')));
      final card = find.byKey(const Key('about-card'));
      expect(find.descendant(of: card, matching: find.text('Atualização 1.1.0 disponível')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('Caderno novo')), findsOneWidget);
      await reveal(t, find.byKey(const Key('about-update')));
      await t.tap(find.byKey(const Key('about-update')));
      await t.pumpAndSettle();
      expect(installer.installs, hasLength(1));
    });

    testWidgets('Depois no banner não tira a atualização do Sobre', (t) async {
      await open(t);
      await t.tap(find.byKey(const Key('update-later')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('nav-/ajustes')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('update-banner')), findsNothing);
      final card = find.byKey(const Key('about-card'));
      await reveal(t, card);
      expect(find.descendant(of: card, matching: find.text('Atualização 1.1.0 disponível')), findsOneWidget);
    });

    testWidgets('falha ao procurar mostra o erro no Sobre', (t) async {
      repo.releases.clear();
      await open(t, location: '/ajustes');
      repo.latestError = Exception('sem rede');
      await reveal(t, find.byKey(const Key('check-update')));
      await t.tap(find.byKey(const Key('check-update')));
      await t.pumpAndSettle();
      expect(find.textContaining('Não foi possível procurar atualização'), findsOneWidget);
    });
  });
}
