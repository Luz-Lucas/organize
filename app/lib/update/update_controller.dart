import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../data/repository.dart';
import 'app_release.dart';
import 'update_downloader.dart';
import 'update_installer.dart';
import 'update_providers.dart';

enum UpdatePhase { idle, checking, upToDate, available, downloading, installing, needsPermission, error }

class UpdateState {
  const UpdateState({
    this.phase = UpdatePhase.idle,
    this.release,
    this.progress,
    this.message,
    this.dismissed = false,
  });

  final UpdatePhase phase;

  /// A versão encontrada (também durante o download e depois de um erro nele).
  final AppRelease? release;

  /// 0..1 enquanto baixa; null = sem medida.
  final double? progress;

  /// Aviso para o usuário (erro, instrução de permissão, "em dia").
  final String? message;

  /// O usuário tocou em "Depois" para esta versão.
  final bool dismissed;

  /// O banner do shell aparece? Aviso dispensado fica só no Ajustes; erro de checagem não vira banner.
  bool get showBanner {
    if (release == null) return false;
    return switch (phase) {
      UpdatePhase.available => !dismissed,
      UpdatePhase.downloading || UpdatePhase.installing || UpdatePhase.needsPermission || UpdatePhase.error => true,
      _ => false,
    };
  }

  /// Há algo em andamento que uma nova checagem não deve interromper.
  bool get busy =>
      phase == UpdatePhase.downloading ||
      phase == UpdatePhase.installing ||
      phase == UpdatePhase.checking ||
      phase == UpdatePhase.needsPermission;

  UpdateState copyWith({
    UpdatePhase? phase,
    AppRelease? release,
    double? progress,
    String? message,
    bool? dismissed,
    bool clearMessage = false,
    bool clearProgress = false,
  }) =>
      UpdateState(
        phase: phase ?? this.phase,
        release: release ?? this.release,
        progress: clearProgress ? null : (progress ?? this.progress),
        message: clearMessage ? null : (message ?? this.message),
        dismissed: dismissed ?? this.dismissed,
      );
}

/// Intervalo mínimo entre checagens automáticas.
const updateCheckInterval = Duration(hours: 24);

class UpdateController extends Notifier<UpdateState> {
  DownloadCancelToken? _cancel;
  File? _pending; // pacote já baixado e conferido, à espera de permissão para instalar

  @override
  UpdateState build() => const UpdateState();

  /// Checagem ao abrir o app: no máximo 1 vez a cada 24 h.
  Future<void> checkIfDue() async {
    if (!ref.read(updateInstallerProvider).supported) return;
    final last = await ref.read(updatePrefsProvider).lastCheck();
    if (!ref.mounted) return;
    if (last != null && ref.read(clockProvider)().difference(last) < updateCheckInterval) return;
    await check();
  }

  /// Consulta a release mais nova da plataforma. [manual] mostra o resultado/erro ao usuário.
  Future<void> check({bool manual = false}) async {
    final installer = ref.read(updateInstallerProvider);
    if (!installer.supported || state.busy) return;
    final previous = state;
    state = previous.copyWith(phase: UpdatePhase.checking, clearMessage: true);
    try {
      final installed = await ref.read(installedVersionProvider.future);
      final latest = await ref.read(releaseRepositoryProvider).latest(installer.platform);
      final prefs = ref.read(updatePrefsProvider);
      await prefs.setLastCheck(ref.read(clockProvider)());
      final dismissed = await prefs.dismissedBuild();
      if (!ref.mounted) return;
      if (latest != null && latest.build > installed.build) {
        state = UpdateState(phase: UpdatePhase.available, release: latest, dismissed: dismissed >= latest.build);
      } else {
        state = UpdateState(
          phase: UpdatePhase.upToDate,
          release: latest, // para mostrar as novidades da versão instalada
          message: manual ? 'Você já está na versão mais recente.' : null,
        );
      }
    } catch (_) {
      if (!ref.mounted) return;
      const failure = 'Não foi possível procurar atualização. Verifique a conexão.';
      final keepsRelease = previous.phase == UpdatePhase.available || previous.phase == UpdatePhase.upToDate;
      state = !manual
          ? previous.copyWith(phase: keepsRelease ? previous.phase : UpdatePhase.idle)
          : (keepsRelease
              ? previous.copyWith(message: failure) // a atualização já achada continua disponível
              : const UpdateState(phase: UpdatePhase.error, message: failure));
    }
  }

