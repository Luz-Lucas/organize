import 'dart:math' as math;
import 'dart:ui' hide TextBox;

import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/core/notebook_core.dart';
import 'package:organizacional/notebook/ui/ink_painting.dart';
import 'package:organizacional/notebook/ui/live_stroke.dart';

List<InkPoint> wave(int n) => [
  for (var i = 0; i < n; i++)
    InkPoint(
      50 + i * 1.2,
      400 + 80 * math.sin(i / 25),
      0.3 + 0.6 * ((math.sin(i / 40) + 1) / 2),
    ),
];

void main() {
  test('a união dos pedaços cobre praticamente o mesmo contorno que o cálculo completo', () {
    final pts = wave(700);
    final live = LiveStrokeOutline();
    final grown = <InkPoint>[];
    List<Path> paths = const [];
    for (final p in pts) {
      grown.add(p);
      paths = live.pathsFor(grown, PenTool.fountain, 3);
    }
    final full = strokeOutlinePath(pts, PenTool.fountain, 3, complete: false).getBounds();
    var union = paths.first.getBounds();
    for (final p in paths.skip(1)) {
      union = union.expandToInclude(p.getBounds());
    }
    expect(union.left, closeTo(full.left, 2));
    expect(union.right, closeTo(full.right, 2));
    expect(union.top, closeTo(full.top, 2));
    expect(union.bottom, closeTo(full.bottom, 2));
    expect(paths.length, greaterThan(3), reason: 'segmentos antigos ficam fixos em pedaços');
  });

  test('cada evento recalcula só a cauda: o trabalho total cresce linearmente', () {
    final pts = wave(2000);
    final live = LiveStrokeOutline();
    final grown = <InkPoint>[];
    var worst = 0;
    for (final p in pts) {
      grown.add(p);
      final before = live.pointsOutlined;
      live.pathsFor(grown, PenTool.pen, 3);
      worst = math.max(worst, live.pointsOutlined - before);
    }
    // recalcular tudo a cada evento seria ~2.000.000 de pontos no total
    expect(live.pointsOutlined, lessThan(2000 * 75));
    expect(worst, lessThanOrEqualTo(LiveStrokeOutline.tailMax + LiveStrokeOutline.chunk + 1));
  });

  test('pedir de novo sem pontos novos não calcula nada', () {
    final live = LiveStrokeOutline();
    final pts = wave(120);
    live.pathsFor(pts, PenTool.pen, 3);
    final n = live.pointsOutlined;
    live.pathsFor(pts, PenTool.pen, 3);
    expect(live.pointsOutlined, n);
  });

  test('outro traço (lista nova) ou outra caneta recomeça do zero', () {
    final live = LiveStrokeOutline();
    live.pathsFor(wave(300), PenTool.pen, 3);
    final fresh = wave(10);
    final paths = live.pathsFor(fresh, PenTool.pen, 3);
    expect(paths, hasLength(1));
    final other = live.pathsFor(fresh, PenTool.highlighter, 12);
    expect(other, hasLength(1));
  });

  test('um ponto só vira um pingo visível', () {
    final live = LiveStrokeOutline();
    final paths = live.pathsFor(const [InkPoint(100, 100, 0.5)], PenTool.pen, 4);
    expect(paths.single.getBounds().width, greaterThan(1));
  });
}
