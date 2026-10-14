/// Gestos de edição feitos com a caneta sobre a escrita: rabisco apaga, ∧ abre
/// espaço, traço vertical separa a palavra, arco ∪ junta duas palavras.
///
/// Regra de ouro: **só reconhece com confiança alta**. Qualquer dúvida devolve
/// `null` e o traço vira tinta normal (apagar uma palavra sem querer é pior que
/// ter de repetir o gesto). Por isso cada gesto exige, além da forma do traço,
/// uma posição que a escrita normal não ocupa:
///
///  * rabisco: ≥ 4 inversões horizontais (varreduras com pelo menos 30 % da
///    largura do traço) sobre ≥ 60 % de uma palavra;
///  * ∧: dois segmentos retos (Douglas–Peucker) com ângulo de 30° a 120° e a
///    ponta para cima, do tamanho de 0,35–1,6 altura-x (a letra A maiúscula, de
///    2 alturas-x, não vale), **dentro do vão entre duas palavras** e na altura
///    da linha (um acento circunflexo fica em cima das letras, dentro da palavra);
///  * vertical: reto, largura ≤ 15 % da altura, altura ≥ 80 % da palavra e
///    atravessando uma palavra **do alto da altura-x até abaixo da baseline**
///    (o 'l' não desce da baseline; o 'p' e o 'g' não sobem da altura-x);
///  * arco: copo liso (sem laços), mais largo que fundo, **abaixo da baseline**
///    e debaixo do vão entre duas palavras (o 'u' e o 'v' ficam na altura-x).
library;

import 'dart:math' as math;
import 'dart:ui' hide TextBox;

import 'package:flutter/foundation.dart' show setEquals;

import '../core/ink_math.dart' show distPointSegment;
import '../core/notebook_core.dart';
import 'ink_edit.dart';
import 'ink_types.dart';
import 'segmentation.dart';

/// Um gesto de edição reconhecido. Aplique com [applyGesture].
sealed class InkGesture {
  const InkGesture();
}

/// Rabisco sobre palavra(s): apaga os traços em [targetIds].
final class ScratchOut extends InkGesture {
  const ScratchOut(this.targetIds);
  final Set<String> targetIds;

  @override
  bool operator ==(Object other) =>
      other is ScratchOut && setEquals(other.targetIds, targetIds);

  @override
  int get hashCode => Object.hashAllUnordered(targetIds);

  @override
  String toString() => 'ScratchOut(${targetIds.length} traços)';
}

/// ∧ entre duas palavras: abre [width] de espaço em [at] (x do vão, y da
/// baseline da linha ali). A tela pode oferecer uma caixa de texto no vão.
final class InsertSpace extends InkGesture {
  const InsertSpace(this.at, this.width);
  final Offset at;
  final double width;

  @override
  bool operator ==(Object other) =>
      other is InsertSpace && other.at == at && other.width == width;

  @override
  int get hashCode => Object.hash(at, width);

  @override
  String toString() => 'InsertSpace($at, $width)';
}

/// Traço vertical atravessando uma palavra: separa-a em [x].
/// [strokeOrWordIds] é a chave da palavra (`InkWord.key`: os ids dos traços
/// dela ordenados e unidos por ','); um único id de traço da palavra também vale.
final class SplitWord extends InkGesture {
  const SplitWord(this.strokeOrWordIds, this.x);
  final String strokeOrWordIds;
  final double x;

  @override
  bool operator ==(Object other) =>
      other is SplitWord && other.strokeOrWordIds == strokeOrWordIds && other.x == x;

  @override
  int get hashCode => Object.hash(strokeOrWordIds, x);

  @override
  String toString() => 'SplitWord($strokeOrWordIds, $x)';
}

/// Arco ∪ sob o vão entre duas palavras: [ids] são os traços das duas.
final class JoinWords extends InkGesture {
  const JoinWords(this.ids);
  final Set<String> ids;

  @override
  bool operator ==(Object other) => other is JoinWords && setEquals(other.ids, ids);

  @override
  int get hashCode => Object.hashAllUnordered(ids);

