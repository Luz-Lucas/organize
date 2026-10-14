import 'dart:io';

import 'package:archive/archive.dart';

import 'archive_paths.dart';
import 'linux_update_installer.dart' show ProcessInfoPid;
import 'update_installer.dart';

/// Windows: o pacote é um `.zip` do bundle. Extrai (em Dart) numa pasta irmã (`<app>.new`) e dispara um `.cmd`
/// em `%TEMP%` que espera o processo sair, troca as pastas com `move` e relança o `.exe`.
class WindowsUpdateInstaller implements UpdateInstaller {
  WindowsUpdateInstaller({
    String? executable,
    int? pid,
    Directory? scriptRoot,
    this.updatesDir,
    Map<String, String>? env,
    StartDetached? start,
  })  : _executable = executable ?? Platform.resolvedExecutable,
        _pid = pid ?? ProcessInfoPid.current,
        _scriptRoot = scriptRoot ?? Directory.systemTemp,
        _env = env ?? Platform.environment,
        _start = start ?? startDetached;

  final String _executable;
  final int _pid;
  final Directory _scriptRoot;
  /// Pasta do pacote baixado; o padrão fica no cache do usuário.
  final Directory? updatesDir;
  final Map<String, String> _env;
  final StartDetached _start;

  /// Teto do que o pacote pode ocupar depois de extraído (contra "bomba" de compressão).
  static const maxUnpackedBytes = 2 * 1024 * 1024 * 1024;

  @override
  bool get supported => true;
  @override
  String get platform => 'windows';

  @override
  Future<Directory> downloadDir() async {
    final fixed = updatesDir;
    if (fixed != null) return fixed;
    final base = _env['LOCALAPPDATA'] ?? _env['APPDATA'];
    if (base == null) return Directory('${Directory.systemTemp.path}\\Organize\\updates');
    return Directory('$base\\Organize\\updates');
  }

  @override
  Future<InstallOutcome> install(File package, {bool promptForPermission = true}) async {
    final appDir = parentOf(_executable);
    final exeName = baseName(_executable);
    final staging = Directory('$appDir.new');
    try {
      final Archive archive;
      try {
        archive = ZipDecoder().decodeBytes(await package.readAsBytes());
      } catch (_) {
        return const InstallOutcome(InstallResult.failed, corruptPackageMessage);
      }
      if (validateArchiveEntries(archive.files.map((f) => f.name)) != null ||
          archive.files.any((f) => f.isSymbolicLink || (f.mode & 0xF000) == 0xA000)) {
        return const InstallOutcome(InstallResult.failed, unsafePackageMessage);
      }
      var total = 0;
      for (final f in archive.files) {
        total += f.size;
      }
      if (total > maxUnpackedBytes) {
        return const InstallOutcome(InstallResult.failed, 'O pacote de atualização é grande demais e foi recusado.');
      }

      if (staging.existsSync()) await staging.delete(recursive: true);
      await staging.create(recursive: true);
      for (final f in archive.files) {
        final name = f.name.replaceAll(r'\', '/').replaceFirst(RegExp(r'^(\./)+'), '');
        if (name.isEmpty) continue;
        if (!f.isFile || name.endsWith('/')) {
          await Directory('${staging.path}/$name').create(recursive: true);
          continue;
        }
        final out = File('${staging.path}/$name');
        await out.parent.create(recursive: true);
        await out.writeAsBytes(f.readBytes() ?? const []);
      }
      if (!File('${staging.path}/$exeName').existsSync()) {
        await _discard(staging);
        return const InstallOutcome(
            InstallResult.failed, 'O pacote de atualização não contém o app. Nada foi instalado.');
      }

      final script = File('${(await _scriptRoot.createTemp('organize-update-')).path}/trocar.cmd');
      await script.writeAsString(_script(appDir, staging.path, exeName), flush: true);
      await _start('cmd.exe', ['/d', '/c', script.path]);
      return const InstallOutcome(InstallResult.restarting);
    } on FileSystemException {
      await _discard(staging);
      return const InstallOutcome(InstallResult.failed, 'Não foi possível preparar a atualização (sem permissão ou espaço).');
    }
  }

  Future<void> _discard(Directory d) async {
    try {
      if (d.existsSync()) await d.delete(recursive: true);
    } on FileSystemException {
      // a próxima tentativa recomeça a pasta
    }
  }

  /// Valor seguro para `set "X=..."`: `%` dobrado; aspas e quebras de linha não existem em caminhos válidos.
  static String _cmd(String path) =>
      path.replaceAll('/', r'\').replaceAll('%', '%%').replaceAll('"', '').replaceAll(RegExp(r'[\r\n]'), '');

  String _script(String app, String staging, String exe) {
    final a = _cmd(app);
    return '@echo off\r\n'
        'rem Troca a pasta do Organize depois que o app sair. Gerado pelo próprio app a cada atualização.\r\n'
        'setlocal\r\n'
        'set "PID=$_pid"\r\n'
        'set "APP=$a"\r\n'
        'set "NEW=${_cmd(staging)}"\r\n'
        'set "OLD=$a.old"\r\n'
        'set "EXE=${_cmd(exe)}"\r\n'
        'set /a TRIES=0\r\n'
        ':wait\r\n'
        'tasklist /FI "PID eq %PID%" /FO CSV /NH 2>nul | find """%PID%""" >nul\r\n'
        'if errorlevel 1 goto swap\r\n'
        'set /a TRIES+=1\r\n'
        'if %TRIES% GTR 240 goto relaunch\r\n'
        'timeout /t 1 /nobreak >nul 2>&1 || ping -n 2 127.0.0.1 >nul\r\n'
        'goto wait\r\n'
        ':swap\r\n'
        'if exist "%OLD%" rmdir /s /q "%OLD%"\r\n'
        'set /a TRIES=0\r\n'
        ':movetry\r\n'
        'move "%APP%" "%OLD%" >nul 2>&1\r\n'
        'if not errorlevel 1 goto movenew\r\n'
        'set /a TRIES+=1\r\n'
        'if %TRIES% GTR 20 goto relaunch\r\n'
        'timeout /t 1 /nobreak >nul 2>&1 || ping -n 2 127.0.0.1 >nul\r\n'
        'goto movetry\r\n'
        ':movenew\r\n'
        'move "%NEW%" "%APP%" >nul 2>&1\r\n'
        'if errorlevel 1 (\r\n'
        '  move "%OLD%" "%APP%" >nul 2>&1\r\n'
        '  goto relaunch\r\n'
        ')\r\n'
        'rmdir /s /q "%OLD%"\r\n'
        ':relaunch\r\n'
        'start "" "%APP%\\%EXE%"\r\n'
        '(goto) 2>nul & del "%~f0"\r\n';
  }
}
