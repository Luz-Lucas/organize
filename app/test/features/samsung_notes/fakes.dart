import 'dart:async';

import 'package:organizacional/domain/drive.dart';
import 'package:organizacional/data/memory_drive_repository.dart';
import 'package:organizacional/features/samsung_notes/folder_sync.dart';
import 'package:organizacional/features/samsung_notes/samsung_folder.dart';
import 'package:organizacional/features/samsung_notes/samsung_platform.dart';

/// "Sistema de arquivos" em memória para o motor de sincronização.
class FakeFolderFileSystem implements FolderFileSystem {
  final _files = <String, ({List<int> bytes, DateTime modified})>{};
  final opened = <String>[];
  int closed = 0;
  Object? listError;

  void put(String name, List<int> bytes, {DateTime? modified}) {
    _files[name] = (bytes: bytes, modified: modified ?? DateTime(2026, 10, 13, 8));
  }

  void remove(String name) => _files.remove(name);

  @override
  Future<List<SyncEntry>> list(SamsungFolder folder) async {
    final err = listError;
    if (err != null) throw err;
    return [
      for (final e in _files.entries) SyncEntry(id: e.key, name: e.key, size: e.value.bytes.length, modified: e.value.modified),
    ];
  }

  @override
  Future<SyncSource> open(SamsungFolder folder, SyncEntry entry) async {
    opened.add(entry.name);
    final bytes = _files[entry.id]!.bytes;
    return _FakeSource(bytes, () => closed++);
  }
}

class _FakeSource implements SyncSource {
  _FakeSource(this._bytes, this._onClose);

  final List<int> _bytes;
  final void Function() _onClose;

  @override
  int get size => _bytes.length;

  @override
  Stream<List<int>> read() async* {
    // Em pedaços pequenos, para exercitar o hash em streaming.
    final step = _bytes.length > 4096 ? 65536 : 3;
    for (var i = 0; i < _bytes.length; i += step) {
      yield _bytes.sublist(i, i + step > _bytes.length ? _bytes.length : i + step);
    }
  }

  @override
  Future<void> close() async => _onClose();
}

/// Drive em memória que conta as chamadas de `ensurePath` e pode falhar só no upload.
class CountingDriveRepository extends MemoryDriveRepository {
  CountingDriveRepository({super.state});

  int ensurePathCalls = 0;
  int findCalls = 0;
  bool failUploads = false;
  Object? uploadError;

  @override
  Future<String> ensurePath(List<String> path) {
    ensurePathCalls++;
    return super.ensurePath(path);
  }

  @override
  Future<DriveItem?> findBySha256(String sha256) {
    findCalls++;
    return super.findBySha256(sha256);
  }

  @override
  Future<UploadedFile> upload({
    required String parentId,
    required String name,
    required String mimeType,
    required int size,
    required Stream<List<int>> data,
    void Function(int sent, int total)? onProgress,
    Map<String, String>? appProperties,
  }) {
    final err = uploadError;
    if (err != null) throw err;
    if (failUploads) throw StateError('falha simulada no upload');
    return super.upload(
      parentId: parentId,
      name: name,
      mimeType: mimeType,
      size: size,
      data: data,
      onProgress: onProgress,
      appProperties: appProperties,
    );
  }
}

/// Plataforma Android falsa: o que o canal nativo responderia.
class FakeSamsungPlatform implements SamsungNotesPlatform {
  bool allFiles = true;
  bool installed = true;
  List<String> found = [];
  SamsungFolder? picked;
  int requestCalls = 0;
  int openCalls = 0;
  int pickCalls = 0;

  @override
  Future<bool> isInstalled() async => installed;
  @override
  Future<bool> open() async {
    openCalls++;
    return true;
  }

  @override
  Future<bool> hasAllFilesAccess() async => allFiles;
  @override
  Future<bool> requestAllFilesAccess() async {
    requestCalls++;
    return true;
  }

  @override
  Future<List<String>> findFolders() async => found;
  @override
  Future<SamsungFolder?> pickFolder() async {
    pickCalls++;
    return picked;
  }

  @override
  Future<List<SyncEntry>> listTree(String uri) async => throw const FolderAccessException('x');
  @override
  Future<String?> copyToCache(String uri) async => null;
  @override
  Future<String?> deviceName() async => 'SM-X200';
}

