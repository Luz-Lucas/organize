import 'dart:math' as math;
import 'dart:ui' hide TextBox;

import 'ids.dart';
import 'ink_math.dart';
import 'ink_types.dart';
import 'matrix2x3.dart';
import 'page_doc.dart';

/// Resultado de uma edição que cria itens novos: o documento e o mapa
/// `id antigo -> id novo` (para a UI manter a seleção).
class EditResult {
  const EditResult(this.doc, this.idMap);
  final PageDoc doc;
  final Map<String, String> idMap;
}

// ---------------------------------------------------------------------------
// Borracha por traço

double _strokeDistToSegment(Stroke s, Offset e0, Offset e1) {
  final pts = s.points;
  if (pts.length == 1) return distPointSegment(pts[0].offset, e0, e1);
  var best = double.infinity;
  for (var i = 0; i + 1 < pts.length; i++) {
    final d = distSegmentSegment(pts[i].offset, pts[i + 1].offset, e0, e1);
    if (d < best) {
      best = d;
      if (best == 0) break;
    }
  }
  return best;
}

/// Ids dos traços tocados por uma borracha circular de [radius] em [center]
/// (conta a meia espessura do traço), na ordem do documento. Com [from], a
/// borracha varre o segmento `from → center` (evita "pular" traços quando o
/// dedo/caneta anda rápido entre duas amostras).
List<String> hitStrokes(
  PageDoc doc,
  Offset center,
  double radius, {
  Offset? from,
}) {
  final e0 = from ?? center;
  final zone = Rect.fromPoints(e0, center).inflate(radius + 1);
  final hits = <String>[];
  for (final s in doc.strokes) {
    if (!s.bounds.overlaps(zone)) continue;
    if (_strokeDistToSegment(s, e0, center) <= radius + s.width / 2) {
      hits.add(s.id);
    }
  }
  return hits;
}

/// Como [hitStrokes], mas inclui textos e imagens (pelo retângulo): traços,
/// depois textos, depois imagens.
List<String> hitItems(
  PageDoc doc,
  Offset center,
  double radius, {
  Offset? from,
}) {
  final hits = hitStrokes(doc, center, radius, from: from);
  final e0 = from ?? center;
  bool near(Rect r) {
    if (e0 == center) return distPointRect(center, r) <= radius;
    // varredura: amostra o segmento (passo <= raio)
    final len = (center - e0).distance;
    final steps = math.max(1, (len / math.max(radius, 1)).ceil());
    for (var i = 0; i <= steps; i++) {
      if (distPointRect(Offset.lerp(e0, center, i / steps)!, r) <= radius) {
        return true;
      }
    }
    return false;
  }

  for (final t in doc.texts) {
    if (near(t.bounds)) hits.add(t.id);
  }
  for (final i in doc.images) {
    if (near(i.bounds)) hits.add(i.id);
  }
  return hits;
}

// ---------------------------------------------------------------------------
// Borracha parcial

const double _eps = 1e-9;

InkPoint _lerpPoint(InkPoint a, InkPoint b, double t) {
  if (t <= _eps) return a;
  if (t >= 1 - _eps) return b;
  return InkPoint(
    a.x + (b.x - a.x) * t,
    a.y + (b.y - a.y) * t,
    a.p + (b.p - a.p) * t,
  );
}

