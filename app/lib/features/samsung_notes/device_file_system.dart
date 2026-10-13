import 'dart:io';

import 'folder_sync.dart';
import 'samsung_folder.dart';
import 'samsung_platform.dart';

/// Lê a pasta vigiada no aparelho: por caminho (`dart:io`, vale também no segundo plano) ou, para pastas
/// escolhidas no seletor do Android, pelo SAF via canal (só com o app aberto) — com o caminho equivalente
/// (`uriToPath`) como alternativa quando há "Acesso a todos os arquivos".
class DeviceFolderFileSystem implements FolderFileSystem {
  DeviceFolderFileSystem({this._platform, String? Function(String uri)? uriToPathOverride}) : _uriToPath = uriToPathOverride ?? uriToPath;

  final SamsungNotesPlatform? _platform;
  final String? Function(String uri) _uriToPath;

  @override
  Future<List<SyncEntry>> list(SamsungFolder folder) async {
    final uri = folder.uri;
    if (uri != null) {
      final platform = _platform;
      if (platform != null) {
        try {
          return await platform.listTree(uri);
        } on FolderAccessException {
          // sem o canal (segundo plano) ou sem a permissão do seletor: tenta o caminho equivalente
        }
      }
      final path = folder.path ?? _uriToPath(uri);
      if (path == null) {
        throw const FolderAccessException('Sem acesso à pasta. Abra o app e escolha a pasta de novo em Ajustes.');
      }
      return _listPath(path);
    }
    return _listPath(folder.path!);
  }

  Future<List<SyncEntry>> _listPath(String path) async {
    final dir = Directory(path);
    try {
      if (!await dir.exists()) throw const FolderAccessException('Não encontrei a pasta. Escolha a pasta de novo em Ajustes.');
      final out = <SyncEntry>[];
      await for (final e in dir.list(followLinks: false)) {
        if (e is! File) continue;
        final stat = await e.stat();
        out.add(SyncEntry(
          id: e.path,
          name: e.uri.pathSegments.last,
          size: stat.size,
          modified: stat.modified,
        ));
      }
      return out;
    } on FileSystemException {
      throw const FolderAccessException('Sem permissão para ler a pasta. Conceda "Acesso a todos os arquivos" em Ajustes.');
    }
  }

  @override
  Future<SyncSource> open(SamsungFolder folder, SyncEntry entry) async {
    if (entry.id.startsWith('content://')) {
      final platform = _platform;
      final copy = platform == null ? null : await platform.copyToCache(entry.id);
      if (copy == null) throw const FolderAccessException('Não foi possível ler o arquivo.');
      return _FileSource(File(copy), deleteOnClose: true);
    }
    return _FileSource(File(entry.id), deleteOnClose: false);
  }
}

class _FileSource implements SyncSource {
  _FileSource(this._file, {required this.deleteOnClose}) : size = _file.lengthSync();

  final File _file;
  final bool deleteOnClose;

  @override
  final int size;

  @override
  Stream<List<int>> read() => _file.openRead();

  @override
  Future<void> close() async {
    if (!deleteOnClose) return;
    try {
      await _file.delete();
    } on FileSystemException {
      // já removida
    }
  }
}
