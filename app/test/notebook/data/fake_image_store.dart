import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:organizacional/notebook/ui/notebook_session.dart';

/// Store de imagens falso para os testes: guarda os bytes em memória.
class FakeNotebookImageStore implements NotebookImageStore {
  final uploads = <String, Uint8List>{};

  @override
  Future<String> upload(Uint8List bytes, String ext) async {
    final path = 'u/n/${uploads.length}.$ext';
    uploads[path] = bytes;
    return path;
  }

  @override
  Future<ImageProvider> load(String path) async => MemoryImage(uploads[path] ?? Uint8List(0));
}