/// `null` = intocado; lista vazia = apagado inteiro; senão os pedaços.
List<List<InkPoint>>? _cutStroke(
  Stroke s,
  List<(Offset, Offset)> eraser,
  double eff,
) {
  final pts = s.points;
  if (pts.length == 1) {
    final o = pts[0].offset;
    for (final e in eraser) {
      if (distPointSegment(o, e.$1, e.$2) <= eff) return const [];
    }
    return null;
  }
  final runs = <List<InkPoint>>[];
  List<InkPoint>? run;
  var open = false; // `run` termina exatamente no fim do segmento anterior
  var touched = false;

  void flush() {
    if (run != null) runs.add(run!);
    run = null;
    open = false;
  }

  for (var i = 0; i + 1 < pts.length; i++) {
    final p0 = pts[i], p1 = pts[i + 1];
    final a = p0.offset, b = p1.offset;
    final cuts = <(double, double)>[];
    for (final e in eraser) {
      final iv = segmentCapsuleInterval(a, b, e.$1, e.$2, eff);
      if (iv != null) cuts.add(iv);
    }
    if (cuts.isEmpty) {
      (run ??= [p0]).add(p1);
      open = true;
      continue;
    }
    touched = true;
    cuts.sort((x, y) => x.$1.compareTo(y.$1));
    final kept = <(double, double)>[];
    var cur = 0.0;
    for (final c in cuts) {
      if (c.$1 - cur > _eps) kept.add((cur, c.$1));
      cur = math.max(cur, c.$2);
    }
    if (1 - cur > _eps) kept.add((cur, 1.0));

    if (kept.isEmpty) {
      flush();
      continue;
    }
    for (final k in kept) {
      final continues = k.$1 <= _eps && open;
      if (!continues) {
        flush();
        run = [_lerpPoint(p0, p1, k.$1)];
      }
      run!.add(_lerpPoint(p0, p1, k.$2));
      open = k.$2 >= 1 - _eps;
      if (!open) flush();
    }
  }
  flush();
  return touched ? runs : null;
}

List<InkPoint>? _finishPiece(List<InkPoint> raw, double minLength) {
  final out = <InkPoint>[];
  for (final p in raw) {
    final q = p.quantized();
    if (out.isNotEmpty && out.last.x == q.x && out.last.y == q.y) continue;
    out.add(q);
  }
  if (out.length < 2) return null;
  var len = 0.0;
  for (var i = 0; i + 1 < out.length; i++) {
    len += (out[i + 1].offset - out[i].offset).distance;
  }
  return len < minLength ? null : out;
}

/// Borracha parcial: apaga a parte dos traços que fica a até [radius] (mais a
/// meia espessura) do [path] (polilinha varrida pela borracha) e **divide** o
/// traço em pedaços novos (ids de [newId], um por pedaço; o original vira
/// tombstone). Os cortes caem exatamente na borda da borracha (interpolando
/// x, y e pressão), mesmo em segmentos longos.
///
/// Nunca cria pedaço de um ponto só: pedaços que ficariam com menos de dois
/// pontos distintos ou com comprimento menor que [minPieceLength] são
/// descartados. Traços de um ponto (pingos) são apagados inteiros ou nada.
/// Traços intocados mantêm id e instância. Os pedaços vão para o topo da
/// pilha. Sem contato, devolve o próprio [doc].
PageDoc erasePartial(
  PageDoc doc,
  List<Offset> path,
  double radius,
  String Function() newId, {
  double minPieceLength = 0.5,
}) {
  if (path.isEmpty || doc.strokes.isEmpty) return doc;
  final eraser = path.length == 1
      ? [(path[0], path[0])]
      : [for (var i = 0; i + 1 < path.length; i++) (path[i], path[i + 1])];
  var zone = Rect.fromPoints(path[0], path[0]);
  for (final p in path) {
    zone = zone.expandToInclude(Rect.fromPoints(p, p));
  }
  zone = zone.inflate(radius + 1);

  final removed = <String>{};
  final created = <Stroke>[];
  for (final s in doc.strokes) {
    if (!s.bounds.overlaps(zone)) continue;
    final runs = _cutStroke(s, eraser, radius + s.width / 2);
    if (runs == null) continue;
    removed.add(s.id);
    for (final r in runs) {
      final pts = _finishPiece(r, minPieceLength);
      if (pts != null) created.add(s.copyWith(id: newId(), points: pts));
    }
  }
  if (removed.isEmpty) return doc;
  return doc.without(removed).withStrokes(created);
}

// ---------------------------------------------------------------------------
// Laço

