import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide TextBox;
import 'package:perfect_freehand/perfect_freehand.dart';

import '../core/notebook_core.dart';
import 'tool_settings.dart' show kEraserRadius;

// ---------------------------------------------------------------------------
// Contorno do traço (largura variável com a pressão) — perfect_freehand.
// ---------------------------------------------------------------------------

StrokeOptions strokeOptionsFor(PenTool tool, double width, {required bool complete}) {
  switch (tool) {
    case PenTool.fountain:
      return StrokeOptions(
        size: width,
        thinning: 0.65,
        smoothing: 0.55,
        streamline: 0.5,
        simulatePressure: false,
        isComplete: complete,
      );
    case PenTool.pen:
      return StrokeOptions(
        size: width,
        thinning: 0.2,
        smoothing: 0.5,
        streamline: 0.45,
        simulatePressure: false,
        isComplete: complete,
      );
    case PenTool.pencil:
      return StrokeOptions(
        size: width,
        thinning: 0.45,
        smoothing: 0.4,
        streamline: 0.3,
        simulatePressure: false,
        isComplete: complete,
      );
    case PenTool.highlighter:
      return StrokeOptions(
        size: width,
        thinning: 0,
        smoothing: 0.5,
        streamline: 0.5,
        simulatePressure: false,
        isComplete: complete,
        start: StrokeEndOptions.start(cap: false),
        end: StrokeEndOptions.end(cap: false),
      );
  }
}

/// Caminho preenchível com o contorno do traço.
Path strokeOutlinePath(
  List<InkPoint> pts,
  PenTool tool,
  double width, {
  bool complete = true,
}) {
  if (pts.isEmpty) return Path();
  final radius = math.max(width / 2, 0.6);
  List<Offset> outline = const [];
  if (pts.length > 1) {
    outline = getStroke(
      [for (final p in pts) PointVector(p.x, p.y, p.p)],
      options: strokeOptionsFor(tool, width, complete: complete),
    );
  }
  if (outline.length < 3) {
    // Pingo (um ponto) ou traço sem comprimento: círculo na pressão média.
    final p = pts.first;
    final r = radius * (0.5 + 0.5 * p.p.clamp(0.0, 1.0)) * 1.0;
    return Path()..addOval(Rect.fromCircle(center: p.offset, radius: math.max(r, 0.6)));
  }
  final path = Path();
  Offset mid(Offset a, Offset b) => Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
  final n = outline.length;
  final m0 = mid(outline[0], outline[1]);
  path.moveTo(m0.dx, m0.dy);
  for (var i = 1; i <= n; i++) {
    final c = outline[i % n];
    final e = mid(c, outline[(i + 1) % n]);
    path.quadraticBezierTo(c.dx, c.dy, e.dx, e.dy);
  }
  path.close();
  return path;
}

Paint strokePaint(int argb) => Paint()
  ..color = Color(argb)
  ..style = PaintingStyle.fill
  ..isAntiAlias = true;

// ---------------------------------------------------------------------------
// Cache dos traços prontos (um ui.Picture por página).
// ---------------------------------------------------------------------------

/// Guarda o `ui.Picture` com tudo que já está pronto na página e os contornos
/// de cada traço (traços são imutáveis por id, então o contorno nunca muda).
/// O Picture só é regravado quando o `PageDoc` (ou o conjunto escondido, ou as
/// imagens carregadas) muda — desenhar um traço novo só calcula o contorno dele.
class PageInkCache {
  final Map<String, Path> _paths = {};
  ui.Picture? _picture;
  PageDoc? _doc;
  Set<String>? _hidden;
  int _epoch = -1;

  /// Quantas vezes o Picture foi regravado (diagnóstico/testes).
  int rebuilds = 0;

  /// Quantos contornos foram calculados (diagnóstico/testes).
  int outlinesComputed = 0;

  Path pathFor(Stroke s) => _paths.putIfAbsent(s.id, () {
    outlinesComputed++;
    return strokeOutlinePath(s.points, s.tool, s.width);
  });

