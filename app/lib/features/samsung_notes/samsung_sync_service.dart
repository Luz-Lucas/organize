import 'dart:async';

import '../../data/drive_repository.dart';
import '../../data/imported_files_repository.dart';
import '../../data/repository.dart';
import '../../domain/drive.dart';
import 'folder_sync.dart';
import 'samsung_sync_settings.dart';
import 'sync_lock.dart';

/// Tudo de que uma rodada precisa, sem Riverpod: o app e a tarefa em segundo plano montam o seu.
class SamsungSyncDeps {
  const SamsungSyncDeps({
    required this.repo,
    required this.drive,
    required this.imported,
    required this.fs,
    required this.prefs,
    required this.lock,
    required this.now,
    required this.hasSession,
    this.device,
  });

  final Repository repo;
  final DriveRepository drive;
  final ImportedFilesRepository imported;
  final FolderFileSystem fs;
  final SamsungSyncPrefs prefs;
  final SyncLock lock;
  final DateTime Function() now;
  final bool Function() hasSession;
  final String? device;
}

enum SamsungSyncStatus { ran, disabled, noSession, driveNotReady, noFolder, busy }

class SamsungSyncOutcome {
  const SamsungSyncOutcome(this.status, [this.result]);

  final SamsungSyncStatus status;
  final SyncResult? result;
}

const driveExpiredMessage = 'O acesso ao Google Drive expirou. Reconecte em Ajustes.';

Future<bool> _driveReady(DriveRepository drive) async {
  try {
    final state = await drive.watchState().first.timeout(const Duration(seconds: 10));
    return state?.status == DriveStatus.ok && (state?.rootFolderId ?? '').isNotEmpty;
  } catch (_) {
    return false;
  }
}

/// Uma rodada completa: confere sessão, chave, Drive e pasta; pega a trava; sincroniza; guarda o resumo.
/// [force] ignora a chave "Sincronizar automaticamente" (botão "Sincronizar agora").
/// Sem sessão, Drive conectado ou pasta, não faz nada.
Future<SamsungSyncOutcome> runSamsungSync(SamsungSyncDeps deps, {bool force = false}) async {
  if (!deps.hasSession()) return const SamsungSyncOutcome(SamsungSyncStatus.noSession);
  final settings = await deps.prefs.load();
  if (!settings.enabled && !force) return const SamsungSyncOutcome(SamsungSyncStatus.disabled);
  final folder = settings.folder;
  if (folder == null) return const SamsungSyncOutcome(SamsungSyncStatus.noFolder);
  if (!await _driveReady(deps.drive)) return const SamsungSyncOutcome(SamsungSyncStatus.driveNotReady);
  if (!await deps.lock.tryAcquire()) return const SamsungSyncOutcome(SamsungSyncStatus.busy);
  try {
    final sync = FolderSync(
      repo: deps.repo,
      drive: deps.drive,
      imported: deps.imported,
      fs: deps.fs,
      now: deps.now,
      device: deps.device,
    );
    final result = await sync.run(folder);
    await deps.prefs.saveLastRun(SamsungSyncLastRun(
      at: deps.now(),
      uploaded: result.uploaded,
      skipped: result.skipped,
      ignored: result.ignored,
      errors: result.errors.length,
      message: result.needsReconnect ? driveExpiredMessage : result.errors.firstOrNull,
    ));
    return SamsungSyncOutcome(SamsungSyncStatus.ran, result);
  } finally {
    await deps.lock.release();
  }
}
