// Gerador de escrita à mão sintética para os testes da inteligência do Caderno.
//
// Cada letra é uma (ou mais) polilinha(s) em unidades de altura-x (x para a
// direita, y para CIMA, 0 = baseline). O gerador reamostra como uma caneta
// (amostras a ~2,4 unidades), com ruído, variação de tamanho, "tremida" da
// baseline, inclinação da linha e itálico leve. Tudo determinístico (seed).
import 'dart:math' as math;
import 'dart:ui' hide TextBox;

import 'package:organizacional/notebook/core/notebook_core.dart';

typedef Glyph = ({double adv, List<List<Offset>> main, List<List<Offset>> extra});

List<Offset> _arc(
  double cx,
  double cy,
  double rx,
  double ry,
  double a0,
  double a1, [
  int n = 14,
]) => [
  for (var i = 0; i <= n; i++)
    () {
      final a = (a0 + (a1 - a0) * i / n) * math.pi / 180;
      return Offset(cx + rx * math.cos(a), cy + ry * math.sin(a));
    }(),
];

/// Catmull-Rom por pontos de controle (curvas suaves, sem cantos).
List<Offset> _smooth(List<Offset> p, [int sub = 5]) {
  final out = <Offset>[];
  for (var i = 0; i < p.length - 1; i++) {
    final p0 = p[math.max(0, i - 1)], p1 = p[i], p2 = p[i + 1];
    final p3 = p[math.min(p.length - 1, i + 2)];
    for (var k = 0; k < sub; k++) {
      final t = k / sub, t2 = t * t, t3 = t2 * t;
      double c(double a, double b, double cc, double d) =>
          0.5 *
          ((2 * b) +
              (-a + cc) * t +
              (2 * a - 5 * b + 4 * cc - d) * t2 +
              (-a + 3 * b - 3 * cc + d) * t3);
      out.add(Offset(c(p0.dx, p1.dx, p2.dx, p3.dx), c(p0.dy, p1.dy, p2.dy, p3.dy)));
    }
  }
  out.add(p.last);
  return out;
}

List<Offset> _pl(List<List<double>> xy) => [for (final p in xy) Offset(p[0], p[1])];

List<Offset> _bowl() => _arc(0.42, 0.5, 0.4, 0.5, 90, 450, 18);

