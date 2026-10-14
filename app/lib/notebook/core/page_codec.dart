import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:isolate' show Isolate;

import 'ink_types.dart';
import 'page_doc.dart';

/// Versão do formato que este código escreve e entende.
const int pageFormatVersion = 1;

/// Dados da página ilegíveis (corrompidos, truncados ou malformados).
class PageDecodeException extends FormatException {
  PageDecodeException(super.message);

  @override
  String toString() => 'PageDecodeException: $message';
}

/// A página foi gravada por uma versão mais nova do formato.
class UnsupportedPageVersionException extends PageDecodeException {
  UnsupportedPageVersionException(this.version)
    : super(
        'Esta página usa o formato de versão $version, que este '
        'aplicativo não entende (só até a versão $pageFormatVersion). '
        'Atualize o aplicativo para abri-la.',
      );

  final int version;
}

/// Contadores de diagnóstico do codec (testes e benchmarks; não afetam nada).
class PageCodecStats {
  PageCodecStats._();

  /// Traços convertidos para JSON (um traço já convertido não conta de novo).
  static int strokesSerialized = 0;

  /// Chamadas a [decodePage] que chegaram a decodificar algo.
  static int decodes = 0;

  /// Vezes que [encodePageAsync] mandou o trabalho para outro isolate.
  static int isolateRuns = 0;
}

/// JSON já pronto de cada traço. Traços são imutáveis por id, então o texto
/// nunca muda: codificar a página de novo depois de acrescentar um traço
/// reaproveita o JSON dos outros (o custo vira ~constante por traço novo em vez
/// de proporcional à página inteira). O `Expando` não segura o traço: quando o
/// traço sai da memória, o texto vai junto.
final Expando<String> _strokeJson = Expando<String>('strokeJson');

String _strokeFragment(Stroke s) {
  final cached = _strokeJson[s];
  if (cached != null) return cached;
  PageCodecStats.strokesSerialized++;
  return _strokeJson[s] = jsonEncode(_strokeToJson(s));
}

/// O JSON (texto) da página, na forma exata que `jsonEncode` daria ao mapa do
/// formato v1: `{"v":1,"strokes":[…],"texts":[…],"images":[…],"deleted":[…]}`.
/// É a parte barata de [encodePage] (reaproveita o JSON dos traços); falta só
/// comprimir ([compressPageJson]). Página sem item nem tombstone → `''`.
String pageJson(PageDoc doc) {
  if (doc.isEmpty && doc.deleted.isEmpty) return '';
  final b = StringBuffer('{"v":$pageFormatVersion,"strokes":[');
  var first = true;
  for (final s in doc.strokes) {
    if (!first) b.write(',');
    first = false;
    b.write(_strokeFragment(s));
  }
  b
    ..write('],"texts":')
    ..write(jsonEncode([for (final t in doc.texts) _textToJson(t)]))
    ..write(',"images":')
    ..write(jsonEncode([for (final i in doc.images) _imageToJson(i)]))
    ..write(',"deleted":')
    ..write(jsonEncode(doc.deleted.toList()..sort()))
    ..write('}');
  return b.toString();
}

/// utf8 → gzip → base64 de um JSON de [pageJson]. Função de nível superior e
/// sem estado: pode rodar em outro isolate (é a parte pesada para páginas grandes).
String compressPageJson(String json) {
  if (json.isEmpty) return '';
  return base64Encode(gzip.encode(utf8.encode(json)));
}

/// JSON v1 → gzip → base64. Página sem nenhum item nem tombstone vira `''`.
///
/// Quantização: coordenadas e caixas em 0,1 unidade de página; pressão com 2
/// casas (0–1); espessura e fonte com 2 casas. Inteiros saem sem `.0`.
///
/// Os pontos de cada traço saem na forma compacta `"q"`: inteiros (x e y em
/// décimos, pressão em centésimos), o 1º ponto absoluto e os demais em delta
/// em relação ao anterior. Isso comprime ~2x melhor no gzip que os `pts`
/// absolutos da spec; [decodePage] lê as duas formas.
String encodePage(PageDoc doc) => compressPageJson(pageJson(doc));

/// Tamanho do JSON (caracteres) a partir do qual [encodePageAsync] comprime em
/// outro isolate. Abaixo disso, subir o isolate custa mais do que comprimir.
const int pageInlineLimit = 16 * 1024;