/// Ids (traços, textos e imagens) com pelo menos 50 % dos pontos dentro do
/// [polygon] (fechado implicitamente). Textos e imagens: grade 3×3 de amostras
/// sobre o retângulo.
Set<String> lassoSelect(PageDoc doc, List<Offset> polygon) {
  if (polygon.length < 3) return <String>{};
  var box = Rect.fromPoints(polygon[0], polygon[0]);
  for (final p in polygon) {
    box = box.expandToInclude(Rect.fromPoints(p, p));
  }
  final picked = <String>{};
  for (final s in doc.strokes) {
    if (!s.bounds.overlaps(box) && !box.contains(s.points.first.offset)) {
      continue;
    }
    final n = s.points.length;
    var inside = 0, outside = 0;
    for (final p in s.points) {
      final o = p.offset;
      if (box.contains(o) && pointInPolygon(o, polygon)) {
        inside++;
      } else {
        outside++;
        if (outside * 2 > n) break;
      }
    }
    if (inside * 2 >= n) picked.add(s.id);
  }
  bool boxSelected(Rect r) {
    var inside = 0;
    for (final fx in const [1 / 6, 3 / 6, 5 / 6]) {
      for (final fy in const [1 / 6, 3 / 6, 5 / 6]) {
        final o = Offset(r.left + r.width * fx, r.top + r.height * fy);
        if (pointInPolygon(o, polygon)) inside++;
      }
    }
    return inside * 2 >= 9;
  }

  for (final t in doc.texts) {
    if (boxSelected(t.bounds)) picked.add(t.id);
  }
  for (final i in doc.images) {
    if (boxSelected(i.bounds)) picked.add(i.id);
  }
  return picked;
}

/// Retângulo que envolve os itens [ids] (ou `null` se nenhum existir).
Rect? itemsBounds(PageDoc doc, Set<String> ids) {
  Rect? r;
  void add(Rect b) => r = r == null ? b : r!.expandToInclude(b);
  for (final s in doc.strokes) {
    if (ids.contains(s.id)) add(s.bounds);
  }
  for (final t in doc.texts) {
    if (ids.contains(t.id)) add(t.bounds);
  }
  for (final i in doc.images) {
    if (ids.contains(i.id)) add(i.bounds);
  }
  return r;
}

// ---------------------------------------------------------------------------
// Transformar / recolorir / copiar e colar (sempre apagar + criar com id novo)

({
  List<Stroke> strokes,
  List<TextBox> texts,
  List<ImageBox> images,
  Map<String, String> idMap,
})
_mapItems(PageDoc src, Set<String>? ids, Matrix2x3 m, String Function() newId) {
  final idMap = <String, String>{};
  bool want(String id) => ids == null || ids.contains(id);
  final us = m.uniformScale;
  final strokes = <Stroke>[
    for (final s in src.strokes)
      if (want(s.id))
        s.copyWith(
          id: idMap[s.id] = newId(),
          width: s.width * us,
          points: [
            for (final p in s.points)
              () {
                final o = m.apply(p.offset);
                return InkPoint(o.dx, o.dy, p.p);
              }(),
          ],
        ),
  ];
  final texts = <TextBox>[
    for (final t in src.texts)
      if (want(t.id))
        () {
          final o = m.apply(Offset(t.x, t.y));
          return t.copyWith(
            id: idMap[t.id] = newId(),
            x: o.dx,
            y: o.dy,
            w: t.w * m.xScale,
            size: t.size * math.sqrt(m.xScale * m.yScale),
          );
        }(),
  ];
  final images = <ImageBox>[
    for (final i in src.images)
      if (want(i.id))
        () {
          final o = m.apply(Offset(i.x, i.y));
          return i.copyWith(
            id: idMap[i.id] = newId(),
            x: o.dx,
            y: o.dy,
            w: i.w * m.xScale,
            h: i.h * m.yScale,
          );
        }(),
  ];
  return (strokes: strokes, texts: texts, images: images, idMap: idMap);
}