final Map<String, Glyph> glyphs = () {
  final g = <String, Glyph>{};
  void add(String c, double adv, List<List<Offset>> main, [List<List<Offset>> extra = const []]) =>
      g[c] = (adv: adv, main: main, extra: extra);

  add('o', 0.95, [_bowl()]);
  add('a', 1.1, [_bowl(), _pl([[0.84, 1.0], [0.84, 0.0]])]);
  add('c', 0.9, [_arc(0.45, 0.5, 0.4, 0.5, 50, 310)]);
  add('e', 0.95, [
    [..._pl([[0.05, 0.5], [0.85, 0.5]]), ..._arc(0.45, 0.5, 0.4, 0.5, 0, 320, 16)],
  ]);
  add('d', 1.1, [_bowl(), _pl([[0.86, 2.0], [0.86, 0.0]])]);
  add('b', 1.0, [_pl([[0.0, 2.0], [0.0, 0.0]]), _arc(0.45, 0.5, 0.4, 0.5, 180, 540, 18)]);
  add('p', 1.0, [_pl([[0.0, 1.0], [0.0, -1.0]]), _arc(0.45, 0.5, 0.4, 0.5, 180, 540, 18)]);
  add('q', 1.1, [_bowl(), _pl([[0.86, 1.0], [0.86, -1.0]])]);
  add('f', 0.8, [
    [
      ..._arc(0.6, 1.5, 0.3, 0.3, 20, 90, 4),
      ..._arc(0.3, 1.5, 0.0001, 0.3, 90, 90, 1),
      ..._pl([[0.3, 1.8], [0.3, 0.0]]),
    ],
  ], [
    _pl([[0.0, 1.0], [0.68, 1.0]]),
  ]);
  add('g', 1.1, [
    _bowl(),
    [..._pl([[0.86, 1.0], [0.86, -0.4]]), ..._arc(0.5, -0.4, 0.36, 0.35, 0, -150, 8)],
  ]);
  add('h', 1.0, [
    _pl([[0.0, 2.0], [0.0, 0.0]]),
    [..._arc(0.4, 0.6, 0.4, 0.4, 180, 0, 10), const Offset(0.8, 0.0)],
  ]);
  add('n', 1.0, [
    [
      ..._pl([[0.0, 1.0], [0.0, 0.0], [0.0, 0.6]]),
      ..._arc(0.4, 0.6, 0.4, 0.4, 180, 0, 10),
      const Offset(0.8, 0.0),
    ],
  ]);
  add('m', 1.55, [
    [
      ..._pl([[0.0, 1.0], [0.0, 0.0], [0.0, 0.6]]),
      ..._arc(0.35, 0.6, 0.35, 0.4, 180, 0, 8),
      ..._pl([[0.7, 0.0], [0.7, 0.6]]),
      ..._arc(1.05, 0.6, 0.35, 0.4, 180, 0, 8),
      const Offset(1.4, 0.0),
    ],
  ]);
  add('r', 0.8, [
    _pl([[0.0, 1.0], [0.0, 0.0]]),
    [const Offset(0.0, 0.55), ..._arc(0.35, 0.65, 0.35, 0.35, 180, 55, 6)],
  ]);
  add('i', 0.35, [
    _pl([[0.05, 1.0], [0.05, 0.0]]),
  ], [
    _pl([[0.05, 1.45], [0.08, 1.52]]),
  ]);
  add('j', 0.5, [
    [..._pl([[0.25, 1.0], [0.25, -0.45]]), ..._arc(0.05, -0.45, 0.2, 0.3, 0, -120, 6)],
  ], [
    _pl([[0.25, 1.45], [0.28, 1.52]]),
  ]);
  add('k', 0.9, [
    _pl([[0.0, 2.0], [0.0, 0.0]]),
    _pl([[0.7, 1.0], [0.0, 0.4], [0.75, 0.0]]),
  ]);
  add('l', 0.35, [
    _pl([[0.05, 2.0], [0.05, 0.0]]),
  ]);
  add('s', 0.75, [
    _smooth(_pl([
      [0.7, 0.9], [0.45, 1.0], [0.15, 0.85], [0.2, 0.65], [0.5, 0.5],
      [0.75, 0.35], [0.7, 0.12], [0.4, 0.0], [0.08, 0.12],
    ])),
  ]);
  add('t', 0.75, [
    _pl([[0.3, 1.7], [0.3, 0.0]]),
  ], [
    _pl([[0.0, 1.05], [0.66, 1.05]]),
  ]);
  add('u', 1.0, [
    [
      ..._pl([[0.0, 1.0], [0.0, 0.4]]),
      ..._arc(0.4, 0.4, 0.4, 0.4, 180, 360, 10),
      ..._pl([[0.8, 1.0], [0.8, 0.0]]),
    ],
  ]);
  add('v', 0.95, [
    _pl([[0.0, 1.0], [0.4, 0.0], [0.8, 1.0]]),
  ]);
  add('w', 1.4, [
    _pl([[0.0, 1.0], [0.3, 0.0], [0.6, 0.8], [0.9, 0.0], [1.2, 1.0]]),
  ]);
  add('x', 0.95, [
    _pl([[0.0, 1.0], [0.8, 0.0]]),
    _pl([[0.8, 1.0], [0.0, 0.0]]),
  ]);
  add('y', 0.95, [
    _pl([[0.0, 1.0], [0.4, 0.05]]),
    _pl([[0.8, 1.0], [0.45, -0.1], [0.15, -0.75]]),
  ]);
  add('z', 0.95, [
    _pl([[0.0, 1.0], [0.8, 1.0], [0.0, 0.0], [0.8, 0.0]]),
  ]);
  add('ç', 0.9, [
    _arc(0.45, 0.5, 0.4, 0.5, 50, 310),
  ], [
    _pl([[0.45, 0.0], [0.5, -0.35]]),
  ]);
  add('é', 0.95, g['e']!.main, [
    _pl([[0.3, 1.35], [0.6, 1.8]]),
  ]);
  add('ê', 0.95, g['e']!.main, [
    // acento circunflexo: formato de "∧" colocado SOBRE a letra
    _pl([[0.1, 1.4], [0.42, 1.9], [0.74, 1.4]]),
  ]);
  add('á', 1.1, g['a']!.main, [
    _pl([[0.3, 1.35], [0.6, 1.8]]),
  ]);
  add('í', 0.35, g['i']!.main, [
    _pl([[0.0, 1.35], [0.3, 1.8]]),
  ]);
  add('ó', 0.95, g['o']!.main, [
    _pl([[0.3, 1.35], [0.6, 1.8]]),
  ]);
  add('ú', 1.0, g['u']!.main, [
    _pl([[0.3, 1.35], [0.6, 1.8]]),
  ]);
  add('â', 1.1, g['a']!.main, [
    _pl([[0.1, 1.4], [0.42, 1.9], [0.74, 1.4]]),
  ]);
  add('ô', 0.95, g['o']!.main, [
    _pl([[0.1, 1.4], [0.42, 1.9], [0.74, 1.4]]),
  ]);
  add('õ', 0.95, g['o']!.main, [
    _smooth(_pl([[0.1, 1.45], [0.3, 1.7], [0.5, 1.45], [0.7, 1.7]])),
  ]);
  add('ã', 1.1, g['a']!.main, [
    _smooth(_pl([[0.15, 1.45], [0.35, 1.7], [0.55, 1.45], [0.75, 1.7]])),
  ]);
  add('L', 1.0, [
    _pl([[0.0, 2.0], [0.0, 0.0], [0.8, 0.0]]),
  ]);
  add('.', 0.3, [
    _pl([[0.05, 0.1], [0.08, 0.0]]),
  ]);
  add(',', 0.3, [
    _pl([[0.1, 0.1], [0.05, -0.35]]),
  ]);
  return g;
}();