/// Igual a [encodePage], mas a compressão (utf8 + gzip + base64: ~metade do
/// custo e a que cresce com a página) roda fora da thread da interface quando a
/// página é grande. Na thread de chamada sobra montar o JSON a partir dos
/// fragmentos em cache, que é rápido. O resultado é idêntico ao de [encodePage].
Future<String> encodePageAsync(PageDoc doc, {int inlineLimit = pageInlineLimit}) {
  final json = pageJson(doc);
  if (json.length <= inlineLimit) return Future.value(compressPageJson(json));
  PageCodecStats.isolateRuns++;
  return Isolate.run(() => compressPageJson(json));
}

/// Inverso de [encodePage]. `''` (ou só espaços) → página vazia. Dados ruins →
/// [PageDecodeException]; versão desconhecida → [UnsupportedPageVersionException].
PageDoc decodePage(String data) {
  final text = data.trim();
  if (text.isEmpty) return PageDoc.empty;
  PageCodecStats.decodes++;

  final List<int> compressed;
  try {
    compressed = base64Decode(text);
  } catch (_) {
    throw PageDecodeException('Dados da página não são base64 válido.');
  }
  final List<int> raw;
  try {
    raw = gzip.decode(compressed);
  } catch (_) {
    throw PageDecodeException(
      'Dados da página não estão comprimidos (gzip) '
      'ou estão truncados.',
    );
  }
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(raw));
  } catch (_) {
    throw PageDecodeException('Conteúdo da página não é um JSON válido.');
  }
  if (json is! Map<String, dynamic>) {
    throw PageDecodeException('Conteúdo da página deveria ser um objeto JSON.');
  }
  final v = json['v'];
  if (v is! int) {
    throw PageDecodeException('Página sem número de versão ("v").');
  }
  if (v != pageFormatVersion) throw UnsupportedPageVersionException(v);

  return PageDoc(
    strokes: [for (final m in _list(json, 'strokes')) _strokeFromJson(m)],
    texts: [for (final m in _list(json, 'texts')) _textFromJson(m)],
    images: [for (final m in _list(json, 'images')) _imageFromJson(m)],
    deleted: [
      for (final d in _rawList(json, 'deleted'))
        d is String
            ? d
            : throw PageDecodeException('"deleted" deve ter só textos.'),
    ],
  );
}

// ---------------------------------------------------------------------------
// escrita

int _int(double v, int scale) {
  if (!v.isFinite) {
    throw ArgumentError.value(v, 'valor', 'número não finito não é salvável');
  }
  return (v * scale).round();
}

/// Número já arredondado em `1/scale`; inteiros viram `int` (sem `.0`).
Object _num(double v, int scale) {
  final n = _int(v, scale);
  return n % scale == 0 ? n ~/ scale : n / scale;
}

Object _coord(double v) => _num(v, 10);
Object _size(double v) => _num(v, 100);

