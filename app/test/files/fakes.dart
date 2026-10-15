import 'dart:async';
import 'dart:typed_data';

import 'package:organizacional/data/drive_repository.dart';
import 'package:organizacional/data/memory_drive_repository.dart';
import 'package:organizacional/domain/drive.dart';
import 'package:organizacional/files/drive_cache.dart';
import 'package:organizacional/files/drive_file_opener.dart';
import 'package:organizacional/files/files_platform.dart';

/// Plataforma de arquivos falsa: guarda o que foi pedido para abrir.
class FakeFilesPlatform implements FilesPlatform {
  FakeFilesPlatform({this.root = '/tmp/nao-usado/drive_cache', this.supported = true});

  String? root;
  @override
  bool supported;

  /// O que `openFile` responde (false = nenhum app resolveu o arquivo).
  bool openResult = true;
  final opened = <({String path, String mime})>[];

  @override
  Future<String?> cacheRoot() async => root;

  @override
  Future<bool> openFile(String path, String mime) async {
    opened.add((path: path, mime: mime));
    return openResult;
  }
}

/// Drive em memória cujo download espera o [gate] e pode devolver outros bytes.
class ControlledDrive extends MemoryDriveRepository {
  ControlledDrive({this.gate, this.bytesOverride, this.downloadError});

  Future<void>? gate;
  List<int>? bytesOverride;
  Object? downloadError;

  @override
  Future<Uint8List> download(String id) async {
    final g = gate;
    if (g != null) await g;
    final err = downloadError;
    if (err != null) throw err;
    final real = await super.download(id);
    final o = bytesOverride;
    return o == null ? real : Uint8List.fromList(o);
  }
}

/// Abridor falso para os testes de tela: registra os ids pedidos e responde o que o teste mandar.
class FakeDriveFileOpener implements DriveFileOpener {
  OpenResult result = const OpenResult(OpenOutcome.opened);

  /// Se definido, `open` avisa `onDownloading` com isto e espera [gate].
  DriveFileMeta? downloading;
  Future<void>? gate;
  final opened = <String>[];

  @override
  DriveRepository get drive => throw UnimplementedError();
  @override
  FilesPlatform get platform => throw UnimplementedError();
  @override
  DriveCache get cache => throw UnimplementedError();

  @override
  Future<OpenResult> open(String fileId, {OpenCancel? cancel, void Function(DriveFileMeta meta)? onDownloading}) async {
    opened.add(fileId);
    final d = downloading;
    if (d != null) onDownloading?.call(d);
    final g = gate;
    if (g != null) await g;
    if (cancel?.isCancelled ?? false) return const OpenResult(OpenOutcome.cancelled);
    return result;
  }
}

/// Cache falso para os testes de tela: só o tamanho e o "limpar".
class FakeDriveCache extends DriveCache {
  FakeDriveCache(this.bytes) : super.at('/nao-usado');

  int bytes;
  int clears = 0;

  @override
  Future<int> totalBytes() async => bytes;

  @override
  Future<void> clear() async {
    clears++;
    bytes = 0;
  }
}
