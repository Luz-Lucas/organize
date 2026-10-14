import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide TextBox;
import 'package:perfect_freehand/perfect_freehand.dart';

import '../core/notebook_core.dart';
import 'eraser_session.dart' show ErasePreview;
import 'live_stroke.dart';
import 'tool_settings.dart' show kEraserRadius;

// ---------------------------------------------------------------------------
// Contorno do traço (largura variável com a pressão) — perfect_freehand.
// ---------------------------------------------------------------------------

/// Parâmetros do perfect_freehand por caneta.
///
/// `streamline` e `smoothing` ficam baixos de propósito: a S Pen já entrega
/// pontos limpos e suavizar muito achata curvas rápidas (o S deformava, as
/// pontas do U e do C encurtavam). `streamline` ~0,2 deixa o traço colado nas
/// amostras (o ponto final é sempre o real) e `smoothing` ~0,4 só poupa pontos
/// do contorno. `thinning` menor deixa a pressão variar a largura sem afinar
/// demais; o resto é o [pressureWithFloor] em [strokeOutlinePath].
StrokeOptions strokeOptionsFor(PenTool tool, double width, {required bool complete}) {
  switch (tool) {
    case PenTool.fountain:
      return StrokeOptions(
        size: width,
        thinning: 0.45,
        smoothing: 0.4,
        streamline: 0.2,
        simulatePressure: false,
        isComplete: complete,
      );
    case PenTool.pen:
      return StrokeOptions(
        size: width,
        thinning: 0.2,
        smoothing: 0.4,
        streamline: 0.2,
        simulatePressure: false,
        isComplete: complete,
      );
    case PenTool.pencil:
      return StrokeOptions(
        size: width,
        thinning: 0.3,
        smoothing: 0.35,
        streamline: 0.15,
        simulatePressure: false,
        isComplete: complete,
      );
    case PenTool.highlighter:
      return StrokeOptions(
        size: width,
        thinning: 0,
        smoothing: 0.4,
        streamline: 0.2,
        simulatePressure: false,
        isComplete: complete,
        start: StrokeEndOptions.start(cap: false),
        end: StrokeEndOptions.end(cap: false),
      );
  }
}