  ui.Picture pictureFor(
    PageDoc doc,
    Set<String> hidden,
    int epoch,
    Map<String, ui.Image> images,
  ) {
    final cached = _picture;
    if (cached != null &&
        identical(_doc, doc) &&
        identical(_hidden, hidden) &&
        _epoch == epoch) {
      return cached;
    }
    cached?.dispose();
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec, const Rect.fromLTWH(0, 0, pageWidth, pageHeight));
    paintDoc(canvas, doc, hidden: hidden, images: images, pathFor: pathFor);
    _picture = rec.endRecording();
    _doc = doc;
    _hidden = hidden;
    _epoch = epoch;
    rebuilds++;
    // Poda contornos de traços que já não existem.
    if (_paths.length > doc.strokes.length + 64) {
      final keep = {for (final s in doc.strokes) s.id};
      _paths.removeWhere((id, _) => !keep.contains(id));
    }
    return _picture!;
  }

  void dispose() {
    _picture?.dispose();
    _picture = null;
  }
}

/// Desenha imagens, marca-textos, demais traços e textos de [doc].
void paintDoc(
  Canvas canvas,
  PageDoc doc, {
  Set<String> hidden = const {},
  Map<String, ui.Image> images = const {},
  Path Function(Stroke)? pathFor,
}) {
  final outline = pathFor ?? (s) => strokeOutlinePath(s.points, s.tool, s.width);
  for (final im in doc.images) {
    if (hidden.contains(im.id)) continue;
    final dst = Rect.fromLTWH(im.x, im.y, im.w, im.h);
    final img = images[im.path];
    if (img != null) {
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        dst,
        Paint()..filterQuality = FilterQuality.medium,
      );
    } else {
      canvas.drawRect(dst, Paint()..color = const Color(0x22808080));
      canvas.drawRect(
        dst,
        Paint()
          ..color = const Color(0x55808080)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }
  for (final pass in const [true, false]) {
    for (final s in doc.strokes) {
      if ((s.tool == PenTool.highlighter) != pass) continue;
      if (hidden.contains(s.id)) continue;
      canvas.drawPath(outline(s), strokePaint(s.argb));
    }
  }
  for (final t in doc.texts) {
    if (hidden.contains(t.id)) continue;
    paintText(canvas, t);
  }
}

void paintText(Canvas canvas, TextBox t) {
  final tp = TextPainter(
    text: TextSpan(
      text: t.text,
      style: TextStyle(fontSize: t.size, color: Color(t.argb), height: 1.25),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: t.w <= 0 ? 1 : t.w);
  tp.paint(canvas, Offset(t.x, t.y));
  tp.dispose();
}

/// Altura real do texto (para o retângulo de seleção/toque).
double measureTextHeight(TextBox t) {
  final tp = TextPainter(
    text: TextSpan(text: t.text, style: TextStyle(fontSize: t.size, height: 1.25)),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: t.w <= 0 ? 1 : t.w);
  final h = tp.height;
  tp.dispose();
  return h;
}

// ---------------------------------------------------------------------------
// Painters
// ---------------------------------------------------------------------------

/// Fundo da página (papel + pautas/grade/pontos).
class PageBackgroundPainter extends CustomPainter {
  PageBackgroundPainter({
    required this.background,
    required this.paper,
    required this.line,
  });

  final PageBackground background;
  final Color paper;
  final Color line;

  static const double spacing = 40;
  static const double top = 120;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = paper);
    final p = Paint()
      ..color = line.withValues(alpha: 0.55)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    switch (background) {
      case PageBackground.blank:
        break;
      case PageBackground.lined:
        for (var y = top; y < size.height - 30; y += spacing) {
          canvas.drawLine(Offset(40, y), Offset(size.width - 40, y), p);
        }
      case PageBackground.grid:
        for (var y = spacing; y < size.height; y += spacing) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
        }
        for (var x = spacing; x < size.width; x += spacing) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
        }
      case PageBackground.dots:
        final dot = Paint()..color = line.withValues(alpha: 0.8);
        for (var y = spacing; y < size.height; y += spacing) {
          for (var x = spacing; x < size.width; x += spacing) {
            canvas.drawCircle(Offset(x, y), 1.8, dot);
          }
        }
    }
  }

  @override
  bool shouldRepaint(PageBackgroundPainter old) =>
      old.background != background || old.paper != paper || old.line != line;
}