  /// "Depois": esconde o banner desta versão até sair uma mais nova.
  Future<void> dismiss() async {
    final release = state.release;
    if (release == null || state.phase != UpdatePhase.available) return;
    state = state.copyWith(dismissed: true);
    await ref.read(updatePrefsProvider).setDismissedBuild(release.build);
  }

  void cancelDownload() => _cancel?.cancel();

  /// Fecha a mensagem de erro e volta ao aviso normal da versão.
  void acknowledgeError() {
    if (state.phase == UpdatePhase.error && state.release != null) {
      state = state.copyWith(phase: UpdatePhase.available, clearMessage: true);
    }
  }

  /// Baixa (confere SHA-256 e tamanho) e instala a versão encontrada.
  Future<void> startUpdate() async {
    final release = state.release;
    if (release == null || (state.phase != UpdatePhase.available && state.phase != UpdatePhase.error)) return;
    final installer = ref.read(updateInstallerProvider);
    final token = _cancel = DownloadCancelToken();
    _pending = null;
    state = state.copyWith(phase: UpdatePhase.downloading, progress: 0, clearMessage: true);
    var lastPercent = -1;
    try {
      final url = await ref.read(releaseRepositoryProvider).signedUrl(release.storagePath);
      final dir = await installer.downloadDir();
      final file = await ref.read(updateDownloaderProvider).download(
            url: url,
            target: File('${dir.path}/${_safeName(release.fileName)}'),
            sha256: release.sha256,
            size: release.sizeBytes,
            cancel: token,
            onProgress: (received, total) {
              final percent = total <= 0 ? 0 : (received * 100 ~/ total);
              if (percent == lastPercent || !ref.mounted) return;
              lastPercent = percent;
              state = state.copyWith(progress: total <= 0 ? null : received / total);
            },
          );
      if (!ref.mounted) return;
      state = state.copyWith(phase: UpdatePhase.installing, clearProgress: true);
      await _install(file, prompt: true);
    } on UpdateCancelled {
      if (ref.mounted) state = state.copyWith(phase: UpdatePhase.available, clearProgress: true, clearMessage: true);
    } on UpdateDownloadException catch (e) {
      _fail(e.message);
    } on RepositoryException {
      _fail('Não foi possível obter o link de download. Tente de novo.');
    } catch (_) {
      _fail('Não foi possível baixar a atualização. Tente de novo.');
    } finally {
      _cancel = null;
    }
  }

  /// Tenta instalar de novo o pacote já baixado (ao voltar dos ajustes do Android, ou pelo botão).
  /// [prompt] false não reabre os ajustes do sistema.
  Future<void> retryInstall({bool prompt = false}) async {
    final file = _pending;
    if (file == null || state.phase != UpdatePhase.needsPermission) return;
    await _install(file, prompt: prompt);
  }

  Future<void> _install(File file, {required bool prompt}) async {
    final installer = ref.read(updateInstallerProvider);
    final outcome = await installer.install(file, promptForPermission: prompt);
    if (!ref.mounted) return;
    switch (outcome.result) {
      case InstallResult.started:
        _pending = null;
        state = state.copyWith(
          phase: UpdatePhase.available,
          clearProgress: true,
          message: 'O instalador do Android foi aberto. Confirme a instalação para concluir.',
        );
      case InstallResult.needsPermission:
        _pending = file;
        state = state.copyWith(phase: UpdatePhase.needsPermission, clearProgress: true, message: outcome.message);
      case InstallResult.restarting:
        _pending = null;
        state = state.copyWith(phase: UpdatePhase.installing, message: 'Reiniciando o app para concluir…');
        try {
          if (file.existsSync()) await file.delete();
        } on FileSystemException {
          // só sobra um arquivo no cache
        }
        if (!ref.mounted) return;
        ref.read(updateExitProvider)();
      case InstallResult.failed:
        _pending = null;
        _fail(outcome.message ?? 'Não foi possível instalar a atualização.');
        try {
          if (file.existsSync()) await file.delete();
        } on FileSystemException {
          // idem
        }
    }
  }

  void _fail(String message) {
    if (!ref.mounted) return;
    state = state.copyWith(phase: UpdatePhase.error, clearProgress: true, message: message);
  }

  /// Só caracteres simples no nome do arquivo no disco (o caminho no bucket vem do servidor).
  static String _safeName(String name) => name.replaceAll(RegExp(r'[^A-Za-z0-9._+-]'), '_');
}

final updateControllerProvider = NotifierProvider<UpdateController, UpdateState>(UpdateController.new);