/// Piso da pressão na largura: a caneta informa pressão baixa ao encostar e ao
/// levantar, e sem piso as pontas ficavam quase invisíveis. `p' = 0,25 + 0,75 p`.
double pressureWithFloor(double p) => 0.25 + 0.75 * p.clamp(0.0, 1.0);

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
      [for (final p in pts) PointVector(p.x, p.y, pressureWithFloor(p.p))],
      options: strokeOptionsFor(tool, width, complete: complete),
    );
  }
  if (outline.length < 3) {
    // Pingo (um ponto) ou traço sem comprimento: círculo na pressão média.
    final p = pts.first;
    final r = radius * (0.5 + 0.5 * pressureWithFloor(p.p));
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
// Cache dos traços prontos (Pictures por bloco de traços, compostos numa página).
// ---------------------------------------------------------------------------

/// Um bloco de até [PageInkCache.chunkSize] traços consecutivos, com o seu
/// próprio Picture de marca-texto e de tinta.
class _Chunk {
  List<Stroke> src = const [];
  ui.Picture? hl;
  ui.Picture? ink;

  void dispose() {
    hl?.dispose();
    ink?.dispose();
    hl = null;
    ink = null;
    src = const [];
  }
}

/// Uma camada pequena (imagens ou textos) com o seu Picture.
class _Layer<T> {
  List<T> src = const [];
  int epoch = -1;
  ui.Picture? pic;

  void dispose() {
    pic?.dispose();
    pic = null;
    src = const [];
    epoch = -1;
  }
}

/// Guarda os contornos de cada traço (traços são imutáveis por id, então o
/// contorno nunca muda) e o `ui.Picture` com tudo que já está pronto na página.
///
/// Os traços ficam em blocos de [chunkSize] com um Picture cada; o Picture da
/// página só compõe (`drawPicture`) os blocos. Esconder um traço (borracha),
/// acrescentar um no fim ou um pedaço da borracha parcial regrava **só o bloco
/// afetado** — não os milhares de traços da página — e nunca recalcula contornos.
/// A ordem de empilhamento é a de antes: imagens, marca-textos, tinta, pedaços
/// novos e textos.
class PageInkCache {
  /// Traços por bloco.
  static const int chunkSize = 256;

  final Map<String, Path> _paths = {};
  final List<_Chunk> _base = [];
  final List<_Chunk> _extra = [];
  final _Layer<ImageBox> _under = _Layer<ImageBox>();
  final _Layer<TextBox> _over = _Layer<TextBox>();
  ui.Picture? _picture;
  PageDoc? _doc;
  Set<String>? _hidden;
  int _epoch = -1;
  int _revision = -1;

  /// Quantas vezes o Picture da página foi recomposto (diagnóstico/testes).
  int rebuilds = 0;

  /// Quantos contornos foram calculados (diagnóstico/testes).
  int outlinesComputed = 0;

  /// Quantos blocos de traços foram regravados (diagnóstico/testes).
  int chunksRecorded = 0;

  Path pathFor(Stroke s) => _paths.putIfAbsent(s.id, () {
    outlinesComputed++;
    return strokeOutlinePath(s.points, s.tool, s.width);
  });

  /// Picture da página. [extra] são traços acrescentados por cima de [doc]
  /// (pedaços da borracha parcial em andamento) e [revision] identifica o
  /// estado de [hidden]/[extra] quando eles são mutados no lugar: o Picture só
  /// é recomposto se algo disso mudou, e só os blocos que mudaram são regravados.
  ui.Picture pictureFor(
    PageDoc doc,
    Set<String> hidden,
    int epoch,
    Map<String, ui.Image> images, {
    List<Stroke> extra = const [],
    int revision = 0,
  }) {
    final cached = _picture;
    if (cached != null &&
        identical(_doc, doc) &&
        identical(_hidden, hidden) &&
        _epoch == epoch &&
        _revision == revision) {
      return cached;
    }
    cached?.dispose();
    _syncChunks(_base, doc.strokes, hidden);
    _syncChunks(_extra, extra, hidden);
    _syncImages(doc.images, hidden, epoch, images);
    _syncTexts(doc.texts, hidden);

    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec, const Rect.fromLTWH(0, 0, pageWidth, pageHeight));
    if (_under.pic != null) canvas.drawPicture(_under.pic!);
    for (final list in [_base, _extra]) {
      for (final c in list) {
        if (c.hl != null) canvas.drawPicture(c.hl!);
      }
    }
    for (final list in [_base, _extra]) {
      for (final c in list) {
        if (c.ink != null) canvas.drawPicture(c.ink!);
      }
    }
    if (_over.pic != null) canvas.drawPicture(_over.pic!);
    _picture = rec.endRecording();
    _doc = doc;
    _hidden = hidden;
    _epoch = epoch;
    _revision = revision;
    rebuilds++;
    // Poda contornos de traços que já não existem.
    if (_paths.length > doc.strokes.length + extra.length + 64) {
      final keep = {for (final s in doc.strokes) s.id, for (final s in extra) s.id};
      _paths.removeWhere((id, _) => !keep.contains(id));
    }
    return _picture!;
  }

  /// Deixa [chunks] igual a [strokes] sem os escondidos, regravando só os
  /// blocos cujo conteúdo visível mudou.
  void _syncChunks(List<_Chunk> chunks, List<Stroke> strokes, Set<String> hidden) {
    final n = (strokes.length + chunkSize - 1) ~/ chunkSize;
    while (chunks.length > n) {
      chunks.removeLast().dispose();
    }
    while (chunks.length < n) {
      chunks.add(_Chunk());
    }
    for (var i = 0; i < n; i++) {
      final c = chunks[i];
      final from = i * chunkSize;
      final to = from + chunkSize < strokes.length ? from + chunkSize : strokes.length;
      var j = 0;
      var same = true;
      for (var k = from; k < to; k++) {
        final s = strokes[k];
        if (hidden.contains(s.id)) continue;
        if (j >= c.src.length || !identical(c.src[j], s)) {
          same = false;
          break;
        }
        j++;
      }
      if (same && j == c.src.length) continue;
      final visible = <Stroke>[
        for (var k = from; k < to; k++)
          if (!hidden.contains(strokes[k].id)) strokes[k],
      ];
      c.dispose();
      c.src = visible;
      c.hl = _recordStrokes(visible, highlighter: true);
      c.ink = _recordStrokes(visible, highlighter: false);
      chunksRecorded++;
    }
  }

  ui.Picture? _recordStrokes(List<Stroke> strokes, {required bool highlighter}) {
    if (!strokes.any((s) => (s.tool == PenTool.highlighter) == highlighter)) return null;
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec, const Rect.fromLTWH(0, 0, pageWidth, pageHeight));
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    for (final s in strokes) {
      if ((s.tool == PenTool.highlighter) != highlighter) continue;
      canvas.drawPath(pathFor(s), paint..color = Color(s.argb));
    }
    return rec.endRecording();
  }

  void _syncImages(List<ImageBox> all, Set<String> hidden, int epoch, Map<String, ui.Image> images) {
    final visible = [
      for (final im in all)
        if (!hidden.contains(im.id)) im,
    ];
    if (_under.epoch == epoch && _sameItems(_under.src, visible)) return;
    _under.pic?.dispose();
    _under.src = visible;
    _under.epoch = epoch;
    if (visible.isEmpty) {
      _under.pic = null;
      return;
    }
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec, const Rect.fromLTWH(0, 0, pageWidth, pageHeight));
    for (final im in visible) {
      paintImage(canvas, im, images[im.path]);
    }
    _under.pic = rec.endRecording();
  }

  void _syncTexts(List<TextBox> all, Set<String> hidden) {
    final visible = [
      for (final t in all)
        if (!hidden.contains(t.id)) t,
    ];
    if (_sameItems(_over.src, visible)) return;
    _over.pic?.dispose();
    _over.src = visible;
    if (visible.isEmpty) {
      _over.pic = null;
      return;
    }
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec, const Rect.fromLTWH(0, 0, pageWidth, pageHeight));
    for (final t in visible) {
      paintText(canvas, t);
    }
    _over.pic = rec.endRecording();
  }

  static bool _sameItems<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  void dispose() {
    _picture?.dispose();
    _picture = null;
    for (final c in [..._base, ..._extra]) {
      c.dispose();
    }
    _base.clear();
    _extra.clear();
    _under.dispose();
    _over.dispose();
    _doc = null;
    _hidden = null;
  }
}