/// Gerador de ids crescentes e ordenáveis (como `newInkId`).
class IdGen {
  IdGen([this.prefix = 's']);
  final String prefix;
  int _n = 0;
  String next() => '$prefix${(++_n).toString().padLeft(6, '0')}';
}

class Hand {
  const Hand({
    this.xh = 16,
    this.slopeDeg = 0,
    this.seed = 1,
    this.letterGap = 0.22,
    this.wordGap = 1.15,
    this.noise = 0.2,
    this.sizeVar = 0.06,
    this.wobble = 0.05,
    this.slant = 0.08,
    this.spacing = 2.4,
    this.delayExtras = false,
    this.width = 2.2,
  });
  final double xh, slopeDeg, letterGap, wordGap, noise, sizeVar, wobble, slant;
  final double spacing, width;
  final int seed;

  /// Pontos de i, barras de t e acentos só depois da palavra toda.
  final bool delayExtras;

  Hand copyWith({double? xh, double? slopeDeg, int? seed, double? wordGap, bool? delayExtras}) => Hand(
    xh: xh ?? this.xh,
    slopeDeg: slopeDeg ?? this.slopeDeg,
    seed: seed ?? this.seed,
    letterGap: letterGap,
    wordGap: wordGap ?? this.wordGap,
    noise: noise,
    sizeVar: sizeVar,
    wobble: wobble,
    slant: slant,
    spacing: spacing,
    delayExtras: delayExtras ?? this.delayExtras,
    width: width,
  );
}