/// Traços prontos: reproduz o Picture em cache.
class CommittedInkPainter extends CustomPainter {
  CommittedInkPainter({
    required this.cache,
    required this.doc,
    required this.hidden,
    required this.epoch,
    required this.images,
  });

  final PageInkCache cache;
  final PageDoc doc;
  final Set<String> hidden;
  final int epoch;
  final Map<String, ui.Image> images;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPicture(cache.pictureFor(doc, hidden, epoch, images));
  }

  @override
  bool shouldRepaint(CommittedInkPainter old) =>
      !identical(old.doc, doc) ||
      !identical(old.hidden, hidden) ||
      old.epoch != epoch ||
      !identical(old.cache, cache);
}

/// Estado da camada ao vivo (traço em andamento, borracha, laço, prévia da
/// seleção). Notifica só essa camada: o resto da página não repinta.
class LiveInk extends ChangeNotifier {
  List<InkPoint> points = const [];
  PenTool tool = PenTool.fountain;
  int argb = 0xFFFFFFFF;
  double width = 3;

  Offset? eraserPos;
  double eraserRadius = kEraserRadius;

  List<Offset> lasso = const [];

  /// Itens selecionados que estão sendo movidos/redimensionados.
  PageDoc? movingDoc;
  Matrix2x3 moveMatrix = Matrix2x3.identity;

  void changed() => notifyListeners();

  void clear() {
    points = const [];
    eraserPos = null;
    lasso = const [];
    movingDoc = null;
    moveMatrix = Matrix2x3.identity;
    notifyListeners();
  }
}

Float64List matrix4Of(Matrix2x3 m) => Float64List.fromList([
  m.a, m.b, 0, 0, //
  m.c, m.d, 0, 0,
  0, 0, 1, 0,
  m.tx, m.ty, 0, 1,
]);

class LiveInkPainter extends CustomPainter {
  LiveInkPainter({
    required this.live,
    required this.selectionRect,
    required this.accent,
    required this.pixelRatio,
    required this.images,
  }) : super(repaint: live);

  final LiveInk live;
  final Rect? selectionRect;
  final Color accent;
  final double pixelRatio;
  final Map<String, ui.Image> images;

  /// Raio (em unidades de página) correspondente a [dp] pixels lógicos.
  double _units(Canvas canvas, double dp) {
    final scale = canvas.getTransform()[0].abs() / pixelRatio;
    return scale <= 0 ? dp : dp / scale;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final m = live.moveMatrix;
    // Prévia da seleção em movimento.
    final moving = live.movingDoc;
    if (moving != null) {
      canvas.save();
      canvas.transform(matrix4Of(m));
      paintDoc(canvas, moving, images: images);
      canvas.restore();
    }
    // Traço em andamento.
    if (live.points.isNotEmpty) {
      final path = strokeOutlinePath(live.points, live.tool, live.width, complete: false);
      canvas.drawPath(path, strokePaint(live.argb));
    }
    // Retângulo e alças da seleção.
    final sel = selectionRect;
    if (sel != null) {
      final a = m.apply(sel.topLeft), b = m.apply(sel.bottomRight);
      final r = Rect.fromPoints(a, b);
      final u = _units(canvas, 1);
      final box = Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * u;
      canvas.drawRect(r, box);
      final hr = 7 * u;
      for (final c in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
        canvas.drawCircle(c, hr, Paint()..color = accent);
        canvas.drawCircle(c, hr * 0.5, Paint()..color = Colors.white);
      }
    }
    // Laço.
    if (live.lasso.length > 1) {
      final u = _units(canvas, 1);
      final path = Path()..moveTo(live.lasso.first.dx, live.lasso.first.dy);
      for (final p in live.lasso.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6 * u
          ..strokeCap = StrokeCap.round,
      );
    }
    // Borracha.
    final e = live.eraserPos;
    if (e != null) {
      final u = _units(canvas, 1);
      canvas.drawCircle(e, live.eraserRadius, Paint()..color = const Color(0x22FFFFFF));
      canvas.drawCircle(
        e,
        live.eraserRadius,
        Paint()
          ..color = const Color(0xCCFFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2 * u,
      );
    }
  }

  @override
  bool shouldRepaint(LiveInkPainter old) =>
      old.selectionRect != selectionRect ||
      old.accent != accent ||
      !identical(old.images, images);
}
