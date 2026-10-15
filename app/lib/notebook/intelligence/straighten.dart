/// "Endireitar": deixa a escrita mais legível sem mudar o que foi escrito.
///
/// Por linha: gira a baseline para a horizontal, endireita a letra inclinada,
/// assenta cada palavra na mesma baseline, iguala a altura-x das palavras e o
/// espaçamento entre elas. Na página: com pautas (pautado, quadriculado,
/// pontilhado), cada linha vai para a pauta mais próxima e a letra se ajusta ao
/// espaço entre pautas; linhas que começam quase no mesmo x ficam alinhadas.
library;

import 'dart:math' as math;
import 'dart:ui' hide TextBox;

import '../core/notebook_core.dart';
import 'ink_edit.dart';
import 'ink_types.dart';
import 'segmentation.dart';

/// Abaixo disto (≈ 0,2°) a linha já é considerada reta.
const double _minAngle = 0.0035;

/// Limite da escala aplicada a uma palavra.
const double kMinWordScale = 0.75;
const double kMaxWordScale = 1.25;

/// Variação de altura-x menor que isto é ruído de escrita: não reescala.
const double _scaleDeadband = 0.03;

/// Lacunas que já diferem da mediana menos que isto (unidades) ficam como estão.
const double _gapDeadband = 0.75;

/// Inclinação da letra (tangente; 0,1 ≈ 6°) abaixo da qual não se mexe: o
/// itálico leve é parte da letra de cada um, o forte atrapalha a leitura.
const double _slantDeadband = 0.1;

/// Inclinação máxima corrigida (tangente; ≈ 35°): acima disso a estimativa não é confiável.
const double _maxSlant = 0.7;

/// Palavra fora da baseline por menos que isto (em alturas-x) fica onde está.
const double _wordBaseDeadband = 0.12;

/// Palavra fora da baseline por mais que isto (em alturas-x) é de propósito
/// (expoente, índice): não se mexe.
const double _wordBaseMax = 0.8;

/// Altura-x desejada na pauta, em frações do espaço entre pautas: dentro desta
/// faixa o tamanho fica como está; fora, é trazido para a borda mais próxima.
const double _ruleXhMin = 0.3;
const double _ruleXhMax = 0.6;

/// Limite da escala de uma linha inteira para caber na pauta.
const double _minLineScale = 0.7;
const double _maxLineScale = 1.4;

/// Linhas cujo início difere menos que isto (em alturas-x) ficam alinhadas à esquerda.
const double _leftAlignTolerance = 1.2;

/// As pautas da página (onde as baselines podem assentar).
class RuleGuide {
  const RuleGuide({required this.first, required this.spacing, required this.last});

  /// y da primeira e da última pauta.
  final double first, last;
  final double spacing;

  /// Índice da pauta mais próxima de [y], ou `null` se [y] está fora da área com
  /// pautas (mais de meia pauta acima da primeira ou abaixo da última).
  int? nearest(double y) {
    if (y < first - spacing / 2 || y > last + spacing / 2) return null;
    final k = ((y - first) / spacing).round();
    return k.clamp(0, count - 1);
  }

  int get count => ((last - first) / spacing).floor() + 1;

  double y(int k) => first + k * spacing;
}

/// As pautas de cada fundo de página (`null` = folha lisa, sem encaixe).
RuleGuide? ruleGuideFor(PageBackground background) => switch (background) {
      PageBackground.blank => null,
      PageBackground.lined => const RuleGuide(
          first: kLinedTop,
          spacing: kRuleSpacing,
          last: kLinedTop + kRuleSpacing * ((pageHeight - kLinedBottomMargin - kLinedTop) ~/ kRuleSpacing),
        ),
      PageBackground.grid || PageBackground.dots => const RuleGuide(
          first: kRuleSpacing,
          spacing: kRuleSpacing,
          last: kRuleSpacing * ((pageHeight - 1) ~/ kRuleSpacing),
        ),
    };

