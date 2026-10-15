import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Maior PDF guardado no caderno (limite do bucket `notebook-images` para PDFs).
const int kMaxStoredPdfBytes = 50 * 1024 * 1024;

/// O PDF original de um caderno, no Storage do caderno (some com ele ao excluir).
abstract class NotebookPdfStore {
  /// Envia o PDF e devolve o caminho no Storage.
  Future<String> uploadPdf(Uint8List bytes);

  /// Baixa o PDF de [path].
  Future<Uint8List> downloadPdf(String path);
}

/// Em memória (testes e padrão sem servidor). Os cadernos compartilham o mesmo mapa.
class MemoryNotebookPdfStore implements NotebookPdfStore {
  MemoryNotebookPdfStore(this.noteId, this.files);

  final String noteId;
  final Map<String, Uint8List> files;

  @override
  Future<String> uploadPdf(Uint8List bytes) async {
    final path = 'u/$noteId/${files.length}.pdf';
    files[path] = bytes;
    return path;
  }

  @override
  Future<Uint8List> downloadPdf(String path) async {
    final f = files[path];
    if (f == null) throw StateError('PDF não encontrado: $path');
    return f;
  }
}

/// Guarda no aparelho os PDFs já baixados ou enviados: abrir de novo não gasta a
/// rede e funciona sem internet. O caminho no Storage é único por arquivo enviado,
/// então o que está no disco nunca fica velho.
class CachedNotebookPdfStore implements NotebookPdfStore {
  CachedNotebookPdfStore(this._inner, this._dir);

  final NotebookPdfStore _inner;
  final Future<Directory> Function() _dir;

  Future<File> _file(String path) async {
    final dir = await _dir();
    return File('${dir.path}${Platform.pathSeparator}${path.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}');
  }

  @override
  Future<String> uploadPdf(Uint8List bytes) async {
    final path = await _inner.uploadPdf(bytes);
    try {
      final f = await _file(path);
      await f.parent.create(recursive: true);
      await f.writeAsBytes(bytes, flush: true);
    } catch (_) {
      // Sem cache: baixa quando abrir.
    }
    return path;
  }

  @override
  Future<Uint8List> downloadPdf(String path) async {
    try {
      final f = await _file(path);
      if (await f.exists()) return await f.readAsBytes();
    } catch (_) {}
    final bytes = await _inner.downloadPdf(path);
    try {
      final f = await _file(path);
      await f.parent.create(recursive: true);
      await f.writeAsBytes(bytes, flush: true);
    } catch (_) {}
    return bytes;
  }
}

/// O store de PDFs de um caderno. Padrão: memória; `main.dart` liga o Supabase com cache.
final notebookPdfStoreFactoryProvider = Provider<NotebookPdfStore Function(String noteId)>((ref) {
  final files = <String, Uint8List>{};
  return (noteId) => MemoryNotebookPdfStore(noteId, files);
});
