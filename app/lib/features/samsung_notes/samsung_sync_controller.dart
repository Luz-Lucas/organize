import 'dart:async';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/directory_picker_service.dart';
import '../../data/drive_repository.dart';
import '../../data/imported_files_repository.dart';
import '../../location/location_report_sync.dart' show locationSignedInProvider;
import 'device_file_system.dart';
import 'folder_sync.dart';
import 'samsung_folder.dart';
import 'samsung_platform.dart';
import 'samsung_sync_service.dart';
import 'samsung_sync_settings.dart';
import 'sync_lock.dart';

/// Liga e desliga a tarefa periódica em segundo plano (workmanager, só no Android).
abstract interface class SamsungBackgroundScheduler {
  Future<void> schedule();
  Future<void> cancel();
}

class NoopSamsungBackgroundScheduler implements SamsungBackgroundScheduler {
  const NoopSamsungBackgroundScheduler();

  @override
  Future<void> schedule() async {}
  @override
  Future<void> cancel() async {}
}

final samsungSyncPrefsProvider = Provider<SamsungSyncPrefs>((ref) => MemorySamsungSyncPrefs());

final samsungFolderFsProvider = Provider<FolderFileSystem>(
  (ref) => DeviceFolderFileSystem(platform: ref.watch(samsungNotesPlatformProvider)),
);

/// `main.dart` troca pela trava em arquivo (vale também para a tarefa em segundo plano).
final samsungSyncLockProvider = Provider<SyncLock>((ref) => MemorySyncLock());

final samsungBackgroundSchedulerProvider = Provider<SamsungBackgroundScheduler>((ref) => const NoopSamsungBackgroundScheduler());

bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Antes de uma nova sincronização automática ao voltar para o app.
const samsungForegroundMinInterval = Duration(minutes: 1);

class SamsungSyncUiState {
  const SamsungSyncUiState({this.loaded = false, this.settings = const SamsungSyncSettings(), this.syncing = false, this.message});

  final bool loaded;
  final SamsungSyncSettings settings;
  final bool syncing;

  /// Resultado ou orientação para mostrar no cartão.
  final String? message;

  SamsungSyncUiState copyWith({bool? loaded, SamsungSyncSettings? settings, bool? syncing, String? message, bool clearMessage = false}) =>
      SamsungSyncUiState(
        loaded: loaded ?? this.loaded,
        settings: settings ?? this.settings,
        syncing: syncing ?? this.syncing,
        message: clearMessage ? null : (message ?? this.message),
      );
}

/// Texto para um resultado de [runSamsungSync] que o usuário pediu (null = nada a dizer).
String? samsungOutcomeMessage(SamsungSyncOutcome o) => switch (o.status) {
      SamsungSyncStatus.ran => o.result!.needsReconnect ? driveExpiredMessage : o.result!.text,
      SamsungSyncStatus.noFolder => 'Escolha a pasta dos arquivos primeiro.',
      SamsungSyncStatus.driveNotReady => 'Conecte o Google Drive para sincronizar.',
      SamsungSyncStatus.busy => 'Já existe uma sincronização em andamento.',
      SamsungSyncStatus.noSession => 'Entre na sua conta para sincronizar.',
      SamsungSyncStatus.disabled => null,
    };

class SamsungSyncController extends Notifier<SamsungSyncUiState> {
  DateTime? _lastForeground;
  String? _device;

  @override
  SamsungSyncUiState build() {
    Future.microtask(reload);
    return const SamsungSyncUiState();
  }

  SamsungNotesPlatform get _platform => ref.read(samsungNotesPlatformProvider);
  SamsungSyncPrefs get _prefs => ref.read(samsungSyncPrefsProvider);

  /// Relê as configurações do aparelho (a tarefa em segundo plano também as altera).
  Future<void> reload() async {
    final settings = await _prefs.load();
    if (!ref.mounted) return;
    state = state.copyWith(loaded: true, settings: settings);
    // O agendamento é "atualizar": reagendar ao abrir o app é inofensivo e garante a tarefa depois de reinstalar.
    if (settings.enabled) unawaited(ref.read(samsungBackgroundSchedulerProvider).schedule().catchError((_) {}));
  }