  @override
  String toString() => 'JoinWords(${ids.length} traços)';
}

// ---------------------------------------------------------------------------
// Limiares (veja o comentário de cada gesto no topo do arquivo)

const int _scratchMinReversals = 4;
const double _scratchSwing = 0.3; // fração da largura do traço
const double _scratchCover = 0.6; // fração da palavra coberta

const double _caretMinAngle = 30, _caretMaxAngle = 120; // graus
const double _caretMinSize = 0.35, _caretMaxSize = 1.6; // alturas-x

const double _vertMaxWidthRatio = 0.15;
const double _vertMinLineRatio = 0.8;
const double _vertOvershoot = 0.35; // alturas-x acima da altura-x e abaixo da baseline
const double _vertMaxHeight = 4; // alturas-x
const double _vertEdge = 0.3; // alturas-x de folga até a borda da palavra

const double _arcMinAspect = 1.1; // largura / profundidade
const double _arcMinDepth = 0.2, _arcMaxDepth = 1.5; // alturas-x

/// Lacuna que `SplitWord` abre (alturas-x): acima do limiar de palavra (0,6).
const double _splitGap = 1.0;

/// Lacuna que `JoinWords` deixa (alturas-x): abaixo do limiar de palavra.
const double _joinGap = 0.2;

// ---------------------------------------------------------------------------
// Geometria do traço

List<Offset> _points(Stroke s) {
  final out = <Offset>[];
  for (final p in s.points) {
    final o = p.offset;
    if (out.isEmpty || (o - out.last).distanceSquared > 0.0025) out.add(o);
  }
  return out;
}

Rect _box(List<Offset> pts) {
  var l = double.infinity, r = -double.infinity, t = double.infinity, b = -double.infinity;
  for (final p in pts) {
    l = math.min(l, p.dx);
    r = math.max(r, p.dx);
    t = math.min(t, p.dy);
    b = math.max(b, p.dy);
  }
  return Rect.fromLTRB(l, t, r, b);
}

double _pathLength(List<Offset> pts) {
  var d = 0.0;
  for (var i = 1; i < pts.length; i++) {
    d += (pts[i] - pts[i - 1]).distance;
  }
  return d;
}

/// Douglas–Peucker: vértices que sobram com tolerância [eps].
List<Offset> _simplify(List<Offset> pts, double eps) {
  if (pts.length < 3) return pts;
  final keep = List<bool>.filled(pts.length, false);
  keep[0] = keep[pts.length - 1] = true;
  final stack = <(int, int)>[(0, pts.length - 1)];
  while (stack.isNotEmpty) {
    final (a, b) = stack.removeLast();
    var worst = -1.0;
    var idx = -1;
    for (var i = a + 1; i < b; i++) {
      final d = distPointSegment(pts[i], pts[a], pts[b]);
      if (d > worst) {
        worst = d;
        idx = i;
      }
    }
    if (worst > eps && idx > 0) {
      keep[idx] = true;
      stack.add((a, idx));
      stack.add((idx, b));
    }
  }
  return [for (var i = 0; i < pts.length; i++) if (keep[i]) pts[i]];
}

/// Reamostra o traço em [n] pontos igualmente espaçados ao longo do caminho.
List<Offset> _resample(List<Offset> pts, int n) {
  final total = _pathLength(pts);
  if (total <= 0 || pts.length < 2) return pts;
  final out = <Offset>[pts.first];
  final step = total / (n - 1);
  var acc = 0.0;
  var next = step;
  for (var i = 1; i < pts.length && out.length < n; i++) {
    final seg = (pts[i] - pts[i - 1]).distance;
    while (acc + seg >= next && out.length < n) {
      final t = (next - acc) / seg;
      out.add(Offset.lerp(pts[i - 1], pts[i], t)!);
      next += step;
    }
    acc += seg;
  }
  while (out.length < n) {
    out.add(pts.last);
  }
  return out;
}

