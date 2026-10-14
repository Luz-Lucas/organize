import 'dart:io';

import 'package:flutter/services.dart';

import 'update_installer.dart';

/// Android: canal `dev.organizacional/update` (ver `UpdateChannel.kt`). O APK fica em `cache/updates/` e é
/// aberto no instalador do sistema; sem a permissão de "apps desconhecidos" o canal abre os ajustes.
class AndroidUpdateInstaller implements UpdateInstaller {
  AndroidUpdateInstaller([MethodChannel? channel]) : _channel = channel ?? const MethodChannel('dev.organizacional/update');

  final MethodChannel _channel;

  @override
  bool get supported => true;
  @override
  String get platform => 'android';

  @override
  Future<Directory> downloadDir() async {
    final path = await _channel.invokeMethod<String>('updatesDir');
    if (path == null) throw StateError('updatesDir indisponível');
    return Directory(path);
  }

  @override
  Future<InstallOutcome> install(File package, {bool promptForPermission = true}) async {
    try {
      final r = await _channel.invokeMethod<String>(
          'install', {'path': package.path, 'promptForPermission': promptForPermission});
      switch (r) {
        case 'started':
          return const InstallOutcome(InstallResult.started);
        case 'needs_permission':
          return const InstallOutcome(
            InstallResult.needsPermission,
            'Para instalar, permita “Instalar apps desconhecidos” para o Organize nos ajustes que abriram e volte para cá.',
          );
        default:
          return const InstallOutcome(InstallResult.failed, 'Não foi possível abrir o instalador do Android.');
      }
    } on PlatformException {
      return const InstallOutcome(InstallResult.failed, 'Não foi possível abrir o instalador do Android.');
    } on MissingPluginException {
      return const InstallOutcome(InstallResult.failed, 'Não foi possível abrir o instalador do Android.');
    }
  }
}
