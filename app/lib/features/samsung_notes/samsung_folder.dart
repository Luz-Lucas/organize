/// Pasta vigiada: um caminho do sistema de arquivos ([path]) ou, quando o usuário a escolheu
/// pelo seletor do Android (SAF), o URI persistido ([uri]).
class SamsungFolder {
  const SamsungFolder({this.path, this.uri, this._label}) : assert(path != null || uri != null, 'path ou uri');

  final String? path;
  final String? uri;
  final String? _label;

  bool get isUri => uri != null;

  /// Nome curto para mostrar: o dado pelo seletor, ou os dois últimos trechos do caminho.
  String get label {
    final given = _label;
    if (given != null && given.isNotEmpty) return given;
    final p = path;
    if (p == null) return uri!;
    final parts = p.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.length <= 2) return parts.join('/');
    return parts.sublist(parts.length - 2).join('/');
  }

  Map<String, dynamic> toJson() => {
        if (path != null) 'path': path,
        if (uri != null) 'uri': uri,
        if (_label != null) 'label': _label,
      };

  static SamsungFolder? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final path = raw['path'];
    final uri = raw['uri'];
    final p = path is String && path.isNotEmpty ? path : null;
    final u = uri is String && uri.isNotEmpty ? uri : null;
    if (p == null && u == null) return null;
    final label = raw['label'];
    return SamsungFolder(path: p, uri: u, label: label is String ? label : null);
  }

  @override
  bool operator ==(Object other) => other is SamsungFolder && other.path == path && other.uri == uri && other._label == _label;

  @override
  int get hashCode => Object.hash(path, uri, _label);
}

const _externalStorageAuthority = 'com.android.externalstorage.documents';

/// Caminho de arquivos equivalente a um URI de pasta escolhida no seletor do Android, quando a pasta está
/// no armazenamento interno (`primary:`) ou num cartão (`<id>:`). Outros provedores não têm caminho.
String? uriToPath(String uri) {
  final parsed = Uri.tryParse(uri);
  if (parsed == null || parsed.scheme != 'content' || parsed.host != _externalStorageAuthority) return null;
  final segs = parsed.pathSegments;
  final i = segs.indexOf('tree');
  if (i < 0 || i + 1 >= segs.length) return null;
  final doc = segs[i + 1];
  final colon = doc.indexOf(':');
  if (colon <= 0) return null;
  final volume = doc.substring(0, colon);
  final rel = doc.substring(colon + 1);
  if (rel.split('/').any((s) => s == '..')) return null;
  final root = volume == 'primary' ? '/storage/emulated/0' : '/storage/$volume';
  final clean = rel.split('/').where((s) => s.isNotEmpty).join('/');
  return clean.isEmpty ? root : '$root/$clean';
}

/// A pasta "Download" mistura de tudo (não indica que são notas): o usuário precisa confirmar antes de vigiá-la.
bool folderNeedsConfirmation(String path) {
  final last = path.split('/').where((s) => s.isNotEmpty).lastOrNull;
  return last != null && last.toLowerCase() == 'download';
}
