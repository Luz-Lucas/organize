/// Nomes e tipos de arquivo do Drive no aparelho.
library;

const _maxNameLength = 120;
const _maxExtensionLength = 12;
const _opaqueMime = 'application/octet-stream';
final _mimeRe = RegExp(r'^[a-z0-9][a-z0-9!#$&^_.+-]*/[a-z0-9][a-z0-9!#$&^_.+-]*$');

/// Nome seguro para gravar no aparelho: sem separadores, controles nem pontos iniciais ou `..`; no máximo
/// 120 caracteres, preservando a extensão. Nunca devolve vazio.
String safeFileName(String name) {
  var n = name.replaceAll(RegExp(r'[\u0000-\u001f\u007f/\\:*?"<>|]'), '_').replaceAll(RegExp(r'\.{2,}'), '.').trim();
  n = n.replaceFirst(RegExp(r'^\.+'), '');
  if (n.isEmpty || n.replaceAll('.', '').isEmpty) return 'arquivo';
  if (n.length > _maxNameLength) {
    final dot = n.lastIndexOf('.');
    final ext = dot > 0 && n.length - dot <= _maxExtensionLength ? n.substring(dot) : '';
    n = '${n.substring(0, _maxNameLength - ext.length)}$ext';
  }
  return n;
}

const _mimeByExtension = {
  'pdf': 'application/pdf',
  'doc': 'application/msword',
  'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'ppt': 'application/vnd.ms-powerpoint',
  'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'odt': 'application/vnd.oasis.opendocument.text',
  'ods': 'application/vnd.oasis.opendocument.spreadsheet',
  'odp': 'application/vnd.oasis.opendocument.presentation',
  'txt': 'text/plain',
  'md': 'text/markdown',
  'csv': 'text/csv',
  'html': 'text/html',
  'rtf': 'application/rtf',
  'zip': 'application/zip',
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'svg': 'image/svg+xml',
  'mp3': 'audio/mpeg',
  'm4a': 'audio/mp4',
  'wav': 'audio/wav',
  'mp4': 'video/mp4',
  'mkv': 'video/x-matroska',
  'webm': 'video/webm',
};

String? _extensionOf(String name) {
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return null;
  return name.substring(dot + 1).toLowerCase();
}

/// Tipo MIME para abrir o arquivo: o do Drive quando é específico; senão pela extensão. Sem curingas nem
/// valores malformados: o pior caso é binário opaco (o app que abre decide pelo conteúdo).
String mimeForFile(String name, String? driveMime) {
  final given = driveMime?.trim().toLowerCase();
  if (given != null && given != _opaqueMime && _mimeRe.hasMatch(given) && !given.contains('*')) return given;
  final ext = _extensionOf(name);
  return (ext == null ? null : _mimeByExtension[ext]) ?? _opaqueMime;
}
