import 'dart:async';
import 'dart:io';

import 'package:organizacional/update/app_release.dart';
import 'package:organizacional/update/update_downloader.dart';
import 'package:organizacional/update/update_installer.dart';

AppRelease release({int build = 5, String version = '1.1.0', String platform = 'android', String notes = 'Caderno novo', int size = 100}) =>
    AppRelease(
      id: 'r$build',
      platform: platform,
      version: version,
      build: build,
      storagePath: '$platform/$build/organizacional-$version+$build.apk',
      sha256: 'a' * 64,
      sizeBytes: size,
      notes: notes,
    );

class FakeInstaller implements UpdateInstaller {
  FakeInstaller({this.supported = true, this.platform = 'android', Directory? dir}) : dir = dir ?? Directory.systemTemp;

  @override
  bool supported;
  @override
  String platform;
  Directory dir;

  /// Respostas em sequência (a última se repete).
  List<InstallOutcome> outcomes = [const InstallOutcome(InstallResult.started)];
  final installs = <({String path, bool prompt})>[];

  @override
  Future<Directory> downloadDir() async => dir;

  @override
  Future<InstallOutcome> install(File package, {bool promptForPermission = true}) async {
    installs.add((path: package.path, prompt: promptForPermission));
    final i = installs.length - 1;
    return outcomes[i < outcomes.length ? i : outcomes.length - 1];
  }
}

/// Baixador falso: não usa rede nem disco além de criar o arquivo-alvo.
class FakeDownloader implements UpdateDownloader {
  /// Se definido, o download espera aqui (para ver o progresso e cancelar).
  Completer<void>? gate;
  Object? error;
  final progressSteps = <double>[0.25, 0.5];
  final calls = <({Uri url, String path, String sha256, int size})>[];
  int created = 0;

  @override
  Future<File> download({
    required Uri url,
    required File target,
    required String sha256,
    required int size,
    DownloadProgress? onProgress,
    DownloadCancelToken? cancel,
  }) async {
    calls.add((url: url, path: target.path, sha256: sha256, size: size));
    for (final p in progressSteps) {
      onProgress?.call((size * p).round(), size);
    }
    final g = gate;
    if (g != null) {
      await Future.any([g.future, if (cancel != null) cancel.whenCancelled]);
      if (cancel?.isCancelled ?? false) throw const UpdateCancelled();
    }
    final e = error;
    if (e != null) throw e;
    target.parent.createSync(recursive: true);
    target.writeAsBytesSync([1, 2, 3]);
    created++;
    onProgress?.call(size, size);
    return target;
  }
}