/// Endireita as linhas de escrita dentro de [ids].
///
/// Por linha (veja `segmentLines`):
///  1. gira em torno do início da linha para a baseline ficar horizontal;
///  2. endireita a letra inclinada (mais de ~6°), cisalhando em torno da baseline;
///  3. assenta na baseline as palavras que "pulam" para cima ou para baixo;
///  4. escala cada palavra (ancorada na esquerda e na baseline) para que a
///     altura-x dela seja a mediana das palavras da linha — escala limitada a
///     ±25 %, e palavra sem letras de altura-x (só 'l', 't'...) não é mexida;
///  5. reposiciona as palavras para que todas as lacunas sejam a mediana (a
///     primeira palavra fica onde está; se a linha passaria da borda direita
///     da página, as lacunas só encolhem).
///
/// Com [guide] (as pautas da página, veja [ruleGuideFor]):
///  6. a letra muito grande ou muito pequena para a pauta é ajustada (a linha
///     inteira, ±40 % no máximo);
///  7. a baseline de cada linha vai para a pauta mais próxima, de cima para
///     baixo, sem duas linhas na mesma pauta.
///
/// Por fim, linhas que começam quase no mesmo x ficam alinhadas à esquerda.
///
/// Não mexe em textos, imagens, marca-texto nem em traços fora das linhas. Cada
/// traço trocado vira outro com id de [newId] e o antigo recebe tombstone.
/// Se nada precisa mudar devolve o próprio [doc].
PageDoc straighten(PageDoc doc, Set<String> ids, String Function() newId, {RuleGuide? guide}) {
  if (ids.isEmpty || doc.strokes.isEmpty) return doc;
  final lines = segmentLines(doc, only: ids);
  if (lines.isEmpty) return doc;
  final results = [for (final line in lines) _straightenLine(doc, line, guide)];

  // 7. pautas: de cima para baixo, cada linha na pauta mais próxima ainda livre.
  if (guide != null) {
    final order = [for (var i = 0; i < results.length; i++) i]
      ..sort((a, b) => results[a].baseline.compareTo(results[b].baseline));
    var used = -1;
    for (final i in order) {
      final r = results[i];
      var k = guide.nearest(r.baseline);
      if (k == null) continue;
      if (k <= used) k = used + 1;
      if (k >= guide.count) continue;
      used = k;
      r.dy = guide.y(k) - r.baseline;
      if (r.dy.abs() < 0.5) r.dy = 0;
    }
  }

  // Margem: inícios de linha próximos viram um só (o mais à esquerda do grupo).
  if (results.length >= 2) {
    final order = [for (var i = 0; i < results.length; i++) i]
      ..sort((a, b) => results[a].left.compareTo(results[b].left));
    var g = 0;
    while (g < order.length) {
      final first = results[order[g]];
      final tol = _leftAlignTolerance * first.xh;
      var e = g + 1;
      while (e < order.length && results[order[e]].left - first.left <= tol) {
        e++;
      }
      if (e - g >= 2) {
        for (var j = g + 1; j < e; j++) {
          final r = results[order[j]];
          r.dx = first.left - r.left;
          if (r.dx.abs() < 0.5) r.dx = 0;
        }
      }
      g = e;
    }
  }

  final transforms = <String, Matrix2x3>{};
  for (final r in results) {
    final d = Offset(r.dx, r.dy);
    r.matrices.forEach((id, m) => transforms[id] = d == Offset.zero ? m : thenShift(m, d));
  }
  return remapStrokes(doc, transforms, newId);
}

double _median(List<double> v) {
  final s = [...v]..sort();
  return s[s.length ~/ 2];
}

/// Mediana ponderada de [v] com pesos [w].
double _weightedMedian(List<double> v, List<double> w) {
  final idx = [for (var i = 0; i < v.length; i++) i]..sort((a, b) => v[a].compareTo(v[b]));
  final total = w.fold<double>(0, (a, b) => a + b);
  var acc = 0.0;
  for (final i in idx) {
    acc += w[i];
    if (acc >= total / 2) return v[i];
  }
  return v[idx.last];
}

/// O que cada linha ficou devendo para os passos de página (pauta e margem).
class _LineResult {
  _LineResult(this.matrices, this.baseline, this.left, this.xh);

  /// Transformação de cada traço da linha (passos 1–6).
  final Map<String, Matrix2x3> matrices;

  /// y da baseline (a que se vê) e x do início da linha depois dos passos 1–6.
  final double baseline, left;
  final double xh;
  double dx = 0, dy = 0;
}