String _colorToJson(int argb) {
  final rgb = (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
  final a = ((argb >> 24) & 0xFF).toRadixString(16).padLeft(2, '0');
  return '#${(rgb + a).toUpperCase()}';
}

Map<String, Object?> _strokeToJson(Stroke s) {
  final q = <int>[];
  var px = 0, py = 0, pp = 0;
  for (final p in s.points) {
    final x = _int(p.x, 10), y = _int(p.y, 10);
    final pr = _int(p.p.clamp(0.0, 1.0), 100);
    q
      ..add(x - px)
      ..add(y - py)
      ..add(pr - pp);
    px = x;
    py = y;
    pp = pr;
  }
  return {
    'id': s.id,
    'tool': s.tool.name,
    'color': _colorToJson(s.argb),
    'width': _size(s.width),
    'q': q,
  };
}

Map<String, Object?> _textToJson(TextBox t) => {
  'id': t.id,
  'x': _coord(t.x),
  'y': _coord(t.y),
  'w': _coord(t.w),
  'text': t.text,
  'size': _size(t.size),
  'color': _colorToJson(t.argb),
  if (t.font != null) 'font': t.font,
};

Map<String, Object?> _imageToJson(ImageBox i) => {
  'id': i.id,
  'x': _coord(i.x),
  'y': _coord(i.y),
  'w': _coord(i.w),
  'h': _coord(i.h),
  'path': i.path,
};

// ---------------------------------------------------------------------------
// leitura

List<Object?> _rawList(Map<String, dynamic> m, String key) {
  final v = m[key];
  if (v == null) return const [];
  if (v is! List) throw PageDecodeException('"$key" deveria ser uma lista.');
  return v;
}

List<Map<String, dynamic>> _list(Map<String, dynamic> m, String key) => [
  for (final e in _rawList(m, key))
    e is Map<String, dynamic>
        ? e
        : throw PageDecodeException('Item inválido em "$key".'),
];

String _str(Map<String, dynamic> m, String key, String what) {
  final v = m[key];
  if (v is! String) {
    throw PageDecodeException('$what: campo "$key" ausente ou inválido.');
  }
  return v;
}

double _dbl(Map<String, dynamic> m, String key, String what) {
  final v = m[key];
  if (v is! num || !v.isFinite) {
    throw PageDecodeException('$what: campo "$key" ausente ou inválido.');
  }
  return v.toDouble();
}

final _colorRe = RegExp(r'^#[0-9a-fA-F]{8}$');

int _colorFromJson(Map<String, dynamic> m, String what) {
  final c = _str(m, 'color', what);
  if (!_colorRe.hasMatch(c)) {
    throw PageDecodeException('$what: cor "$c" inválida (esperado #RRGGBBAA).');
  }
  final rgb = int.parse(c.substring(1, 7), radix: 16);
  final a = int.parse(c.substring(7, 9), radix: 16);
  return (a << 24) | rgb;
}

Stroke _strokeFromJson(Map<String, dynamic> m) {
  final id = _str(m, 'id', 'traço');
  final what = 'traço $id';
  final toolName = _str(m, 'tool', what);
  final tool = PenTool.values.where((t) => t.name == toolName).firstOrNull;
  if (tool == null) {
    throw PageDecodeException('$what: ferramenta "$toolName" desconhecida.');
  }
  final points = m.containsKey('q')
      ? _pointsFromDeltas(m['q'], what)
      : _pointsFromAbsolute(m['pts'], what);
  return Stroke(
    id: id,
    tool: tool,
    argb: _colorFromJson(m, what),
    width: quantizeSize(_dbl(m, 'width', what)),
    points: points,
  );
}

List<InkPoint> _pointsFromDeltas(Object? q, String what) {
  if (q is! List || q.isEmpty || q.length % 3 != 0) {
    throw PageDecodeException(
      '$what: "q" deve ser uma lista não vazia com tamanho múltiplo de 3 '
      '(x, y, pressão).',
    );
  }
  final points = <InkPoint>[];
  var x = 0, y = 0, p = 0;
  for (var i = 0; i < q.length; i += 3) {
    final dx = q[i], dy = q[i + 1], dp = q[i + 2];
    if (dx is! int || dy is! int || dp is! int) {
      throw PageDecodeException('$what: "q" só pode ter números inteiros.');
    }
    x += dx;
    y += dy;
    p += dp;
    points.add(InkPoint(x / 10.0, y / 10.0, p.clamp(0, 100) / 100.0));
  }
  return points;
}

/// Forma literal da spec: `pts` absolutos `[x, y, p, ...]`.
List<InkPoint> _pointsFromAbsolute(Object? pts, String what) {
  if (pts is! List || pts.isEmpty || pts.length % 3 != 0) {
    throw PageDecodeException(
      '$what: faltam os pontos: "pts" (ou "q") deve ser uma lista não vazia '
      'com tamanho múltiplo de 3 (x, y, pressão).',
    );
  }
  final points = <InkPoint>[];
  for (var i = 0; i < pts.length; i += 3) {
    final x = pts[i], y = pts[i + 1], p = pts[i + 2];
    if (x is! num || y is! num || p is! num) {
      throw PageDecodeException('$what: "pts" só pode ter números.');
    }
    points.add(
      InkPoint(
        quantizeCoord(x.toDouble()),
        quantizeCoord(y.toDouble()),
        quantizePressure(p.toDouble()),
      ),
    );
  }
  return points;
}

TextBox _textFromJson(Map<String, dynamic> m) {
  final id = _str(m, 'id', 'texto');
  final what = 'texto $id';
  return TextBox(
    id: id,
    x: quantizeCoord(_dbl(m, 'x', what)),
    y: quantizeCoord(_dbl(m, 'y', what)),
    w: quantizeCoord(_dbl(m, 'w', what)),
    text: _str(m, 'text', what),
    size: quantizeSize(_dbl(m, 'size', what)),
    argb: _colorFromJson(m, what),
    font: m['font'] is String ? m['font'] as String : null,
  );
}

ImageBox _imageFromJson(Map<String, dynamic> m) {
  final id = _str(m, 'id', 'imagem');
  final what = 'imagem $id';
  return ImageBox(
    id: id,
    x: quantizeCoord(_dbl(m, 'x', what)),
    y: quantizeCoord(_dbl(m, 'y', what)),
    w: quantizeCoord(_dbl(m, 'w', what)),
    h: quantizeCoord(_dbl(m, 'h', what)),
    path: _str(m, 'path', what),
  );
}
