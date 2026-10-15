import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/drive.dart';
import 'file_names.dart';

/// Acima disso, os arquivos abertos há mais tempo saem do aparelho (1 GB).
const driveCacheMaxBytes = 1024 * 1024 * 1024;

final _idRe = RegExp(r'^[A-Za-z0-9_-]{1,200}$');
const _indexName = 'index.json';

/// Não há pasta onde guardar os arquivos neste aparelho.
class DriveCacheUnavailable implements Exception {
  const DriveCacheUnavailable();

  @override
  String toString() => 'DriveCacheUnavailable';
}

/// Um arquivo do Drive guardado no aparelho.
class CachedFile {
  const CachedFile({
    required this.fileId,
    required this.name,
    required this.size,
    required this.path,
    required this.lastOpened,
    this.modifiedTime,
    this.md5,
  });

  final String fileId;

  /// Nome original no Drive (no disco o nome passa por [safeFileName]).
  final String name;
  final int size;

  /// Caminho absoluto, sempre dentro da pasta do cache.
  final String path;
  final DateTime lastOpened;
  final DateTime? modifiedTime;
  final String? md5;

  /// Os metadados que o Drive tinha quando o arquivo foi baixado.
  DriveFileMeta toMeta() => DriveFileMeta(id: fileId, name: name, size: size, modifiedTime: modifiedTime, md5: md5);
}

/// Cache persistente dos arquivos do Drive abertos no aparelho: `<raiz>/<fileId>/<nome seguro>` e o índice
/// `<raiz>/index.json` (`{fileId: {name, size, modifiedTime, md5, path, lastOpened}}`). A raiz não é o `cache/`
/// do sistema (o Android pode limpá-lo); a limpeza é por nossa conta: [clear] e o limite [maxBytes] (LRU).
///
/// Segurança: o id só aceita `[A-Za-z0-9_-]`, o nome passa por [safeFileName] e o caminho lido do índice só vale
/// se, resolvidos os links, ficar dentro da raiz e for um arquivo comum (links simbólicos não são seguidos).
class DriveCache {
  DriveCache.at(String root, {DateTime Function()? now, this.maxBytes = driveCacheMaxBytes})
      : _resolveRoot = (() async => root),
        _now = now ?? DateTime.now;

  /// A raiz só é pedida quando preciso (ex.: o canal nativo). Se devolver null, o cache fica indisponível.
  DriveCache.lazy(Future<String?> Function() resolveRoot, {DateTime Function()? now, this.maxBytes = driveCacheMaxBytes})
      : _resolveRoot = resolveRoot,
        _now = now ?? DateTime.now;

  final Future<String?> Function() _resolveRoot;
  final DateTime Function() _now;
  final int maxBytes;

  Future<void> _tail = Future.value();
  String? _root;

  /// Uma operação por vez: o índice é lido, alterado e regravado inteiro.
  Future<T> _locked<T>(Future<T> Function() op) {
    final done = Completer<T>();
    final previous = _tail;
    _tail = done.future.then<void>((_) {}, onError: (_) {});
    previous.then((_) async {
      try {
        done.complete(await op());
      } catch (e, st) {
        done.completeError(e, st);
      }
    });
    return done.future;
  }

  Future<String?> _rootDir() async => _root ??= await _resolveRoot();

  Future<Map<String, Map<String, dynamic>>> _readIndex(String root) async {
    try {
      final raw = jsonDecode(await File('$root/$_indexName').readAsString());
      if (raw is! Map) return {};
      return {
        for (final e in raw.entries)
          if (e.value is Map) e.key as String: Map<String, dynamic>.from(e.value as Map),
      };
    } catch (_) {
      return {}; // sem índice ou corrompido: começa vazio (os arquivos órfãos ainda contam no tamanho)
    }
  }

  Future<void> _writeIndex(String root, Map<String, Map<String, dynamic>> index) async {
    await Directory(root).create(recursive: true);
    final tmp = File('$root/$_indexName.tmp');
    await tmp.writeAsString(jsonEncode(index), flush: true);
    await tmp.rename('$root/$_indexName');
  }

  /// O caminho (relativo, do índice) dentro da raiz, sem links simbólicos e apontando para um arquivo comum.
  Future<String?> _safePath(String root, String relative) async {
    final segments = relative.split('/');
    if (relative.isEmpty ||
        relative.startsWith('/') ||
        segments.length != 2 ||
        segments.any((s) => s.isEmpty || s == '.' || s == '..')) {
      return null;
    }
    final abs = '$root/$relative';
    try {
      if (FileSystemEntity.typeSync(abs, followLinks: false) != FileSystemEntityType.file) return null;
      final canonRoot = await Directory(root).resolveSymbolicLinks();
      final canonFile = await File(abs).resolveSymbolicLinks();
      if (!samePath(canonFile, '$canonRoot/$relative')) return null; // algum componente é link (ou escapa da raiz)
    } on FileSystemException {
      return null;
    }
    return abs;
  }