/// Inclinação da letra da [line] (tangente; positiva = tomba para a direita),
/// medida nas hastes; `null` se a linha tem poucas hastes para medir.
double? lineSlant(PageDoc doc, InkLine line) => _slantOf(
      [
        for (final w in line.words)
          for (final id in w.strokeIds) doc.strokeById(id)!,
      ],
      Matrix2x3.identity,
      lineXHeight(doc, line),
    );

/// Inclinação da letra (tangente; positiva = tomba para a direita) a partir dos
/// trechos quase verticais dos traços, já com [m] aplicada. `null` sem dados.
double? _slantOf(List<Stroke> strokes, Matrix2x3 m, double xh) {
  final values = <double>[], weights = <double>[];
  final minDy = 0.45 * xh;
  for (final s in strokes) {
    final pts = [for (final p in s.points) m.apply(p.offset)];
    var j = 0;
    for (var i = 0; i < pts.length; i++) {
      if (j <= i) j = i + 1;
      while (j < pts.length && (pts[j].dy - pts[i].dy).abs() < minDy) {
        j++;
      }
      if (j >= pts.length) break;
      final d = pts[j] - pts[i];
      if (d.dx.abs() > d.dy.abs() * 0.9) continue; // não é um trecho de "haste"
      // y cresce para baixo: tombar para a direita = topo à direita da base.
      final slope = -(d.dy > 0 ? d.dx / d.dy : -d.dx / -d.dy);
      values.add(slope);
      weights.add(d.dy.abs());
    }
  }
  if (values.length < 6) return null;
  return _weightedMedian(values, weights);
}

