import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_drive_repository.dart';
import '../../data/supabase_imported_files_repository.dart';
import '../../data/supabase_repository.dart';
import 'device_file_system.dart';
import 'samsung_platform.dart';
import 'samsung_sync_service.dart';
import 'samsung_sync_settings.dart';
import 'sync_lock.dart';

/// Nome da tarefa periódica do workmanager (roteada em `callbackDispatcher`).
const samsungSyncTask = 'samsungNotesSync';
const samsungSyncUniqueName = 'samsung-notes-sync';

/// Frequência mínima permitida pelo Android para trabalho periódico.
const samsungSyncFrequency = Duration(minutes: 15);

/// Arquivo da trava de "uma sincronização por vez", comum ao app e à tarefa em segundo plano
/// (no Android o diretório temporário é o cache do app, compartilhado pelos dois isolates).
File samsungSyncLockFile() => File('${Directory.systemTemp.path}/organizacional_samsung_sync.lock');

/// Dependências da tarefa em segundo plano. Lá o canal nativo não existe: pastas escolhidas pelo seletor só
/// são lidas pelo caminho equivalente (precisa de "Acesso a todos os arquivos").
SamsungSyncDeps samsungSyncDepsFor(SupabaseClient client) => SamsungSyncDeps(
      repo: SupabaseRepository(client),
      drive: SupabaseDriveRepository(client),
      imported: SupabaseImportedFilesRepository(client),
      fs: DeviceFolderFileSystem(platform: MethodChannelSamsungNotesPlatform()),
      prefs: SharedPreferencesSamsungSyncPrefs(),
      lock: FileSyncLock(samsungSyncLockFile()),
      now: DateTime.now,
      hasSession: () => client.auth.currentSession != null,
      device: 'android',
    );

/// Uma rodada em segundo plano. Devolve se a sincronização rodou; toda falha é engolida
/// (sem sessão, Drive desconectado, chave desligada... não são erros: a próxima rodada tenta de novo).
Future<bool> runSamsungSyncTaskWith(SamsungSyncDeps deps) async {
  try {
    final outcome = await runSamsungSync(deps);
    return outcome.status == SamsungSyncStatus.ran;
  } catch (_) {
    return false;
  }
}

/// Ponto de entrada da tarefa `samsungNotesSync` (cliente já inicializado).
Future<bool> runSamsungSyncTask(SupabaseClient? client) {
  if (client == null) return Future.value(false);
  return runSamsungSyncTaskWith(samsungSyncDepsFor(client));
}
