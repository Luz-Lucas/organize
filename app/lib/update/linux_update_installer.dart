import 'dart:convert';
import 'dart:io';

import 'archive_paths.dart';
import 'update_installer.dart';

/// Linux: o pacote é um `.tar.gz` do bundle do app. Extrai numa pasta irmã (`<app>.new`) e dispara um script
/// (escrito na hora, em pasta 700) que espera o app sair, troca as pastas e relança o app.
class LinuxUpdateInstaller implements UpdateInstaller {
  LinuxUpdateInstaller({
    String? executable,
    int? pid,
    Directory? scriptRoot,
    this.updatesDir,
    Map<String, String>? env,
    RunProcess? run,
    StartDetached? start,
  })  : _executable = executable ?? Platform.resolvedExecutable,
        _pid = pid ?? ProcessInfoPid.current,
        _scriptRoot = scriptRoot ?? Directory.systemTemp,
        _env = env ?? Platform.environment,
        _run = run ?? runProcess,
        _start = start ?? startDetached;

  final String _executable;
  final int _pid;
  final Directory _scriptRoot;
  /// Pasta do pacote baixado; o padrão fica no cache do usuário.
  final Directory? updatesDir;
  final Map<String, String> _env;
  final RunProcess _run;
  final StartDetached _start;

  @override
  bool get supported => true;
  @override
  String get platform => 'linux';

  @override
  Future<Directory> downloadDir() async {
    final fixed = updatesDir;
    if (fixed != null) return fixed;
    final xdg = _env['XDG_CACHE_HOME'];
    final home = _env['HOME'];
    final base = (xdg != null && xdg.startsWith('/'))
        ? xdg
        : (home != null && home.startsWith('/') ? '$home/.cache' : Directory.systemTemp.path);
    return Directory('$base/organizacional/updates');
  }

  static const _script = r'''#!/bin/sh
# Troca a pasta do Organize depois que o app sair. Gerado pelo próprio app a cada atualização.
PID="$1"; APP="$2"; NEW="$3"; EXE="$4"; SELF_DIR="$5"
OLD="$APP.old"
i=0
while kill -0 "$PID" 2>/dev/null; do
  i=$((i + 1))
  if [ "$i" -gt 240 ]; then exit 1; fi
  sleep 0.5
done
rm -rf "$OLD"
if mv "$APP" "$OLD"; then
  if mv "$NEW" "$APP"; then
    rm -rf "$OLD"
  else
    mv "$OLD" "$APP"
  fi
fi
(cd "$APP" 2>/dev/null; nohup "$APP/$EXE" >/dev/null 2>&1 &)
rm -rf "$SELF_DIR"
''';

  @override
  Future<InstallOutcome> install(File package, {bool promptForPermission = true}) async {
    final appDir = parentOf(_executable);
    final exeName = baseName(_executable);
    final staging = Directory('$appDir.new');
    try {
      final unsafe = await _checkPackage(package);
      if (unsafe != null) return unsafe;

      if (staging.existsSync()) await staging.delete(recursive: true);
      await staging.create(recursive: true);
      final x = await _run('tar', ['-xzf', package.path, '-C', staging.path, '--no-same-owner']);
      if (x.exitCode != 0) {
        await _discard(staging);
        return const InstallOutcome(InstallResult.failed, corruptPackageMessage);
      }
      if (!File('${staging.path}/$exeName').existsSync()) {
        await _discard(staging);
        return const InstallOutcome(
            InstallResult.failed, 'O pacote de atualização não contém o app. Nada foi instalado.');
      }

      final dir = await _scriptRoot.createTemp('organize-update-'); // mkdtemp: só o dono acessa (700)
      await _run('chmod', ['700', dir.path]);
      final script = File('${dir.path}/trocar.sh');
      await script.writeAsString(_script);
      await _run('chmod', ['700', script.path]);
      await _start('/bin/sh', [script.path, '$_pid', appDir, staging.path, exeName, dir.path]);
      return const InstallOutcome(InstallResult.restarting);
    } on FileSystemException {
      await _discard(staging);
      return const InstallOutcome(InstallResult.failed, 'Não foi possível preparar a atualização (sem permissão ou espaço).');
    } on ProcessException {
      await _discard(staging);
      return const InstallOutcome(InstallResult.failed, 'Não foi possível preparar a atualização (falta o programa tar).');
    }
  }

  Future<void> _discard(Directory d) async {
    try {
      if (d.existsSync()) await d.delete(recursive: true);
    } on FileSystemException {
      // sem o que fazer: a próxima tentativa recomeça a pasta
    }
  }

  /// `tar -tzf` precisa listar sem erro, com nomes seguros; e nada além de arquivos e pastas (sem links).
  Future<InstallOutcome?> _checkPackage(File package) async {
    final names = await _run('tar', ['-tzf', package.path]);
    if (names.exitCode != 0) return const InstallOutcome(InstallResult.failed, corruptPackageMessage);
    final bad = validateArchiveEntries(const LineSplitter().convert('${names.stdout}').where((l) => l.isNotEmpty));
    if (bad != null) return const InstallOutcome(InstallResult.failed, unsafePackageMessage);
    final verbose = await _run('tar', ['-tvzf', package.path]);
    if (verbose.exitCode != 0) return const InstallOutcome(InstallResult.failed, corruptPackageMessage);
    for (final line in const LineSplitter().convert('${verbose.stdout}')) {
      if (line.isEmpty) continue;
      final kind = line[0];
      if (kind != '-' && kind != 'd') return const InstallOutcome(InstallResult.failed, unsafePackageMessage);
    }
    return null;
  }
}

/// Atalho para o PID do processo atual (`pid` do dart:io).
abstract final class ProcessInfoPid {
  static int get current => pid;
}
