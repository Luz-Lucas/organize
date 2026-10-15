import 'dart:math' as math;
import 'dart:ui' hide TextBox;

import '../core/notebook_core.dart';

/// Troca cada traço de [transforms] por uma cópia transformada (id novo de
/// [newId], espessura × escala uniforme) e deixa tombstone do antigo, seguindo
/// o padrão do núcleo ("editar = apagar + criar"). Os ids novos saem na ordem
/// dos traços no documento, então o resultado é determinístico.
///
/// Traços cuja transformação não move nenhum ponto (menos de 0,05 unidade, a
/// resolução da gravação) e não muda a espessura ficam como estão, com o id
/// antigo. Se nada muda devolve o próprio [doc].
PageDoc remapStrokes(
  PageDoc doc,
  Map<String, Matrix2x3> transforms,
  String Function() newId,
) {
  if (transforms.isEmpty) return doc;
  final old = <String>{};
  final fresh = <Stroke>[];
  for (final s in doc.strokes) {
    final m = transforms[s.id];
    if (m == null) continue;
    final us = m.uniformScale;
    var moved = (s.width * us - s.width).abs() > 0.005;
    final pts = <InkPoint>[];
    for (final p in s.points) {
      final o = m.apply(p.offset);
      if (!moved && ((o.dx - p.x).abs() > 0.05 || (o.dy - p.y).abs() > 0.05)) moved = true;
      pts.add(InkPoint(o.dx, o.dy, p.p));
    }
    if (!moved) continue;
    old.add(s.id);
    fresh.add(s.copyWith(id: newId(), width: s.width * us, points: pts));
  }
  if (old.isEmpty) return doc;
  return doc.without(old).withStrokes(fresh);
}

/// Translação por [d] aplicada depois de [m].
Matrix2x3 thenShift(Matrix2x3 m, Offset d) =>
    Matrix2x3.translation(d.dx, d.dy) * m;

/// Caixa dos pontos de [s] depois de [m] (sem espessura).
Rect transformedPointBox(Stroke s, Matrix2x3 m) {
  var l = double.infinity, r = -double.infinity, t = double.infinity, b = -double.infinity;
  for (final p in s.points) {
    final o = m.apply(p.offset);
    l = math.min(l, o.dx);
    r = math.max(r, o.dx);
    t = math.min(t, o.dy);
    b = math.max(b, o.dy);
  }
  return Rect.fromLTRB(l, t, r, b);
}