  void setMessage(String? message) {
    if (ref.mounted) state = state.copyWith(message: message, clearMessage: message == null);
  }

  Future<void> setEnabled(bool enabled) async {
    await _prefs.setEnabled(enabled);
    final scheduler = ref.read(samsungBackgroundSchedulerProvider);
    try {
      if (enabled) {
        await scheduler.schedule();
      } else {
        await scheduler.cancel();
      }
    } catch (_) {
      // sem a tarefa em segundo plano ainda sincroniza ao abrir o app
    }
    if (!ref.mounted) return;
    state = state.copyWith(settings: await _prefs.load(), clearMessage: true);
    if (enabled) await sync();
  }

  Future<void> useFolder(SamsungFolder folder) async {
    await _prefs.setFolder(folder);
    if (!ref.mounted) return;
    state = state.copyWith(settings: await _prefs.load(), clearMessage: true);
    if (state.settings.enabled) await sync();
  }

  Future<bool> hasAllFilesAccess() => _platform.hasAllFilesAccess();
  Future<bool> requestAllFilesAccess() => _platform.requestAllFilesAccess();
  Future<List<String>> findCandidates() => _platform.findFolders();

  /// Seletor de pasta: o do sistema (SAF) no Android; o do file_picker no computador.
  Future<SamsungFolder?> pickFolder() async {
    if (_isAndroid) return _platform.pickFolder();
    final path = await ref.read(directoryPickerProvider).pickDirectory();
    return path == null || path.isEmpty ? null : SamsungFolder(path: path);
  }

  /// Sincronização pedida pelo usuário ([force] ignora a chave) ou disparada ao ligar/trocar de pasta.
  Future<SamsungSyncOutcome> sync({bool force = false}) async {
    if (state.syncing) return const SamsungSyncOutcome(SamsungSyncStatus.busy);
    state = state.copyWith(syncing: true, clearMessage: true);
    SamsungSyncOutcome outcome;
    try {
      _device ??= await _platform.deviceName();
      outcome = await runSamsungSync(_deps(), force: force);
    } catch (_) {
      outcome = SamsungSyncOutcome(SamsungSyncStatus.ran, SyncResult()..errors.add('Não foi possível sincronizar.'));
    }
    if (!ref.mounted) return outcome;
    state = state.copyWith(syncing: false, settings: await _prefs.load(), message: samsungOutcomeMessage(outcome));
    return outcome;
  }

  /// Ao abrir/retomar o app: sincroniza se a chave está ligada, no máximo uma vez por [samsungForegroundMinInterval].
  Future<void> syncIfDue() async {
    final now = ref.read(clockProvider)();
    final last = _lastForeground;
    if (last != null && now.difference(last) < samsungForegroundMinInterval) return;
    _lastForeground = now;
    await sync();
  }

  SamsungSyncDeps _deps() => SamsungSyncDeps(
        repo: ref.read(repositoryProvider),
        drive: ref.read(driveRepositoryProvider),
        imported: ref.read(importedFilesRepositoryProvider),
        fs: ref.read(samsungFolderFsProvider),
        prefs: _prefs,
        lock: ref.read(samsungSyncLockProvider),
        now: ref.read(clockProvider),
        hasSession: ref.read(locationSignedInProvider),
        device: _device,
      );
}

final samsungSyncControllerProvider = NotifierProvider<SamsungSyncController, SamsungSyncUiState>(SamsungSyncController.new);

/// Com o app aberto: sincroniza ao abrir e ao voltar para ele (se a chave estiver ligada).
final samsungForegroundSyncProvider = Provider<void>((ref) {
  final observer = _ResumeObserver(() => unawaited(ref.read(samsungSyncControllerProvider.notifier).syncIfDue()));
  WidgetsBinding.instance.addObserver(observer);
  ref.onDispose(() => WidgetsBinding.instance.removeObserver(observer));
  // No primeiro quadro: o Supabase/ajustes já estão prontos.
  Future.microtask(() {
    if (ref.mounted) unawaited(ref.read(samsungSyncControllerProvider.notifier).syncIfDue());
  });
});

class _ResumeObserver with WidgetsBindingObserver {
  _ResumeObserver(this.onResume);

  final VoidCallback onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }
}
