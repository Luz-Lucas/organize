import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/drive_repository.dart';
import 'package:organizacional/data/memory_drive_repository.dart';
import 'package:organizacional/data/memory_imported_files_repository.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/drive.dart';
import 'package:organizacional/features/samsung_notes/samsung_folder.dart';
import 'package:organizacional/features/samsung_notes/samsung_sync_service.dart';
import 'package:organizacional/features/samsung_notes/samsung_sync_settings.dart';
import 'package:organizacional/features/samsung_notes/sync_lock.dart';

import 'fakes.dart';

final _now = DateTime(2026, 10, 13, 10);
const _folder = SamsungFolder(path: '/storage/emulated/0/Documents/Samsung Notes');

class _Env {
  _Env({DriveState? driveState, bool signedIn = true, bool enabled = true, SamsungFolder? folder = _folder}) {
    drive = CountingDriveRepository(state: driveState ?? const DriveState(status: DriveStatus.ok, rootFolderId: 'org-root'));
    prefs = MemorySamsungSyncPrefs(SamsungSyncSettings(enabled: enabled, folder: folder));
    deps = SamsungSyncDeps(
      repo: repo,
      drive: drive,
      imported: imported,
      fs: fs,
      prefs: prefs,
      lock: lock,
      now: () => _now,
      hasSession: () => signedIn,
      device: 'tablet',
    );
    fs.put('Aula.pdf', [1, 2, 3, 4]);
  }

  final repo = MemoryRepository();
  final imported = MemoryImportedFilesRepository();
  final fs = FakeFolderFileSystem();
  final lock = MemorySyncLock();
  late final CountingDriveRepository drive;
  late final MemorySamsungSyncPrefs prefs;
  late final SamsungSyncDeps deps;
}

void main() {
  test('ligada, com sessão, Drive ok e pasta: sincroniza e guarda o resumo da última rodada', () async {
    final e = _Env();
    final out = await runSamsungSync(e.deps);
    expect(out.status, SamsungSyncStatus.ran);
    expect(out.result!.uploaded, 1);
    final last = (await e.prefs.load()).lastRun!;
    expect(last.at, _now);
    expect(last.uploaded, 1);
    expect(last.ignored, 0);
    expect(last.text, '1 enviado, 0 ignorados');
    expect(e.imported.all.single.device, 'tablet');
  });

  test('desligada: não faz nada; "Sincronizar agora" (force) roda mesmo assim', () async {
    final e = _Env(enabled: false);
    final out = await runSamsungSync(e.deps);
    expect(out.status, SamsungSyncStatus.disabled);
    expect(e.drive.uploads, isEmpty);
    final forced = await runSamsungSync(e.deps, force: true);
    expect(forced.status, SamsungSyncStatus.ran);
    expect(e.drive.uploads, hasLength(1));
  });

  test('sem sessão: não faz nada (nem lê a pasta)', () async {
    final e = _Env(signedIn: false);
    expect((await runSamsungSync(e.deps)).status, SamsungSyncStatus.noSession);
    expect(e.fs.opened, isEmpty);
    expect((await e.prefs.load()).lastRun, isNull);
  });

  test('Drive não conectado, expirado ou sem pasta raiz: não faz nada', () async {
    for (final state in [
      const DriveState(),
      const DriveState(status: DriveStatus.authRequired, rootFolderId: 'org-root'),
      const DriveState(status: DriveStatus.ok),
    ]) {
      final e = _Env(driveState: state);
      expect((await runSamsungSync(e.deps)).status, SamsungSyncStatus.driveNotReady, reason: '${state.status}');
      expect(e.drive.uploads, isEmpty);
    }
  });

  test('sem pasta escolhida: avisa e não faz nada', () async {
    final e = _Env(folder: null);
    expect((await runSamsungSync(e.deps)).status, SamsungSyncStatus.noFolder);
  });

  test('trava ocupada: outra execução em andamento, esta não faz nada', () async {
    final e = _Env();
    expect(await e.lock.tryAcquire(), isTrue);
    expect((await runSamsungSync(e.deps)).status, SamsungSyncStatus.busy);
    expect(e.drive.uploads, isEmpty);
  });

  test('duas chamadas ao mesmo tempo: só uma executa', () async {
    final e = _Env();
    final both = await Future.wait([runSamsungSync(e.deps), runSamsungSync(e.deps)]);
    expect(both.map((o) => o.status).toSet(), {SamsungSyncStatus.ran, SamsungSyncStatus.busy});
    expect(e.drive.uploads, hasLength(1));
  });

  test('a trava é solta no fim, mesmo quando a pasta falha', () async {
    final e = _Env();
    e.fs.listError = StateError('boom');
    final out = await runSamsungSync(e.deps);
    expect(out.status, SamsungSyncStatus.ran);
    expect(out.result!.errors, isNotEmpty);
    expect(await e.lock.tryAcquire(), isTrue);
  });

  test('acesso do Drive expirado fica registrado na última rodada', () async {
    final e = _Env();
    e.drive.uploadError = const DriveException('expirou', code: 'auth_required');
    final out = await runSamsungSync(e.deps);
    expect(out.result!.needsReconnect, isTrue);
    final last = (await e.prefs.load()).lastRun!;
    expect(last.errors, 1);
    expect(last.message, contains('Reconecte'));
  });

  test('o estado do Drive só é lido (Memory) sem mexer na conta', () async {
    final e = _Env();
    await runSamsungSync(e.deps);
    expect(e.drive, isA<MemoryDriveRepository>());
    expect((await e.drive.watchState().first)!.status, DriveStatus.ok);
  });
}