/// Inversões de direção em x, com histerese de [theta] unidades.
int _xReversals(List<Offset> pts, double theta) {
  var dir = 0;
  var lo = pts.first.dx, hi = pts.first.dx;
  var ext = pts.first.dx;
  var reversals = 0;
  for (final p in pts) {
    final x = p.dx;
    if (dir == 0) {
      lo = math.min(lo, x);
      hi = math.max(hi, x);
      if (hi - lo >= theta) {
        dir = (x - lo).abs() < (hi - x).abs() ? -1 : 1;
        ext = x;
      }
    } else if (dir == 1) {
      if (x > ext) {
        ext = x;
      } else if (ext - x >= theta) {
        reversals++;
        dir = -1;
        ext = x;
      }
    } else {
      if (x < ext) {
        ext = x;
      } else if (x - ext >= theta) {
        reversals++;
        dir = 1;
        ext = x;
      }
    }
  }
  return reversals;
}

// ---------------------------------------------------------------------------
// Contexto: linhas e palavras perto do traço, sem o próprio traço

class _W {
  _W(this.key, this.ids, this.bounds);
  final String key;
  final List<String> ids;
  final Rect bounds;
}

class _L {
  _L(this.line, this.xh, this.words);
  final InkLine line;
  final double xh;
  final List<_W> words;
  double baseAt(double x) => lineBaselineAt(line, x);
}

List<_L> _context(Stroke s, PageDoc doc, List<InkLine> lines, Rect near) {
  final out = <_L>[];
  for (final line in lines) {
    final xh = lineXHeight(doc, line);
    if (!line.bounds.inflate(3 * xh).overlaps(near)) continue;
    final words = <_W>[];
    for (final w in line.words) {
      if (!w.strokeIds.contains(s.id)) {
        words.add(_W(w.key, w.strokeIds, w.bounds));
        continue;
      }
      final ids = [for (final id in w.strokeIds) if (id != s.id) id];
      if (ids.isEmpty) continue;
      Rect? b;
      for (final id in ids) {
        final st = doc.strokeById(id);
        if (st == null) continue;
        b = b == null ? st.bounds : b.expandToInclude(st.bounds);
      }
      if (b != null) words.add(_W(wordKey(ids), ids, b));
    }
    if (words.isNotEmpty) out.add(_L(line, xh, words));
  }
  return out;
}

/// O traço [path] encosta em tinta que não seja a das [except] nem o próprio
/// [self]? Um ∧ ou ∪ de verdade é desenhado em espaço livre entre as duas
/// palavras; um traço que toca em outra tinta (a "r" de uma linha de baixo, com a
/// haste colada) é letra. "Encostar" = a menos de 3 unidades (a caneta tem
/// ~2 de espessura).
bool _touchesOtherInk(PageDoc doc, Stroke self, List<Offset> path, Rect box, Set<String> except) {
  final zone = box.inflate(4);
  for (final s in doc.strokes) {
    if (s.id == self.id || except.contains(s.id) || !s.bounds.overlaps(zone)) continue;
    for (final p in s.points) {
      final o = p.offset;
      if (!zone.contains(o)) continue;
      for (var i = 0; i + 1 < path.length; i++) {
        if (distPointSegment(o, path[i], path[i + 1]) <= 3) return true;
      }
    }
  }
  return false;
}

// ---------------------------------------------------------------------------
// Reconhecimento

/// Reconhece um gesto de edição no traço [s] (recém-terminado) sobre [doc], com
/// as [lines] de `segmentLines(doc)`. Só devolve algo com confiança alta; senão
/// `null` e o traço vira tinta normal. [s] pode ou não já estar em [doc] (e em
/// [lines]): ele é ignorado ao olhar a escrita ao redor.
InkGesture? detectGesture(Stroke s, PageDoc doc, List<InkLine> lines) {
  if (s.tool == PenTool.highlighter || lines.isEmpty) return null;
  final pts = _points(s);
  if (pts.length < 5) return null;
  final box = _box(pts);
  if (box.width < 1 && box.height < 1) return null;
  final path = _pathLength(pts);
  final ctx = _context(s, doc, lines, box.inflate(2));
  if (ctx.isEmpty) return null;

  return _scratch(pts, box, path, ctx) ??
      _caret(s, doc, pts, box, path, ctx) ??
      _vertical(pts, box, path, ctx) ??
      _arc(s, doc, pts, box, path, ctx);
}