  CachedFile? _entry(String root, String id, Map<String, dynamic> e, String absPath) {
    final name = e['name'];
    final size = e['size'];
    if (name is! String || size is! int) return null;
    return CachedFile(
      fileId: id,
      name: name,
      size: size,
      path: absPath,
      lastOpened: DateTime.tryParse((e['lastOpened'] as String?) ?? '')?.toUtc() ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      modifiedTime: DateTime.tryParse((e['modifiedTime'] as String?) ?? '')?.toUtc(),
      md5: e['md5'] as String?,
    );
  }

  /// A cópia de [fileId], se existir e estiver íntegra; uma entrada quebrada é esquecida.
  Future<CachedFile?> lookup(String fileId) {
    if (!_idRe.hasMatch(fileId)) return Future.value(null);
    return _locked(() async {
      final root = await _rootDir();
      if (root == null) return null;
      final index = await _readIndex(root);
      final e = index[fileId];
      if (e == null) return null;
      final abs = e['path'] is String ? await _safePath(root, e['path'] as String) : null;
      final entry = abs == null ? null : _entry(root, fileId, e, abs);
      if (entry != null && await File(abs!).length() == entry.size) return entry;
      index.remove(fileId);
      await _writeIndex(root, index);
      return null;
    });
  }

  /// Guarda [bytes] como a cópia de [meta], trocando a anterior, e libera espaço se passou do limite.
  Future<CachedFile> store(DriveFileMeta meta, List<int> bytes) async {
    if (!_idRe.hasMatch(meta.id)) throw ArgumentError.value(meta.id, 'meta.id', 'identificador inválido');
    return _locked(() async {
      final root = await _rootDir();
      if (root == null) throw const DriveCacheUnavailable();
      final name = safeFileName(meta.name);
      final dir = Directory('$root/${meta.id}');
      await dir.create(recursive: true);
      final tmp = File('${dir.path}/.$name.part');
      await tmp.writeAsBytes(bytes, flush: true);
      final target = '${dir.path}/$name';
      await tmp.rename(target);
      await for (final other in dir.list(followLinks: false)) {
        if (other.path != target) await other.delete(recursive: true);
      }
      final now = _now().toUtc();
      final index = await _readIndex(root);
      index[meta.id] = {
        'name': meta.name,
        'size': bytes.length,
        'modifiedTime': meta.modifiedTime?.toUtc().toIso8601String(),
        'md5': meta.md5,
        'path': '${meta.id}/$name',
        'lastOpened': now.toIso8601String(),
      };
      await _evict(root, index, keep: meta.id);
      await _writeIndex(root, index);
      return _entry(root, meta.id, index[meta.id]!, target)!;
    });
  }

  /// Registra que [fileId] acabou de ser aberto (o mais antigo é o primeiro a sair quando falta espaço).
  Future<void> markOpened(String fileId) {
    if (!_idRe.hasMatch(fileId)) return Future.value();
    return _locked(() async {
      final root = await _rootDir();
      if (root == null) return;
      final index = await _readIndex(root);
      final e = index[fileId];
      if (e == null) return;
      e['lastOpened'] = _now().toUtc().toIso8601String();
      await _writeIndex(root, index);
    });
  }

  /// Bytes ocupados pelos arquivos guardados (conta também o que o índice não conhece).
  Future<int> totalBytes() => _locked(() async {
        final root = await _rootDir();
        return root == null ? 0 : _sizeOf(root);
      });

  /// Apaga todos os arquivos baixados e o índice.
  Future<void> clear() => _locked(() async {
        final root = await _rootDir();
        if (root == null) return;
        final dir = Directory(root);
        if (!await dir.exists()) return;
        await for (final e in dir.list(followLinks: false)) {
          await e.delete(recursive: true); // link: apaga o link, não o destino
        }
      });

  Future<int> _sizeOf(String root) async {
    final dir = Directory(root);
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      if (e.path == '$root/$_indexName' || e.path == '$root/$_indexName.tmp') continue;
      total += await e.length();
    }
    return total;
  }

  /// Apaga os menos usados até caber em [maxBytes]; [keep] nunca sai.
  Future<void> _evict(String root, Map<String, Map<String, dynamic>> index, {required String keep}) async {
    var total = await _sizeOf(root);
    if (total <= maxBytes) return;
    DateTime used(Map<String, dynamic> e) =>
        DateTime.tryParse((e['lastOpened'] as String?) ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final order = index.keys.where((k) => k != keep).toList()..sort((a, b) => used(index[a]!).compareTo(used(index[b]!)));
    for (final id in order) {
      if (total <= maxBytes) break;
      final dir = Directory('$root/$id');
      if (await dir.exists()) {
        total -= await _sizeOf(dir.path);
        await dir.delete(recursive: true);
      }
      index.remove(id);
    }
  }
}

/// Compara caminhos canônicos. No Windows o sistema devolve `\` e não diferencia maiúsculas;
/// no Linux/Android a comparação é exata.
bool samePath(String a, String b, {bool? windows}) {
  if (!(windows ?? Platform.isWindows)) return a == b;
  String n(String s) => s.replaceAll('\\', '/').toLowerCase();
  return n(a) == n(b);
}