/// Palavra escrita: traços na ordem da escrita + caixa de cada palavra.
class Written {
  Written(this.strokes, this.wordRects, this.wordIds, this.endX);
  final List<Stroke> strokes;
  final List<Rect> wordRects;

  /// Ids dos traços de cada palavra (mesma ordem de [wordRects]).
  final List<List<String>> wordIds;
  final double endX;
}

List<Offset> _resample(List<Offset> pl, math.Random r, Hand h) {
  final pts = <Offset>[];
  final seg = <double>[0];
  for (var i = 1; i < pl.length; i++) {
    seg.add(seg.last + (pl[i] - pl[i - 1]).distance);
  }
  final total = seg.last;
  if (total < 1e-9) return [pl.first, pl.first, pl.first];
  var d = 0.0;
  var k = 0;
  while (d < total) {
    while (k < seg.length - 2 && seg[k + 1] < d) {
      k++;
    }
    final t = (d - seg[k]) / math.max(1e-9, seg[k + 1] - seg[k]);
    pts.add(Offset.lerp(pl[k], pl[k + 1], t.clamp(0.0, 1.0))!);
    d += h.spacing * (0.75 + 0.5 * r.nextDouble());
  }
  pts.add(pl.last);
  while (pts.length < 3) {
    pts.insert(pts.length - 1, Offset.lerp(pts.first, pts.last, 0.5)!);
  }
  return pts;
}

/// Escreve [text] com a baseline começando em [start] (x, y da baseline).
/// Espaços separam palavras. Retorna os traços na ordem da escrita.
Written writeLine(
  String text, {
  required Offset start,
  required IdGen ids,
  Hand hand = const Hand(),
  int argb = 0xFF101010,
  PenTool tool = PenTool.pen,
}) {
  final r = math.Random(hand.seed);
  final tan = math.tan(hand.slopeDeg * math.pi / 180);
  final strokes = <Stroke>[];
  final rects = <Rect>[];
  final wordIds = <List<String>>[];
  var x = start.dx;
  var wob = 0.0;

  Offset toPage(Offset g, double ox, double scale, double wobble) {
    // g: x/y em unidades de altura-x (y para cima). Itálico: x += slant*y.
    final px = ox + (g.dx + hand.slant * g.dy) * hand.xh * scale;
    final baseY = start.dy + tan * (px - start.dx);
    final py = baseY - (g.dy * scale + wobble) * hand.xh;
    return Offset(px, py);
  }

  Stroke make(List<Offset> pagePts) {
    final pts = _resample(pagePts, r, hand);
    return Stroke(
      id: ids.next(),
      tool: tool,
      argb: argb,
      width: hand.width,
      points: [
        for (var i = 0; i < pts.length; i++)
          InkPoint(
            pts[i].dx + (r.nextDouble() - 0.5) * 2 * hand.noise,
            pts[i].dy + (r.nextDouble() - 0.5) * 2 * hand.noise,
            0.35 + 0.3 * math.sin(i * 0.4).abs(),
          ),
      ],
    );
  }

  final words = text.split(' ').where((w) => w.isNotEmpty);
  var first = true;
  for (final word in words) {
    if (!first) x += hand.wordGap * hand.xh * (0.9 + 0.2 * r.nextDouble());
    first = false;
    final wordStart = strokes.length;
    final pendingExtras = <List<Offset>>[];
    double? minX, maxX, minY, maxY;
    void track(Stroke s) {
      final b = s.bounds;
      minX = math.min(minX ?? b.left, b.left);
      maxX = math.max(maxX ?? b.right, b.right);
      minY = math.min(minY ?? b.top, b.top);
      maxY = math.max(maxY ?? b.bottom, b.bottom);
    }

    for (final ch in word.split('')) {
      final gl = glyphs[ch] ?? glyphs[ch.toLowerCase()];
      if (gl == null) throw ArgumentError('letra sem glifo: $ch');
      final scale = 1 + (r.nextDouble() - 0.5) * 2 * hand.sizeVar;
      wob = (wob * 0.6 + (r.nextDouble() - 0.5) * 2 * hand.wobble).clamp(-0.15, 0.15);
      for (final pl in gl.main) {
        final s = make([for (final g in pl) toPage(g, x, scale, wob)]);
        strokes.add(s);
        track(s);
      }
      for (final pl in gl.extra) {
        final page = [for (final g in pl) toPage(g, x, scale, wob)];
        if (hand.delayExtras) {
          pendingExtras.add(page);
        } else {
          final s = make(page);
          strokes.add(s);
          track(s);
        }
      }
      x += (gl.adv * scale + hand.letterGap * (0.8 + 0.4 * r.nextDouble())) * hand.xh;
    }
    for (final page in pendingExtras) {
      final s = make(page);
      strokes.add(s);
      track(s);
    }
    x -= hand.letterGap * hand.xh;
    if (strokes.length > wordStart) {
      rects.add(Rect.fromLTRB(minX!, minY!, maxX!, maxY!));
      wordIds.add([for (final s in strokes.skip(wordStart)) s.id]);
    }
  }
  return Written(strokes, rects, wordIds, x);
}

