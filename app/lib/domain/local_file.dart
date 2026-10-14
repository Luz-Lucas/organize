import 'dart:convert';
import 'dart:io';

const _mimeByExt = {
  'pdf': 'application/pdf',
  'doc': 'application/msword',
  'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'txt': 'text/plain',
  'md': 'text/markdown',
  // Binário opaco (o servidor recusa curingas e tipos nativos do Google).
  'sdocx': 'application/octet-stream',
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'heic': 'image/heic',
};

String _ext(String name) {
  final i = name.lastIndexOf('.');
  return i < 0 ? '' : name.substring(i + 1).toLowerCase();
}

String mimeForFileName(String name) => _mimeByExt[_ext(name)] ?? 'application/octet-stream';

/// `.txt` e `.md` viram notas; os demais vão para o Drive.
bool isTextFileName(String name) => const {'txt', 'md'}.contains(_ext(name));

/// Texto acima disso (1 MB) não vira nota: o arquivo vai para o Drive.
const maxNoteTextBytes = 1024 * 1024;

/// Arquivo escolhido pelo usuário ou recebido de outro app: no disco ([path]) ou em memória.
class LocalFile {
  LocalFile({required this.name, this.path, List<int>? bytes, int? size, String? mimeType})
      : _bytes = bytes,
        size = size ?? bytes?.length ?? 0,
        mimeType = mimeType ?? mimeForFileName(name);

  LocalFile.memory({required String name, required List<int> bytes, String? mimeType})
      : this(name: name, bytes: bytes, mimeType: mimeType);

  final String name;
  final String? path;
  final List<int>? _bytes;
  final int size;
  final String mimeType;

  /// Vira nota de texto (`.txt`/`.md` de até [maxNoteTextBytes]); o resto vai para o Drive.
  bool get becomesNote => isTextFileName(name) && size <= maxNoteTextBytes;

  Stream<List<int>> openRead() {
    final b = _bytes;
    if (b != null) return Stream.value(b);
    final p = path;
    if (p == null) return const Stream.empty();
    return File(p).openRead();
  }

  Future<String> readAsString() async {
    final b = _bytes ?? await File(path!).readAsBytes();
    return utf8.decode(b, allowMalformed: true);
  }
}
