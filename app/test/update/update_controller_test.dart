import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/app/providers.dart';
import 'package:organizacional/data/repository.dart';
import 'package:organizacional/update/app_release.dart';
import 'package:organizacional/update/release_repository.dart';
import 'package:organizacional/update/update_controller.dart';
import 'package:organizacional/update/update_downloader.dart';
import 'package:organizacional/update/update_installer.dart';
import 'package:organizacional/update/update_prefs.dart';
import 'package:organizacional/update/update_providers.dart';

import 'fakes.dart';

void main() {
  late MemoryReleaseRepository repo;
  late FakeInstaller installer;
  late FakeDownloader downloader;
  late MemoryUpdatePrefs prefs;
  late DateTime now;
  late int exits;
  late Directory tmp;
  late ProviderContainer container;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('upd-ctl-');
    repo = MemoryReleaseRepository([release(build: 5)]);
    installer = FakeInstaller(dir: tmp);
    downloader = FakeDownloader();
    prefs = MemoryUpdatePrefs();
    now = DateTime(2026, 10, 27, 10);
    exits = 0;
    container = ProviderContainer(overrides: [
      releaseRepositoryProvider.overrideWithValue(repo),
      updateInstallerProvider.overrideWithValue(installer),
      updateDownloaderProvider.overrideWithValue(downloader),
      updatePrefsProvider.overrideWithValue(prefs),
      installedVersionLoaderProvider.overrideWithValue(() async => const InstalledVersion('1.0.0', 3)),
      clockProvider.overrideWithValue(() => now),
      updateExitProvider.overrideWithValue(() => exits++),
    ]);
    addTearDown(container.dispose);
    addTearDown(() => tmp.deleteSync(recursive: true));
  });

  UpdateController ctl() => container.read(updateControllerProvider.notifier);
  UpdateState st() => container.read(updateControllerProvider);

  group('checagem', () {
    test('build maior que o instalado: há atualização', () async {
      await ctl().check();
      expect(st().phase, UpdatePhase.available);
      expect(st().release?.build, 5);
      expect(st().showBanner, isTrue);
    });

    test('compara pelo build, não pelo texto da versão', () async {
      repo.releases
        ..clear()
        ..add(release(build: 3, version: '9.9.9'));
      await ctl().check();
      expect(st().phase, UpdatePhase.upToDate);
      expect(st().showBanner, isFalse);
    });

    test('em dia: guarda a release atual para mostrar as novidades, sem permitir reinstalar', () async {
      repo.releases
        ..clear()
        ..add(release(build: 3, version: '1.0.0', notes: 'Primeira versão'));
      await ctl().check();
      expect(st().phase, UpdatePhase.upToDate);
      expect(st().release?.notes, 'Primeira versão');
      expect(st().showBanner, isFalse);
      await ctl().startUpdate();
      expect(downloader.calls, isEmpty);
      await ctl().dismiss();
      expect(await prefs.dismissedBuild(), 0);
    });

    test('sem release publicada: em dia', () async {
      repo.releases.clear();
      await ctl().check(manual: true);
      expect(st().phase, UpdatePhase.upToDate);
      expect(st().message, 'Você já está na versão mais recente.');
    });

    test('só consulta a plataforma do instalador', () async {
      repo.releases
        ..clear()
        ..add(release(build: 9, platform: 'linux'));
      await ctl().check();
      expect(st().phase, UpdatePhase.upToDate);
    });

    test('checagem automática que falha não mostra erro; a manual mostra', () async {
      repo.latestError = const RepositoryException('x');
      await ctl().check();
      expect(st().phase, UpdatePhase.idle);
      expect(st().message, isNull);
      await ctl().check(manual: true);
      expect(st().phase, UpdatePhase.error);
      expect(st().message, contains('Não foi possível procurar atualização'));
      expect(st().showBanner, isFalse, reason: 'erro de checagem não vira banner');
    });

    test('falha na checagem manual não esconde a atualização já encontrada', () async {
      await ctl().check();
      repo.latestError = const RepositoryException('x');
      await ctl().check(manual: true);
      expect(st().phase, UpdatePhase.available);
      expect(st().release?.build, 5);
      expect(st().message, contains('Não foi possível procurar atualização'));
    });

    test('sem suporte na plataforma nada é consultado', () async {
      installer.supported = false;
      await ctl().check();
      await ctl().checkIfDue();
      expect(repo.latestCalls, 0);
      expect(st().phase, UpdatePhase.idle);
    });
  });

  group('no máximo uma vez a cada 24 h', () {
    test('a primeira checagem roda e grava o horário', () async {
      await ctl().checkIfDue();
      expect(repo.latestCalls, 1);
      expect(await prefs.lastCheck(), now);
    });

    test('dentro de 24 h não consulta de novo; passadas 24 h consulta', () async {
      await ctl().checkIfDue();
      now = now.add(const Duration(hours: 23, minutes: 59));
      await ctl().checkIfDue();
      expect(repo.latestCalls, 1);
      now = now.add(const Duration(minutes: 2));
      await ctl().checkIfDue();
      expect(repo.latestCalls, 2);
    });

    test('a checagem manual ignora o intervalo', () async {
      await ctl().checkIfDue();
      await ctl().check(manual: true);
      expect(repo.latestCalls, 2);
    });

    test('checagem que falhou não consome as 24 h', () async {
      repo.latestError = const RepositoryException('x');
      await ctl().checkIfDue();
      expect(await prefs.lastCheck(), isNull);
      repo.latestError = null;
      await ctl().checkIfDue();
      expect(repo.latestCalls, 2);
    });
  });

  group('Depois', () {
    test('esconde o banner dessa versão e lembra entre aberturas', () async {
      await ctl().check();
      await ctl().dismiss();
      expect(st().showBanner, isFalse);
      expect(st().phase, UpdatePhase.available, reason: 'o Ajustes ainda mostra a atualização');
      expect(await prefs.dismissedBuild(), 5);

      container.invalidate(updateControllerProvider);
      await ctl().check(manual: true);
      expect(st().phase, UpdatePhase.available);
      expect(st().showBanner, isFalse);
    });

    test('uma versão mais nova volta a avisar', () async {
      await ctl().check();
      await ctl().dismiss();
      repo.releases.add(release(build: 6, version: '1.2.0'));
      await ctl().check();
      expect(st().release?.build, 6);
      expect(st().showBanner, isTrue);
    });
  });

  group('atualizar', () {
    setUp(() async => ctl().check());

    test('pede URL assinada, baixa com o sha e o tamanho publicados e abre o instalador', () async {
      await ctl().startUpdate();
      final call = downloader.calls.single;
      expect(call.url.toString(), contains('android/5/organizacional-1.1.0+5.apk'));
      expect(call.sha256, 'a' * 64);
      expect(call.size, 100);
      expect(call.path, '${tmp.path}/organizacional-1.1.0+5.apk');
      expect(installer.installs.single.prompt, isTrue);
      expect(st().phase, UpdatePhase.available);
      expect(st().message, contains('instalador do Android'));
    });

    test('mostra o progresso enquanto baixa e permite cancelar sem erro', () async {
      downloader.gate = Completer<void>();
      final seen = <double?>[];
      container.listen(updateControllerProvider, (_, s) {
        if (s.phase == UpdatePhase.downloading) seen.add(s.progress);
      });
      final run = ctl().startUpdate();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(st().phase, UpdatePhase.downloading);
      expect(seen, containsAll(<double?>[0.25, 0.5]));
      ctl().cancelDownload();
      await run;
      expect(st().phase, UpdatePhase.available);
      expect(st().message, isNull);
      expect(installer.installs, isEmpty);
    });

    test('SHA-256 que não confere: erro claro, nada instalado', () async {
      downloader.error = const UpdateIntegrityException('A verificação de integridade (SHA-256) não confere.');
      await ctl().startUpdate();
      expect(st().phase, UpdatePhase.error);
      expect(st().message, contains('não confere'));
      expect(installer.installs, isEmpty);
      expect(st().showBanner, isTrue);
    });

    test('fechar o erro volta ao aviso normal', () async {
      downloader.error = const UpdateDownloadException('caiu');
      await ctl().startUpdate();
      ctl().acknowledgeError();
      expect(st().phase, UpdatePhase.available);
      expect(st().message, isNull);
    });

    test('depois do erro dá para tentar de novo', () async {
      downloader.error = const UpdateDownloadException('A conexão caiu durante o download. Tente de novo.');
      await ctl().startUpdate();
      expect(st().phase, UpdatePhase.error);
      downloader.error = null;
      await ctl().startUpdate();
      expect(st().phase, UpdatePhase.available);
      expect(installer.installs, hasLength(1));
    });

    test('falha ao obter a URL assinada vira erro claro', () async {
      final bad = _FailingSignRepo(repo);
      final c = ProviderContainer(overrides: [
        releaseRepositoryProvider.overrideWithValue(bad),
        updateInstallerProvider.overrideWithValue(installer),
        updateDownloaderProvider.overrideWithValue(downloader),
        updatePrefsProvider.overrideWithValue(prefs),
        installedVersionLoaderProvider.overrideWithValue(() async => const InstalledVersion('1.0.0', 3)),
      ]);
      addTearDown(c.dispose);
      await c.read(updateControllerProvider.notifier).check();
      await c.read(updateControllerProvider.notifier).startUpdate();
      final s = c.read(updateControllerProvider);
      expect(s.phase, UpdatePhase.error);
      expect(s.message, contains('link de download'));
      expect(downloader.calls, isEmpty);
    });

    test('sem permissão no Android: pede para liberar e retoma ao voltar, sem reabrir os ajustes', () async {
      installer.outcomes = [
        const InstallOutcome(InstallResult.needsPermission, 'Libere “Instalar apps desconhecidos”.'),
        const InstallOutcome(InstallResult.needsPermission, 'Libere “Instalar apps desconhecidos”.'),
        const InstallOutcome(InstallResult.started),
      ];
      await ctl().startUpdate();
      expect(st().phase, UpdatePhase.needsPermission);
      expect(st().message, contains('Instalar apps desconhecidos'));
      expect(st().showBanner, isTrue);

      await ctl().retryInstall(); // volta dos ajustes sem liberar
      expect(st().phase, UpdatePhase.needsPermission);
      await ctl().retryInstall(); // volta liberado
      expect(st().phase, UpdatePhase.available);
      expect(downloader.created, 1, reason: 'não baixa de novo');
      expect(installer.installs.map((i) => i.prompt), [true, false, false]);
    });

    test('"Tentar de novo" manual pode reabrir os ajustes', () async {
      installer.outcomes = [const InstallOutcome(InstallResult.needsPermission, 'm')];
      await ctl().startUpdate();
      await ctl().retryInstall(prompt: true);
      expect(installer.installs.map((i) => i.prompt), [true, true]);
    });

    test('desktop: ao ficar pronto o app sai e o pacote baixado é apagado', () async {
      installer.outcomes = [const InstallOutcome(InstallResult.restarting)];
      await ctl().startUpdate();
      expect(exits, 1);
      expect(st().phase, UpdatePhase.installing);
      expect(File(installer.installs.single.path).existsSync(), isFalse);
    });

    test('falha ao instalar mostra a mensagem do instalador', () async {
      installer.outcomes = [const InstallOutcome(InstallResult.failed, 'O pacote tem um caminho inseguro.')];
      await ctl().startUpdate();
      expect(st().phase, UpdatePhase.error);
      expect(st().message, 'O pacote tem um caminho inseguro.');
      expect(exits, 0);
    });

    test('não começa dois downloads ao mesmo tempo', () async {
      downloader.gate = Completer<void>();
      final a = ctl().startUpdate();
      await Future<void>.delayed(Duration.zero);
      await ctl().startUpdate();
      expect(downloader.calls, hasLength(1));
      ctl().cancelDownload();
      await a;
    });
  });
}

class _FailingSignRepo implements ReleaseRepository {
  _FailingSignRepo(this.inner);
  final ReleaseRepository inner;
  @override
  Future<AppRelease?> latest(String platform) => inner.latest(platform);
  @override
  Future<Uri> signedUrl(String storagePath) => throw const RepositoryException('x');
}
