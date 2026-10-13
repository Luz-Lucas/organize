import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/features/samsung_notes/samsung_background.dart';
import 'package:organizacional/features/samsung_notes/samsung_folder.dart';
import 'package:organizacional/features/samsung_notes/samsung_sync_service.dart';
import 'package:organizacional/features/samsung_notes/samsung_sync_settings.dart';
import 'package:organizacional/data/memory_drive_repository.dart';
import 'package:organizacional/data/memory_imported_files_repository.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/features/samsung_notes/sync_lock.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fakes.dart';

class _BoomPrefs implements SamsungSyncPrefs {
  @override
  Future<SamsungSyncSettings> load() async => throw StateError('disco');
  @override
  Future<void> setEnabled(bool enabled) async {}
  @override
  Future<void> setFolder(SamsungFolder? folder) async {}
  @override
  Future<void> saveLastRun(SamsungSyncLastRun run) async {}
}

void main() {
  test('constantes da tarefa (nome único pedido no plano, a cada 15 minutos)', () {
    expect(samsungSyncUniqueName, 'samsung-notes-sync');
    expect(samsungSyncTask, 'samsungNotesSync');
    expect(samsungSyncFrequency, const Duration(minutes: 15));
  });

  test('a trava em arquivo fica no diretório temporário do app (o mesmo para o app e a tarefa)', () {
    expect(samsungSyncLockFile().path, startsWith(Directory.systemTemp.path));
    expect(samsungSyncLockFile().path, endsWith('.lock'));
  });

  test('sem cliente do Supabase a tarefa não faz nada', () async {
    expect(await runSamsungSyncTask(null), isFalse);
  });

  test('sem sessão salva a tarefa não faz nada', () async {
    SharedPreferences.setMockInitialValues({});
    final client = SupabaseClient('http://localhost:54321', 'anon');
    expect(await runSamsungSyncTask(client), isFalse);
  });

  test('com tudo pronto, a tarefa sincroniza e devolve true; erros engolidos devolvem false', () async {
    final fs = FakeFolderFileSystem()..put('Aula.pdf', [1, 2, 3, 4]);
    final drive = MemoryDriveRepository();
    final deps = SamsungSyncDeps(
      repo: MemoryRepository(),
      drive: drive,
      imported: MemoryImportedFilesRepository(),
      fs: fs,
      prefs: MemorySamsungSyncPrefs(const SamsungSyncSettings(enabled: true, folder: SamsungFolder(path: '/x'))),
      lock: MemorySyncLock(),
      now: () => DateTime(2026, 10, 13, 10),
      hasSession: () => true,
    );
    expect(await runSamsungSyncTaskWith(deps), isTrue);
    expect(drive.uploads, hasLength(1));
    final broken = SamsungSyncDeps(
      repo: MemoryRepository(),
      drive: MemoryDriveRepository(),
      imported: MemoryImportedFilesRepository(),
      fs: fs,
      prefs: _BoomPrefs(),
      lock: MemorySyncLock(),
      now: () => DateTime(2026, 10, 13, 10),
      hasSession: () => true,
    );
    expect(await runSamsungSyncTaskWith(broken), isFalse, reason: 'exceção inesperada é engolida');
  });
}