/// Desenha uma imagem posicionada (ou o marcador cinza enquanto não carregou).
void paintImage(Canvas canvas, ImageBox im, ui.Image? img) {
  final dst = Rect.fromLTWH(im.x, im.y, im.w, im.h);
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

/// Desenha imagens, marca-textos, demais traços e textos de [doc].
void paintDoc(
  Canvas canvas,
  PageDoc doc, {
  Set<String> hidden = const {},
  Map<String, ui.Image> images = const {},
  Path Function(Stroke)? pathFor,
  List<Stroke> extraStrokes = const [],
}) {
  final outline = pathFor ?? (s) => strokeOutlinePath(s.points, s.tool, s.width);
  for (final im in doc.images) {
    if (hidden.contains(im.id)) continue;
    paintImage(canvas, im, images[im.path]);
  }
  final paint = Paint()
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;
  for (final pass in const [true, false]) {
    for (final list in [doc.strokes, extraStrokes]) {
      for (final s in list) {
        if ((s.tool == PenTool.highlighter) != pass) continue;
        if (hidden.contains(s.id)) continue;
        canvas.drawPath(outline(s), paint..color = Color(s.argb));
      }
    }
  }
  for (final t in doc.texts) {
    if (hidden.contains(t.id)) continue;
    paintText(canvas, t);
  }
}

/// Família da fonte de [t] no Flutter (`null` = a padrão do tema).
String? textFontFamily(TextBox t) => t.font == kHandwritingFont ? 'Caveat' : null;

void paintText(Canvas canvas, TextBox t) {
  final tp = TextPainter(
    text: TextSpan(
      text: t.text,
      style: TextStyle(fontSize: t.size, color: Color(t.argb), height: 1.25, fontFamily: textFontFamily(t)),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: t.w <= 0 ? 1 : t.w);
  tp.paint(canvas, Offset(t.x, t.y));
  tp.dispose();
}

/// Altura real do texto (para o retângulo de seleção/toque).
double measureTextHeight(TextBox t) {
  final tp = TextPainter(
    text: TextSpan(text: t.text, style: TextStyle(fontSize: t.size, height: 1.25, fontFamily: textFontFamily(t))),
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
///
/// Com [erase] ativo (borracha em andamento) mostra o documento sem os traços
/// apagados e com os pedaços novos, regravando o Picture no máximo uma vez por
/// quadro e sem reconstruir widgets.
class CommittedInkPainter extends CustomPainter {
  CommittedInkPainter({
    required this.cache,
    required this.doc,
    required this.hidden,
    required this.epoch,
    required this.images,
    this.erase,
  }) : super(repaint: erase);

  final PageInkCache cache;
  final PageDoc doc;
  final Set<String> hidden;
  final int epoch;
  final Map<String, ui.Image> images;
  final ErasePreview? erase;

  @override
  void paint(Canvas canvas, Size size) {
    // A tinta nunca aparece fora da página (dados antigos/importados incluídos).
    canvas.clipRect(Offset.zero & size);
    final e = erase;
    final pic = e != null && e.active
        ? cache.pictureFor(doc, e.hidden, epoch, images, extra: e.extra, revision: e.revision)
        : cache.pictureFor(doc, hidden, epoch, images);
    canvas.drawPicture(pic);
  }

  @override
  bool shouldRepaint(CommittedInkPainter old) =>
      !identical(old.doc, doc) ||
      !identical(old.hidden, hidden) ||
      old.epoch != epoch ||
      !identical(old.cache, cache) ||
      !identical(old.erase, erase);
}

/// Estado da camada ao vivo (traço em andamento, borracha, laço, prévia da
/// seleção). Notifica só essa camada: o resto da página não repinta.
class LiveInk extends ChangeNotifier {
  List<InkPoint> points = const [];

  /// Amostras cruas do último traço terminado (só o modo `NB_DEBUG_INPUT` as
  /// mostra); [clear] não as apaga: ficam até o próximo traço terminar.
  List<InkPoint> lastPoints = const [];

  /// Contorno incremental de [points] (só a cauda é recalculada a cada evento).
  final LiveStrokeOutline outline = LiveStrokeOutline();
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
    this.debugSamples = false,
  }) : super(repaint: live);

  final LiveInk live;
  final Rect? selectionRect;
  final Color accent;
  final double pixelRatio;
  final Map<String, ui.Image> images;

  /// Diagnóstico da entrada: pontinhos nas amostras cruas do traço atual
  /// (vermelho) e do último traço (azul), por cima de tudo.
  final bool debugSamples;

  /// Raio (em unidades de página) correspondente a [dp] pixels lógicos.
  double _units(Canvas canvas, double dp) {
    final scale = canvas.getTransform()[0].abs() / pixelRatio;
    return scale <= 0 ? dp : dp / scale;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Recorte pela borda da página, como no Samsung Notes: sem tinta fora dela.
    // (As alças da seleção, o laço e a borracha, que são guias, não são recortados.)
    canvas.save();
    canvas.clipRect(Offset.zero & size);
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
      final paths = live.outline.pathsFor(live.points, live.tool, live.width);
      final alpha = (live.argb >>> 24) & 0xFF;
      if (alpha >= 0xFF) {
        final paint = strokePaint(live.argb);
        for (final path in paths) {
          canvas.drawPath(path, paint);
        }
      } else {
        // Traço translúcido em pedaços que se sobrepõem: desenha opaco numa
        // camada e aplica o alfa uma vez só (sem faixas mais escuras nas junções).
        canvas.saveLayer(Offset.zero & size, Paint()..color = Color.fromARGB(alpha, 0, 0, 0));
        final paint = strokePaint(live.argb | 0xFF000000);
        for (final path in paths) {
          canvas.drawPath(path, paint);
        }
        canvas.restore();
      }
    }
    canvas.restore();
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
    if (debugSamples) _paintSamples(canvas);
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

  /// Se o problema é a entrada (faltam pontos) ou o desenho (os pontos estão
  /// lá, mas a tinta não cobre) fica visível no aparelho.
  void _paintSamples(Canvas canvas) {
    // Em unidades de página, menor que a caneta: o contorno ainda aparece em volta.
    final r = math.max(live.width * 0.3, 1.0);
    final last = Paint()..color = const Color(0xFF2979FF);
    for (final p in live.lastPoints) {
      canvas.drawCircle(p.offset, r, last);
    }
    final now = Paint()..color = const Color(0xFFFF1744);
    for (final p in live.points) {
      canvas.drawCircle(p.offset, r, now);
    }
  }

  @override
  bool shouldRepaint(LiveInkPainter old) =>
      old.debugSamples != debugSamples ||
      old.selectionRect != selectionRect ||
      old.accent != accent ||
      !identical(old.images, images);
}