/// Várias linhas de texto, uma por item, com [pitch] entre baselines.
/// Devolve o documento e a lista de [Written] por linha.
({PageDoc doc, List<Written> lines}) writePage(
  List<String> lines, {
  Offset origin = const Offset(80, 120),
  double pitch = 40,
  Hand hand = const Hand(),
  List<Hand>? perLine,
  IdGen? ids,
}) {
  final gen = ids ?? IdGen();
  final out = <Written>[];
  var doc = PageDoc.empty;
  for (var i = 0; i < lines.length; i++) {
    final h = perLine != null ? perLine[i] : hand.copyWith(seed: hand.seed + i);
    final w = writeLine(
      lines[i],
      start: Offset(origin.dx, origin.dy + i * pitch),
      ids: gen,
      hand: h,
    );
    out.add(w);
    doc = doc.withStrokes(w.strokes);
  }
  return (doc: doc, lines: out);
}

/// Palavra escrita "cursiva": um único traço contínuo em zigue-zague.
Stroke cursiveWordStroke(
  String id, {
  required Offset start,
  required int humps,
  double xh = 16,
  double humpWidth = 0.55,
  int seed = 1,
}) {
  final r = math.Random(seed);
  final pts = <Offset>[];
  var x = start.dx;
  for (var k = 0; k < humps; k++) {
    // sobe até a altura-x, desce de volta (com leve retrocesso ao fim da descida)
    for (var i = 0; i <= 8; i++) {
      final t = i / 8;
      pts.add(Offset(x + t * xh * humpWidth * 0.5, start.dy - xh * math.sin(t * math.pi * 0.5)));
    }
    x += xh * humpWidth * 0.5;
    for (var i = 1; i <= 8; i++) {
      final t = i / 8;
      pts.add(Offset(x + t * xh * humpWidth * 0.5 - (t > 0.8 ? 0.06 * xh : 0),
          start.dy - xh * math.cos(t * math.pi * 0.5)));
    }
    x += xh * humpWidth * 0.5 - 0.06 * xh;
  }
  return Stroke(
    id: id,
    tool: PenTool.pen,
    argb: 0xFF101010,
    width: 2.2,
    points: [
      for (final p in pts)
        InkPoint(p.dx + (r.nextDouble() - 0.5) * 0.4, p.dy + (r.nextDouble() - 0.5) * 0.4, 0.5),
    ],
  );
}