_LineResult _straightenLine(PageDoc doc, InkLine line, RuleGuide? guide) {
  final xhLine = lineXHeight(doc, line);
  final base = line.baselineY;
  final anchor = Offset(line.bounds.left, base);
  final rot = line.angle.abs() >= _minAngle ? Matrix2x3.rotation(-line.angle, anchor: anchor) : Matrix2x3.identity;

  final all = [
    for (final w in line.words)
      for (final id in w.strokeIds) doc.strokeById(id)!,
  ];

  // 2. letra inclinada: cisalha em torno da baseline (a baseline não se move).
  var upright = rot;
  final slant = _slantOf(all, rot, xhLine);
  if (slant != null && slant.abs() >= _slantDeadband) {
    final k = slant.clamp(-_maxSlant, _maxSlant);
    // x' = x + k·(y − base): o topo volta para a esquerda (ou direita) na medida da inclinação.
    upright = Matrix2x3(1, 0, k, 1, -k * base, 0) * rot;
  }

  // Por palavra: traços, caixa e altura-x depois de girar e endireitar.
  final n = line.words.length;
  final strokes = <List<Stroke>>[];
  final left = <double>[], right = <double>[];
  final xhWord = <double?>[];
  final baseWord = <double?>[];
  for (final w in line.words) {
    final ss = [for (final id in w.strokeIds) doc.strokeById(id)!];
    strokes.add(ss);
    var l = double.infinity, r = -double.infinity;
    final hs = <double>[], bottoms = <double>[];
    for (final s in ss) {
      final b = transformedPointBox(s, upright);
      l = math.min(l, b.left - s.width / 2);
      r = math.max(r, b.right + s.width / 2);
      if (b.height >= 0.4 * xhLine && b.height <= 1.6 * xhLine) {
        hs.add(b.height);
        bottoms.add(b.bottom);
      }
    }
    left.add(l);
    right.add(r);
    xhWord.add(hs.length >= 2 ? _median(hs) : null);
    baseWord.add(bottoms.isEmpty ? null : _median(bottoms));
  }

  // 3. palavra fora da baseline: assenta (só o desvio de escrita, não expoentes).
  final lift = List<double>.filled(n, 0.0);
  for (var i = 0; i < n; i++) {
    final b = baseWord[i];
    if (b == null) continue;
    final d = base - b;
    if (d.abs() >= _wordBaseDeadband * xhLine && d.abs() <= _wordBaseMax * xhLine) lift[i] = d;
  }

  // 4. escalas: altura-x de cada palavra → mediana das palavras com altura-x.
  final valid = [for (final h in xhWord) ?h];
  final scale = List<double>.filled(n, 1.0);
  if (valid.length >= 2) {
    final target = _median(valid);
    for (var i = 0; i < n; i++) {
      final h = xhWord[i];
      if (h == null) continue;
      final s = (target / h).clamp(kMinWordScale, kMaxWordScale);
      if ((s - 1).abs() >= _scaleDeadband) scale[i] = s;
    }
  }
  // (ancorada na esquerda da palavra e na baseline: a esquerda não se move)
  final scaledRight = [for (var i = 0; i < n; i++) left[i] + (right[i] - left[i]) * scale[i]];

  // 5. lacunas → mediana das lacunas originais (a escala cresce a palavra para a
  // direita e comeria a lacuna; as posições novas partem das larguras já
  // reescaladas).
  final shift = List<double>.filled(n, 0.0);
  if (n >= 2) {
    final gaps = [for (var i = 1; i < n; i++) left[i] - right[i - 1]];
    final target = _median(gaps);
    List<double> place(List<double> gapFor) {
      var cursor = scaledRight[0];
      final want = <double>[0.0];
      for (var i = 1; i < n; i++) {
        final newLeft = cursor + gapFor[i - 1];
        want.add(newLeft - left[i]);
        cursor = newLeft + (scaledRight[i] - left[i]);
      }
      return want..add(cursor);
    }

    var want = place(List<double>.filled(n - 1, target));
    if (want.last > pageWidth - 4) {
      // não cabe: só encolhe lacunas (nunca aumenta)
      want = place([for (final g in gaps) math.min(g, target)]);
    }
    if (want.last <= pageWidth - 4 || want.last <= right.last + 0.5) {
      for (var i = 1; i < n; i++) {
        shift[i] = want[i];
      }
      // deslocamentos pequenos demais para mudar alguma lacuna são ruído
      if (shift.every((d) => d.abs() < _gapDeadband)) shift.fillRange(0, n, 0.0);
    }
  }

  // 6. tamanho para a pauta: a linha inteira, ancorada no início e na baseline,
  // sem passar da borda direita.
  var lineScale = 1.0;
  final lineLeft = left.reduce(math.min);
  if (guide != null) {
    final lo = _ruleXhMin * guide.spacing, hi = _ruleXhMax * guide.spacing;
    final targetXh = xhLine.clamp(lo, hi);
    var s = (targetXh / xhLine).clamp(_minLineScale, _maxLineScale);
    final lineRight = n == 0 ? lineLeft : scaledRight.last + shift.last;
    if (lineRight > lineLeft && lineLeft + (lineRight - lineLeft) * s > pageWidth - 4) {
      s = math.min(s, math.max(1.0, (pageWidth - 4 - lineLeft) / (lineRight - lineLeft)));
    }
    if ((s - 1).abs() >= _scaleDeadband) lineScale = s;
  }

  final matrices = <String, Matrix2x3>{};
  for (var i = 0; i < n; i++) {
    var m = upright;
    if (lift[i] != 0.0) m = thenShift(m, Offset(0, lift[i]));
    if (scale[i] != 1.0) m = Matrix2x3.scaling(scale[i], anchor: Offset(left[i], base)) * m;
    if (shift[i] != 0.0) m = thenShift(m, Offset(shift[i], 0));
    if (lineScale != 1.0) m = Matrix2x3.scaling(lineScale, anchor: Offset(lineLeft, base)) * m;
    for (final s in strokes[i]) {
      matrices[s.id] = m;
    }
  }

  // A baseline que se vê depois dos passos 1–6: a mediana do pé das letras de
  // altura-x (é ela que vai para a pauta; o ajuste da reta da segmentação puxa
  // para a ponta em linhas que sobem ou descem).
  final feet = <double>[];
  for (var i = 0; i < n; i++) {
    for (final s in strokes[i]) {
      final b = transformedPointBox(s, matrices[s.id]!);
      final h = b.height / lineScale;
      if (h >= 0.4 * xhLine && h <= 1.6 * xhLine) feet.add(b.bottom);
    }
  }
  final seen = feet.length >= 3 ? _median(feet) : base;
  return _LineResult(matrices, seen, lineLeft, xhLine * lineScale);
}