InkGesture? _scratch(List<Offset> pts, Rect box, double path, List<_L> ctx) {
  if (box.width < 10 || path < 2.5 * box.width) return null;
  if (_xReversals(pts, math.max(_scratchSwing * box.width, 3)) < _scratchMinReversals) {
    return null;
  }
  final targets = <String>{};
  for (final l in ctx) {
    for (final w in l.words) {
      final b = w.bounds;
      final overlapX = math.min(box.right, b.right) - math.max(box.left, b.left);
      if (overlapX < _scratchCover * b.width) continue;
      // na altura da palavra (nem um rabisco enorme, nem um risquinho)
      if (box.center.dy < b.top - 0.35 * b.height || box.center.dy > b.bottom + 0.35 * b.height) continue;
      if (box.height > 2.2 * b.height + l.xh) continue;
      if (box.height < 0.2 * b.height) continue;
      targets.addAll(w.ids);
    }
  }
  return targets.isEmpty ? null : ScratchOut(targets);
}

InkGesture? _caret(Stroke self, PageDoc doc, List<Offset> pts, Rect box, double path, List<_L> ctx) {
  final d = math.sqrt(box.width * box.width + box.height * box.height);
  final v = _simplify(pts, 0.09 * d);
  if (v.length != 3) return null;
  final a = v[0], b = v[1], c = v[2];
  // ponta para cima: o vértice é o ponto mais alto e os pés ficam na metade de baixo
  if (b.dy > box.top + 0.1 * box.height) return null;
  if (a.dy < box.top + 0.5 * box.height || c.dy < box.top + 0.5 * box.height) return null;
  if ((a.dy - c.dy).abs() > 0.5 * box.height) return null;
  final u = a - b, w = c - b;
  final lu = u.distance, lw = w.distance;
  if (lu < 1e-6 || lw < 1e-6) return null;
  final cosA = ((u.dx * w.dx + u.dy * w.dy) / (lu * lw)).clamp(-1.0, 1.0);
  final angle = math.acos(cosA) * 180 / math.pi;
  if (angle < _caretMinAngle || angle > _caretMaxAngle) return null;
  if (math.min(lu, lw) / math.max(lu, lw) < 0.45) return null;
  if (path > 1.35 * (lu + lw)) return null; // laços e idas e vindas
  final footSpan = (c.dx - a.dx).abs();
  if (footSpan > 1e-6) {
    final f = (b.dx - math.min(a.dx, c.dx)) / footSpan;
    if (f < 0.2 || f > 0.8) return null;
  }

  for (final l in ctx) {
    final xh = l.xh;
    final h = box.height / xh;
    if (h < _caretMinSize || h > _caretMaxSize) continue;
    if (box.width < 0.3 * xh || box.width > 2.0 * xh) continue;
    final bl = l.baseAt(b.dx);
    // na altura da linha: do alto da altura-x até a zona dos descendentes
    // (mais embaixo já é a linha seguinte)
    if (box.center.dy < bl - 1.0 * xh || box.bottom > bl + 1.3 * xh) continue;
    if (box.bottom < bl - 0.5 * xh) continue;
    for (var i = 0; i + 1 < l.words.length; i++) {
      final gl = l.words[i].bounds.right, gr = l.words[i + 1].bounds.left;
      if (b.dx < gl - 0.15 * xh || b.dx > gr + 0.15 * xh) continue;
      if (box.left < gl - 0.8 * xh || box.right > gr + 0.8 * xh) continue;
      if (_touchesOtherInk(doc, self, pts, box, {...l.words[i].ids, ...l.words[i + 1].ids})) continue;
      return InsertSpace(Offset(b.dx, bl), (7 * xh).clamp(70.0, 260.0));
    }
  }
  return null;
}