PageDoc _addAll(
  PageDoc doc,
  List<Stroke> s,
  List<TextBox> t,
  List<ImageBox> i,
) {
  var d = doc.withStrokes(s);
  for (final x in t) {
    d = d.withText(x);
  }
  for (final x in i) {
    d = d.withImage(x);
  }
  return d;
}

/// Aplica [m] aos itens [ids] (apaga os originais e cria cópias transformadas
/// com ids novos, vindos de [newId], por padrão [newInkId]). Posição de textos
/// e imagens segue [m]; a caixa só escala (não gira). Ids que não existem são
/// ignorados; sem nada a mudar devolve o próprio [doc].
PageDoc transformItems(
  PageDoc doc,
  Set<String> ids,
  Matrix2x3 m, {
  String Function()? newId,
}) => transformItemsMapped(doc, ids, m, newId: newId).doc;

/// Como [transformItems], devolvendo também o mapa `id antigo -> id novo`.
EditResult transformItemsMapped(
  PageDoc doc,
  Set<String> ids,
  Matrix2x3 m, {
  String Function()? newId,
}) {
  if (ids.isEmpty) return EditResult(doc, const {});
  final r = _mapItems(doc, ids, m, newId ?? newInkId);
  if (r.idMap.isEmpty) return EditResult(doc, const {});
  final out = _addAll(doc.without(r.idMap.keys), r.strokes, r.texts, r.images);
  return EditResult(out, Map.unmodifiable(r.idMap));
}

/// Troca a cor RGB dos traços e textos em [ids] por [argb], mantendo o alfa de
/// cada item (o marca-texto continua translúcido). Imagens são ignoradas;
/// itens que já têm a cor ficam como estão. Cria itens novos (ids de [newId]).
PageDoc recolor(
  PageDoc doc,
  Set<String> ids,
  int argb, {
  String Function()? newId,
}) => recolorMapped(doc, ids, argb, newId: newId).doc;

EditResult recolorMapped(
  PageDoc doc,
  Set<String> ids,
  int argb, {
  String Function()? newId,
}) {
  final gen = newId ?? newInkId;
  int tint(int old) => (old & 0xFF000000) | (argb & 0x00FFFFFF);
  final idMap = <String, String>{};
  final strokes = <Stroke>[
    for (final s in doc.strokes)
      if (ids.contains(s.id) && tint(s.argb) != s.argb)
        s.copyWith(id: idMap[s.id] = gen(), argb: tint(s.argb)),
  ];
  final texts = <TextBox>[
    for (final t in doc.texts)
      if (ids.contains(t.id) && tint(t.argb) != t.argb)
        t.copyWith(id: idMap[t.id] = gen(), argb: tint(t.argb)),
  ];
  if (idMap.isEmpty) return EditResult(doc, const {});
  return EditResult(
    _addAll(doc.without(idMap.keys), strokes, texts, const []),
    Map.unmodifiable(idMap),
  );
}

/// "Copiar": um documento só com os itens [ids] (sem tombstones).
PageDoc extractItems(PageDoc doc, Set<String> ids) => PageDoc(
  strokes: doc.strokes.where((s) => ids.contains(s.id)),
  texts: doc.texts.where((s) => ids.contains(s.id)),
  images: doc.images.where((s) => ids.contains(s.id)),
);

/// "Colar": acrescenta a [target] cópias dos itens de [clip], com ids novos e
/// deslocadas de ([dx], [dy]). Funciona entre páginas.
PageDoc pasteDoc(
  PageDoc target,
  PageDoc clip, {
  double dx = 0,
  double dy = 0,
  String Function()? newId,
}) => pasteDocMapped(target, clip, dx: dx, dy: dy, newId: newId).doc;

EditResult pasteDocMapped(
  PageDoc target,
  PageDoc clip, {
  double dx = 0,
  double dy = 0,
  String Function()? newId,
}) {
  final r = _mapItems(
    clip,
    null,
    Matrix2x3.translation(dx, dy),
    newId ?? newInkId,
  );
  return EditResult(
    _addAll(target, r.strokes, r.texts, r.images),
    Map.unmodifiable(r.idMap),
  );
}