/// Traço de polilinha com [n] pontos entre os vértices (para gestos).
Stroke polyStroke(String id, List<Offset> verts, {int perSeg = 8, double noise = 0.2, int seed = 3, PenTool tool = PenTool.pen}) {
  final r = math.Random(seed);
  final pts = <Offset>[];
  for (var i = 0; i < verts.length - 1; i++) {
    for (var k = 0; k < perSeg; k++) {
      pts.add(Offset.lerp(verts[i], verts[i + 1], k / perSeg)!);
    }
  }
  pts.add(verts.last);
  return Stroke(
    id: id,
    tool: tool,
    argb: 0xFF101010,
    width: 2.2,
    points: [
      for (final p in pts)
        InkPoint(p.dx + (r.nextDouble() - 0.5) * 2 * noise, p.dy + (r.nextDouble() - 0.5) * 2 * noise, 0.5),
    ],
  );
}

/// Contador de ids "novos" para os testes de edição (ordenam depois dos `s…`).
class NewIds {
  NewIds([this.prefix = 'z']);
  final String prefix;
  int _n = 0;
  int get count => _n;
  String call() => '$prefix${(++_n).toString().padLeft(6, '0')}';
}

/// Vocabulário pt-BR (com acentos, ascendentes e descendentes) das páginas aleatórias.
const vocab = ['o','a','e','gato','quase','pegou','pequeno','gigante','você','nunca','viu','lillian','jogar','quando','chove','Lucas','estuda','matemática','para','prova','jantar','tarde','pode','ser','pior','que','perder','um','mil','vivo','uva','minimum','feliz','faz','casa','mesa','livro','água','fácil','hoje','amanhã','porque','também','então','já','até','são','mais','muito','sempre','nada','tudo','coração','ônibus','pão','maçã','irmão','vovô','mês','três'];


/// Página realista aleatória (determinística por [seed]): 3–6 linhas de 2–7
/// palavras; tamanho de letra da página sorteado (altura-x 13–24) com ±25 % de
/// variação entre linhas; inclinação de linha da página (−10° a 10°) com ±1° entre
/// linhas; linhas com 2,5× a maior altura-x entre baselines; pontos de i/barras de
/// t/acentos às vezes depois da palavra.
({PageDoc doc, List<Written> lines, List<String> desc}) randomPage(int seed) {
      final r = math.Random(seed);
      final nLines = 3 + r.nextInt(4);
      final gen = IdGen();
      var doc = PageDoc.empty;
      final lines = <Written>[];
      var y = 90.0 + r.nextDouble() * 40;
      final baseSlope = (r.nextDouble() * 20 - 10);
      final pageBase = 13 + r.nextDouble() * 11;
      var prevXh = 0.0;
      final desc = <String>[];
      for (var i = 0; i < nLines; i++) {
        final xh = pageBase * (0.8 + r.nextDouble() * 0.45);
        final nWords = 2 + r.nextInt(5);
        final words = <String>[];
        var chars = 0;
        for (var k = 0; k < nWords; k++) {
          final w = vocab[r.nextInt(vocab.length)];
          if ((chars + w.length + 1) * 1.3 * xh > 800 && words.isNotEmpty) break;
          words.add(w);
          chars += w.length + 1;
        }
        final text = words.join(' ');
        final slope = (baseSlope + (r.nextDouble() * 2 - 1)).clamp(-10.0, 10.0);
        y += (i == 0 ? 0 : 2.5 * math.max(prevXh, xh)) + r.nextDouble() * 8;
        final hand = Hand(xh: xh, slopeDeg: slope, seed: seed * 31 + i, wordGap: 0.95 + r.nextDouble() * 0.45, delayExtras: r.nextBool());
        final w = writeLine(text, start: Offset(40 + r.nextDouble() * 60, y + 120), ids: gen, hand: hand);
        lines.add(w);
        doc = doc.withStrokes(w.strokes);
        desc.add('xh=${xh.toStringAsFixed(1)} slope=${slope.toStringAsFixed(1)} "$text"');
        prevXh = xh;
      }
      return (doc: doc, lines: lines, desc: desc);
}