InkGesture? _vertical(List<Offset> pts, Rect box, double path, List<_L> ctx) {
  if (box.height < 6 || box.width > _vertMaxWidthRatio * box.height) return null;
  final chord = (pts.last - pts.first).distance;
  if (chord < 0.85 * box.height) return null;
  if (path > 1.25 * chord) return null;
  var dev = 0.0;
  for (final p in pts) {
    dev = math.max(dev, distPointSegment(p, pts.first, pts.last));
  }
  if (dev > 0.1 * box.height) return null;
  final x = (pts.first.dx + pts.last.dx) / 2;

  for (final l in ctx) {
    final xh = l.xh;
    if (box.height > _vertMaxHeight * xh) continue;
    final bl = l.baseAt(x);
    if (box.top > bl - (1 + _vertOvershoot) * xh) continue; // não sobe acima da altura-x
    if (box.bottom < bl + _vertOvershoot * xh) continue; // não desce abaixo da baseline
    for (final w in l.words) {
      final b = w.bounds;
      if (b.width < 1.2 * xh) continue;
      if (x < b.left + _vertEdge * xh || x > b.right - _vertEdge * xh) continue;
      // altura ≥ 80 % da palavra que atravessa (a da linha inteira, num texto
      // inclinado, inclui a subida da baseline e passa de 4 alturas-x)
      if (box.height < _vertMinLineRatio * b.height) continue;
      return SplitWord(w.key, x);
    }
  }
  return null;
}

