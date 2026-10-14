/// Uma versão publicada (linha de `app_releases`).
class AppRelease {
  const AppRelease({
    required this.id,
    required this.platform,
    required this.version,
    required this.build,
    required this.storagePath,
    required this.sha256,
    required this.sizeBytes,
    this.notes = '',
  });

  final String id;

  /// `android`, `linux` ou `windows`.
  final String platform;
  final String version;
  final int build;

  /// Caminho no bucket privado `app-releases`: `<plataforma>/<build>/<arquivo>`.
  final String storagePath;
  final String sha256;
  final int sizeBytes;
  final String notes;

  factory AppRelease.fromJson(Map<String, dynamic> json) => AppRelease(
        id: json['id'] as String,
        platform: json['platform'] as String,
        version: json['version'] as String,
        build: (json['build'] as num).toInt(),
        storagePath: json['storage_path'] as String,
        sha256: (json['sha256'] as String).toLowerCase(),
        sizeBytes: int.parse('${json['size_bytes']}'.split('.').first),
        notes: (json['notes'] as String?) ?? '',
      );

  /// Nome do arquivo (último trecho do caminho no bucket).
  String get fileName => storagePath.split('/').last;
}

/// Versão instalada neste aparelho (`package_info_plus`): `version` é o X.Y.Z, `build` o versionCode.
class InstalledVersion {
  const InstalledVersion(this.label, this.build);

  /// X.Y.Z.
  final String label;
  final int build;

  /// Monta a partir do `package_info_plus`. No Android o build publicado é o `+N` do pubspec, mas o APK por ABI
  /// (`--split-per-abi`) leva `versionCode = 1000 * ABI + N` (arm64 = 2001, 2002...); tirar o deslocamento
  /// devolve o N. Por isso o `+N` do pubspec precisa ficar abaixo de 1000.
  factory InstalledVersion.fromPackageInfo(String version, String buildNumber, {required bool android}) {
    final code = int.tryParse(buildNumber) ?? 0;
    return InstalledVersion(version, android ? code % 1000 : code);
  }
}
