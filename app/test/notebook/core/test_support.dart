import 'dart:math';
import 'dart:ui' hide TextBox;

import 'package:organizacional/notebook/core/notebook_core.dart';

/// Traço com pontos dados (pressão constante).
Stroke mkStroke(
  String id,
  List<Offset> pts, {
  PenTool tool = PenTool.pen,
  int argb = 0xFF000000,
  double width = 3,
  double p = 0.5,
}) => Stroke(
  id: id,
  tool: tool,
  argb: argb,
  width: width,
  points: [for (final o in pts) InkPoint(o.dx, o.dy, p)],
);

/// Segmento reto de [a] a [b] com [n] pontos igualmente espaçados.
Stroke lineStroke(
  String id,
  Offset a,
  Offset b, {
  int n = 11,
  double width = 3,
  PenTool tool = PenTool.pen,
}) {
  assert(n >= 2);
  return mkStroke(
    id,
    [for (var i = 0; i < n; i++) Offset.lerp(a, b, i / (n - 1))!],
    width: width,
    tool: tool,
  );
}

/// Traço suave (curva senoidal) com [n] pontos, pressão variando.
Stroke curveStroke(String id, Random r, {int n = 100}) {
  final x0 = r.nextDouble() * 800;
  final y0 = r.nextDouble() * 1200;
  final amp = 10 + r.nextDouble() * 40;
  final freq = 0.05 + r.nextDouble() * 0.1;
  return Stroke(
    id: id,
    tool: PenTool.values[r.nextInt(PenTool.values.length)],
    argb: 0xFF000000 | r.nextInt(0xFFFFFF),
    width: 1 + r.nextInt(8).toDouble(),
    points: [
      for (var i = 0; i < n; i++)
        InkPoint(
          x0 + i * 2.0,
          y0 + sin(i * freq) * amp,
          0.2 + 0.6 * (0.5 + 0.5 * sin(i * 0.1)),
        ),
    ],
  );
}

TextBox mkText(
  String id, {
  double x = 10,
  double y = 20,
  String text = 'olá',
}) =>
    TextBox(id: id, x: x, y: y, w: 200, text: text, size: 18, argb: 0xFF112233);

ImageBox mkImage(String id, {double x = 50, double y = 60}) =>
    ImageBox(id: id, x: x, y: y, w: 300, h: 200, path: 'u/n/$id.png');

/// Mesmo conteúdo de página, ignorando a ordem das listas.
bool sameContent(PageDoc a, PageDoc b) {
  bool sameSet<T>(List<T> x, List<T> y, String Function(T) id) {
    final mx = {for (final i in x) id(i): i};
    final my = {for (final i in y) id(i): i};
    if (mx.length != my.length) return false;
    for (final k in mx.keys) {
      if (my[k] != mx[k]) return false;
    }
    return true;
  }

  return sameSet<Stroke>(a.strokes, b.strokes, (s) => s.id) &&
      sameSet<TextBox>(a.texts, b.texts, (s) => s.id) &&
      sameSet<ImageBox>(a.images, b.images, (s) => s.id) &&
      a.deleted.length == b.deleted.length &&
      a.deleted.containsAll(b.deleted);
}

/// Traço no estilo de letra à mão: direção que varia devagar, passos de
/// ~1–3 unidades (caneta a 240 Hz) e pressão que muda aos poucos.
Stroke handwritingStroke(String id, Random r, {int n = 100}) {
  var x = 50 + r.nextDouble() * 900;
  var y = 50 + r.nextDouble() * 1300;
  var heading = r.nextDouble() * 2 * pi;
  var speed = 1 + r.nextDouble() * 2;
  var press = 0.3 + r.nextDouble() * 0.4;
  final pts = <InkPoint>[];
  for (var i = 0; i < n; i++) {
    pts.add(InkPoint(x, y, press));
    heading += (r.nextDouble() - 0.5) * 0.5;
    speed = (speed + (r.nextDouble() - 0.5) * 0.4).clamp(0.5, 4.0);
    press = (press + (r.nextDouble() - 0.5) * 0.04).clamp(0.05, 1.0);
    x = (x + cos(heading) * speed).clamp(0.0, pageWidth);
    y = (y + sin(heading) * speed).clamp(0.0, pageHeight);
  }
  return Stroke(
    id: id,
    tool: PenTool.pen,
    argb: 0xFF000000,
    width: 3,
    points: pts,
  );
}

/// Pior caso para compressão: pontos totalmente aleatórios.
Stroke noiseStroke(String id, Random r, {int n = 100}) => Stroke(
  id: id,
  tool: PenTool.pen,
  argb: 0xFF000000,
  width: 3,
  points: [
    for (var i = 0; i < n; i++)
      InkPoint(
        r.nextDouble() * pageWidth,
        r.nextDouble() * pageHeight,
        r.nextDouble(),
      ),
  ],
);