InkGesture? _arc(Stroke self, PageDoc doc, List<Offset> pts, Rect box, double path, List<_L> ctx) {
  if (box.height < 3 || box.width < _arcMinAspect * box.height) return null;
  final r = _resample(pts, 24);
  if (r.length < 24) return null;
  var iMin = 0; // ponto mais baixo (maior y)
  for (var i = 0; i < r.length; i++) {
    if (r[i].dy > r[iMin].dy) iMin = i;
  }
  final a = r.first, c = r.last, bottom = r[iMin];
  final lim = box.top + 0.6 * box.height;
  if (a.dy > lim || c.dy > lim) return null; // as pontas ficam no alto do copo
  if (bottom.dx < box.left + 0.25 * box.width || bottom.dx > box.right - 0.25 * box.width) return null;
  // sem laços: y desce até o fundo e sobe depois; x anda sempre para o mesmo lado
  final tolY = 0.15 * box.height, tolX = 0.15 * box.width;
  final sign = (c.dx - a.dx) >= 0 ? 1.0 : -1.0;
  if ((c.dx - a.dx).abs() < 0.6 * box.width) return null;
  for (var i = 0; i + 1 < r.length; i++) {
    final dy = r[i + 1].dy - r[i].dy;
    if (i < iMin ? dy < -tolY : dy > tolY) return null;
    if (sign * (r[i + 1].dx - r[i].dx) < -tolX) return null;
  }
  // a curva precisa ser mesmo um copo, não uma diagonal: o fundo fica bem
  // abaixo da corda entre as pontas
  final sag = bottom.dy - (a.dy + c.dy) / 2;
  if (sag < 0.4 * box.height) return null;

  for (final l in ctx) {
    final xh = l.xh;
    final depth = box.height / xh;
    if (depth < _arcMinDepth || depth > _arcMaxDepth) continue;
    final bl = l.baseAt(bottom.dx);
    // sob a baseline (as pontas do "u" ficam na altura-x, bem acima) e ainda
    // colado nela (mais embaixo já é a linha seguinte)
    if (math.min(a.dy, c.dy) < bl - 0.3 * xh || math.max(a.dy, c.dy) > bl + 1.0 * xh) continue;
    if (box.bottom > bl + 2.2 * xh) continue;
    for (var i = 0; i + 1 < l.words.length; i++) {
      final wa = l.words[i].bounds, wb = l.words[i + 1].bounds;
      final gl = wa.right, gr = wb.left;
      final gc = (gl + gr) / 2;
      if (gc < box.left || gc > box.right) continue;
      if (box.width > (gr - gl) + 3 * xh) continue;
      if (box.left < wa.left || box.right > wb.right) continue;
      if (_touchesOtherInk(doc, self, pts, box, {...l.words[i].ids, ...l.words[i + 1].ids})) continue;
      return JoinWords({...l.words[i].ids, ...l.words[i + 1].ids});
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Aplicação

/// Aplica [g] a [doc]. Edição = apagar + criar: traços movidos ou partidos
/// ganham ids de [newId] e os antigos viram tombstones; sem efeito devolve o
/// próprio [doc]. Determinístico.
PageDoc applyGesture(PageDoc doc, InkGesture g, String Function() newId) =>
    switch (g) {
      ScratchOut() => _applyScratch(doc, g),
      InsertSpace() => _applyInsert(doc, g, newId),
      JoinWords() => _applyJoin(doc, g, newId),
      SplitWord() => _applySplit(doc, g, newId),
    };

PageDoc _applyScratch(PageDoc doc, ScratchOut g) {
  final ids = {for (final id in g.targetIds) if (doc.contains(id)) id};
  return ids.isEmpty ? doc : doc.without(ids);
}

/// Translação ao longo da baseline da linha: [dx] na horizontal e o que a
/// inclinação pedir na vertical.
Matrix2x3 _alongLine(InkLine line, double dx) =>
    Matrix2x3.translation(dx, dx * math.tan(line.angle));

PageDoc _applyInsert(PageDoc doc, InsertSpace g, String Function() newId) {
  final line = _lineAt(doc, g.at);
  if (line == null) return doc;
  final moving = [
    for (final w in line.words)
      if (w.bounds.left >= g.at.dx - 0.01) ...w.strokeIds,
  ];
  if (moving.isEmpty) return doc;
  final room = pageWidth - 4 - line.bounds.right;
  final d = math.min(g.width, room);
  if (d < 1) return doc;
  final m = _alongLine(line, d);
  return remapStrokes(doc, {for (final id in moving) id: m}, newId);
}

/// A linha de [doc] cuja baseline passa mais perto de [at], entre as que têm
/// [at] na faixa vertical (com folga de uma altura-x) e dentro do alcance x.
InkLine? _lineAt(PageDoc doc, Offset at) {
  InkLine? best;
  var bestD = double.infinity;
  for (final line in segmentLines(doc)) {
    final xh = lineXHeight(doc, line);
    if (at.dx < line.bounds.left - xh || at.dx > line.bounds.right + xh) continue;
    final d = (lineBaselineAt(line, at.dx) - at.dy).abs();
    if (d > 2 * xh) continue;
    if (d < bestD) {
      bestD = d;
      best = line;
    }
  }
  return best;
}

PageDoc _applyJoin(PageDoc doc, JoinWords g, String Function() newId) {
  for (final line in segmentLines(doc, only: null)) {
    for (var i = 0; i + 1 < line.words.length; i++) {
      final a = line.words[i], b = line.words[i + 1];
      if (!a.strokeIds.any(g.ids.contains) || !b.strokeIds.any(g.ids.contains)) continue;
      final xh = lineXHeight(doc, line);
      final gap = b.bounds.left - a.bounds.right;
      final shift = gap - _joinGap * xh;
      if (shift < 0.5) return doc;
      final m = _alongLine(line, -shift);
      final moving = [for (var k = i + 1; k < line.words.length; k++) ...line.words[k].strokeIds];
      return remapStrokes(doc, {for (final id in moving) id: m}, newId);
    }
  }
  return doc;
}

PageDoc _applySplit(PageDoc doc, SplitWord g, String Function() newId) {
  // acha a palavra pela chave (ou por um id de traço dela)
  InkLine? line;
  InkWord? word;
  outer:
  for (final l in segmentLines(doc)) {
    for (final w in l.words) {
      if (w.key == g.strokeOrWordIds || w.strokeIds.contains(g.strokeOrWordIds)) {
        line = l;
        word = w;
        break outer;
      }
    }
  }
  if (line == null || word == null) return doc;
  final xh = lineXHeight(doc, line);
  final x = g.x;
  final lineIds = line.strokeIds.toSet();
  final wordIds = word.strokeIds.toSet();
  final eps = 0.08 * xh;

  // 1. o que atravessa x (só dentro da palavra) é cortado; o resto da linha
  // vai para a esquerda ou para a direita conforme o centro
  final cuts = <String, List<(bool, List<InkPoint>)>>{}; // id → trechos (direita?, pontos)
  final movesRight = <String>{};
  var leftEdge = -double.infinity, rightEdge = double.infinity;
  for (final s in doc.strokes) {
    if (!lineIds.contains(s.id)) continue;
    final straddles = wordIds.contains(s.id) &&
        s.points.any((p) => p.x < x - eps) &&
        s.points.any((p) => p.x > x + eps);
    if (straddles) {
      final runs = _cutAt(s.points, x);
      cuts[s.id] = runs;
      for (final (right, run) in runs) {
        for (final p in run) {
          if (right) {
            rightEdge = math.min(rightEdge, p.x);
          } else {
            leftEdge = math.max(leftEdge, p.x);
          }
        }
      }
    } else if (s.bounds.center.dx > x) {
      movesRight.add(s.id);
      rightEdge = math.min(rightEdge, s.bounds.left);
    } else {
      leftEdge = math.max(leftEdge, s.bounds.right);
    }
  }
  if (cuts.isEmpty && movesRight.isEmpty) return doc;
  if (!leftEdge.isFinite) leftEdge = x;
  if (!rightEdge.isFinite) rightEdge = x;

  // 2. deslocamento que deixa a lacuna em _splitGap alturas-x (cabendo na página)
  final current = math.max(0.0, rightEdge - leftEdge);
  final d = math.min(_splitGap * xh - current, pageWidth - 4 - line.bounds.right);
  if (d < 0.5) return doc;
  final m = _alongLine(line, d);

  // 3. monta o documento novo na ordem dos traços (ids determinísticos)
  final removed = <String>{};
  final added = <Stroke>[];
  for (final s in doc.strokes) {
    final runs = cuts[s.id];
    if (runs != null) {
      removed.add(s.id);
      for (final (right, run) in runs) {
        if (_runLength(run) < 0.3) continue; // fiapo do corte
        added.add(s.copyWith(
          id: newId(),
          points: right ? [for (final p in run) _moved(p, m)] : run,
        ));
      }
    } else if (movesRight.contains(s.id)) {
      removed.add(s.id);
      added.add(s.copyWith(id: newId(), points: [for (final p in s.points) _moved(p, m)]));
    }
  }
  return doc.without(removed).withStrokes(added);
}

InkPoint _moved(InkPoint p, Matrix2x3 m) {
  final o = m.apply(p.offset);
  return InkPoint(o.dx, o.dy, p.p);
}

double _runLength(List<InkPoint> run) {
  var d = 0.0;
  for (var i = 1; i < run.length; i++) {
    d += (run[i].offset - run[i - 1].offset).distance;
  }
  return d;
}

/// Parte uma polilinha nos cruzamentos com a vertical x = [x]: trechos
/// alternados à esquerda/direita (`direita?`, pontos), com o ponto de
/// cruzamento (interpolado) nas duas pontas vizinhas.
List<(bool, List<InkPoint>)> _cutAt(List<InkPoint> pts, double x) {
  final runs = <(bool, List<InkPoint>)>[];
  var cur = <InkPoint>[pts.first];
  var right = pts.first.x >= x;
  for (var i = 1; i < pts.length; i++) {
    final a = pts[i - 1], b = pts[i];
    final bRight = b.x >= x;
    if (bRight != right) {
      final t = (x - a.x) / (b.x - a.x);
      final cross = InkPoint(x, a.y + (b.y - a.y) * t, a.p + (b.p - a.p) * t);
      cur.add(cross);
      runs.add((right, cur));
      cur = <InkPoint>[cross];
      right = bRight;
    }
    cur.add(b);
  }
  runs.add((right, cur));
  return runs;
}
