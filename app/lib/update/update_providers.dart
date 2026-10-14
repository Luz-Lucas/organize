import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app_release.dart';
import 'release_repository.dart';
import 'update_downloader.dart';
import 'update_installer.dart';
import 'update_prefs.dart';

/// Padrões inertes (testes e plataformas sem atualização): `main.dart` liga os de verdade.
final releaseRepositoryProvider = Provider<ReleaseRepository>((ref) => MemoryReleaseRepository());

final updateInstallerProvider = Provider<UpdateInstaller>((ref) => const NoopUpdateInstaller());

final updateDownloaderProvider = Provider<UpdateDownloader>((ref) => HttpUpdateDownloader());

final updatePrefsProvider = Provider<UpdatePrefsStore>((ref) => MemoryUpdatePrefs());

/// Sai do app depois que a troca de pastas foi disparada (Linux/Windows). Nos testes não faz nada.
final updateExitProvider = Provider<void Function()>((ref) => () {});

/// Quem informa a versão instalada. O padrão (testes) é 0.0.0+0; `main.dart` usa o `package_info_plus`.
final installedVersionLoaderProvider =
    Provider<Future<InstalledVersion> Function()>((ref) => () async => const InstalledVersion('0.0.0', 0));

final installedVersionProvider =
    FutureProvider<InstalledVersion>((ref) => ref.watch(installedVersionLoaderProvider)());

/// Lê a versão (X.Y.Z) e o build (versionCode) do pacote instalado.
Future<InstalledVersion> loadInstalledVersionFromPlatform() async {
  final info = await PackageInfo.fromPlatform();
  return InstalledVersion.fromPackageInfo(info.version, info.buildNumber, android: !kIsWeb && Platform.isAndroid);
}
