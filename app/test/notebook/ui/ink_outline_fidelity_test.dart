import 'dart:math' as math;
import 'dart:ui' hide TextBox;

import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/core/notebook_core.dart';
import 'package:organizacional/notebook/ui/ink_painting.dart';
import 'package:organizacional/notebook/ui/live_stroke.dart';

/// Distância de [p] ao **preenchimento** do caminho (0 se estiver dentro).
double distanceToFill(Iterable<Path> paths, Offset p) {
  var best = double.infinity;
  for (final path in paths) {
    if (path.contains(p)) return 0;
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d <= m.length; d += 0.25) {
        best = math.min(best, (m.getTangentForOffset(d)!.position - p).distance);
      }
    }
  }
  return best;
}

List<Offset> arc(Offset c, double r, double a0, double a1, [int n = 60]) => [
  for (var i = 0; i <= n; i++) c + Offset.fromDirection(a0 + (a1 - a0) * i / n, r),
];

/// Reamostra a poligonal a cada [step] unidades (a caneta que a tela entrega
/// espaçada quando o input é agrupado) com a pressão [pressure] (0..1 ao longo
/// do traço).
List<InkPoint> sampled(List<Offset> poly, double step, double Function(double t) pressure) {
  final lens = <double>[0];
  for (var i = 1; i < poly.length; i++) {
    lens.add(lens.last + (poly[i] - poly[i - 1]).distance);
  }
  final total = lens.last;
  final out = <InkPoint>[];
  var seg = 1;
  for (var d = 0.0; d < total; d += step) {
    while (seg < poly.length - 1 && d > lens[seg]) {
      seg++;
    }
    final l = lens[seg] - lens[seg - 1];
    final o = Offset.lerp(poly[seg - 1], poly[seg], l == 0 ? 0 : (d - lens[seg - 1]) / l)!;
    out.add(InkPoint(o.dx, o.dy, pressure(d / total)));
  }
  out.add(InkPoint(poly.last.dx, poly.last.dy, pressure(1)));
  return out;
}

/// Pressão baixa ao encostar e ao levantar (como a S Pen), alta no meio.
double tipsLow(double t) => (t < 0.12 || t > 0.88) ? 0.05 : 0.7;

// Letras com ~30 unidades de altura (escrita pequena numa página de 1000).
final List<Offset> letterU = [
  const Offset(100, 100),
  const Offset(100, 125),
  ...arc(const Offset(112, 125), 12, math.pi, 0, 30),
  const Offset(124, 100),
];
final List<Offset> letterC = arc(const Offset(112, 112), 14, -0.6, -2 * math.pi + 0.6, 80);
final List<Offset> letterS = [
  ...arc(const Offset(112, 100), 10, -0.3, -math.pi * 1.5, 40),
  ...arc(const Offset(112, 120), 10, -math.pi * 0.5, math.pi * 0.8, 40),
];

void main() {
  const writing = [PenTool.fountain, PenTool.pen, PenTool.pencil];

  group('as pontas do traço', () {
    for (final tool in [...writing, PenTool.highlighter]) {
      for (final w in [1.5, 3.0, 5.0]) {
        for (final entry in {'U': letterU, 'C': letterC}.entries) {
          test('${entry.key} com pressão baixa nas pontas ($tool, largura $w): o contorno cobre o 1º e o último ponto', () {
            final pts = sampled(entry.value, 6, tipsLow);
            final path = strokeOutlinePath(pts, tool, w);
            expect(distanceToFill([path], pts.first.offset), lessThan(1));
            expect(distanceToFill([path], pts.last.offset), lessThan(1));
            // e de verdade: o ponto está dentro da tinta, não só perto
            expect(path.contains(pts.first.offset), isTrue, reason: 'primeiro ponto');
            expect(path.contains(pts.last.offset), isTrue, reason: 'último ponto');
          });
        }
      }
    }

    test('pressão baixa não deixa a ponta quase invisível (piso de pressão)', () {
      List<InkPoint> line(double p) => [for (var i = 0; i < 20; i++) InkPoint(10.0 * i, 0, p)];
      for (final tool in [PenTool.fountain, PenTool.pencil]) {
        final h = strokeOutlinePath(line(0.05), tool, 6).getBounds().height;
        expect(h, greaterThan(6 * 0.6), reason: '$tool: a linha com pressão 0,05 ainda tem ao menos 60% da largura');
      }
    });
  });

  group('curvas rápidas (amostras espaçadas)', () {
    for (final tool in writing) {
      for (final w in [3.0, 5.0]) {
        for (final entry in {'S': letterS, 'U': letterU, 'C': letterC}.entries) {
          test('${entry.key} rápido ($tool, largura $w): o contorno passa perto de todas as amostras', () {
            final pts = sampled(entry.value, 10, (t) => 0.2 + 0.6 * math.sin(t * math.pi));
            final path = strokeOutlinePath(pts, tool, w);
            var worst = 0.0;
            for (final p in pts) {
              worst = math.max(worst, distanceToFill([path], p.offset));
            }
            expect(worst, lessThan(w / 2), reason: 'desvio máximo do contorno às amostras');
          });
        }
      }
    }
  });

  group('prévia ao vivo', () {
    test('usa os mesmos parâmetros: ao soltar, o traço final não "pula"', () {
      for (final tool in writing) {
        final pts = sampled(letterS, 10, (t) => 0.2 + 0.6 * math.sin(t * math.pi));
        final live = LiveStrokeOutline();
        final grown = <InkPoint>[];
        List<Path> paths = const [];
        for (final p in pts) {
          grown.add(p);
          paths = live.pathsFor(grown, tool, 3);
        }
        final full = strokeOutlinePath(pts, tool, 3);
        // toda amostra está na tinta da prévia e na tinta final com a mesma folga
        for (final p in pts) {
          expect(distanceToFill(paths, p.offset), lessThan(3 / 2 + 0.01), reason: '$tool prévia');
          expect(distanceToFill([full], p.offset), lessThan(3 / 2 + 0.01), reason: '$tool final');
        }
        // e a prévia chega perto do último ponto (a cauda não fica para trás)
        expect(distanceToFill(paths, pts.last.offset), lessThan(1), reason: '$tool: cauda da prévia');
      }
    });
  });
}
