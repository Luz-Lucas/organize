import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide TextBox;

import '../../ui/org_theme.dart';
import '../core/notebook_core.dart';
import 'ink_painting.dart';
import 'notebook_session.dart';
import 'tool_settings.dart';

class _Claim extends GestureArenaMember {
  @override
  void acceptGesture(int pointer) {}

  @override
  void rejectGesture(int pointer) {}
}

enum _Mode { none, draw, erase, lasso, move, scale, tap }

/// Uma página do caderno: fundo, traços prontos (em cache), camada ao vivo e
/// entrada por [Listener] (não GestureDetector), com a regra:
///
/// * `stylus` desenha; `invertedStylus` ou botão lateral apagam enquanto
///   pressionados; `mouse` (botão esquerdo) desenha;
/// * `touch` só rola/dá zoom (a menos que `fingerDraws`), mas toque curto na
///   ferramenta Texto posiciona/edita texto;
/// * enquanto a caneta está no papel, toque (palma) é ignorado.
///
/// Todas as coordenadas internas são **unidades de página** (1000 × 1414): o
/// `FittedBox` que envolve a página aplica a escala e o Flutter já entrega
/// `event.localPosition` nesse espaço.
class InkPageView extends StatefulWidget {
  const InkPageView({
    super.key,
    required this.index,
    required this.doc,
    required this.background,
    required this.settings,
    required this.penArgb,
    required this.selection,
    required this.imageStore,
    required this.onEdit,
    required this.onSelectionChanged,
    required this.onActivate,
    required this.onTextTap,
  });

  final int index;
  final PageDoc doc;
  final PageBackground background;
  final ToolSettings settings;

  /// Cor ARGB já resolvida da caneta (sem o alfa da caneta).
  final int penArgb;
  final Set<String> selection;
  final NotebookImageStore imageStore;

  /// Um gesto terminou: [before] -> [after] (para o histórico e o salvamento).
  final void Function(PageDoc before, PageDoc after) onEdit;
  final ValueChanged<Set<String>> onSelectionChanged;

  final VoidCallback onActivate;
  final void Function(Offset at, TextBox? existing) onTextTap;

  @override
  State<InkPageView> createState() => _InkPageViewState();
}

class _InkPageViewState extends State<InkPageView> {
  final PageInkCache _cache = PageInkCache();
  final LiveInk _live = LiveInk();
  final Map<String, ui.Image> _images = {};
  final Map<String, ImageStream> _streams = {};
  final Map<String, ImageStreamListener> _listeners = {};
  final Set<String> _requested = {};
  int _epoch = 0;

  PageDoc? _working;
  Set<String> _hidden = const {};

  // Gesto atual.
  int? _ptr;
  _Mode _mode = _Mode.none;
  PageDoc? _before;
  Offset _downPos = Offset.zero;
  Offset _last = Offset.zero;
  Duration _downTime = Duration.zero;
  double _travel = 0;
  List<InkPoint> _pts = [];
  List<Offset> _lasso = [];
  Set<String> _movingIds = const {};
  Offset _anchor = Offset.zero;
  double _startDist = 1;
  final Set<int> _stylusDown = {};

  PageDoc get _doc => _working ?? widget.doc;

  @override
  void initState() {
    super.initState();
    _requestImages();
  }

  @override
  void didUpdateWidget(InkPageView old) {
    super.didUpdateWidget(old);
    if (!identical(old.doc, widget.doc)) {
      if (_ptr == null) _working = null;
      _requestImages();
    }
  }

  @override
  void dispose() {
    for (final e in _listeners.entries) {
      _streams[e.key]?.removeListener(e.value);
    }
    _cache.dispose();
    _live.dispose();
    super.dispose();
  }

  // ---- imagens ------------------------------------------------------------

  void _requestImages() {
    for (final im in widget.doc.images) {
      if (!_requested.add(im.path)) continue;
      final path = im.path;
      widget.imageStore.load(path).then((provider) {
        if (!mounted) return;
        final stream = provider.resolve(ImageConfiguration.empty);
        late final ImageStreamListener l;
        l = ImageStreamListener(
          (info, _) {
            if (!mounted) return;
            setState(() {
              _images[path] = info.image;
              _epoch++;
            });
          },
          onError: (_, _) {},
        );
        _streams[path] = stream;
        _listeners[path] = l;
        stream.addListener(l);
      }, onError: (_) {});
    }
  }

  // ---- entrada ------------------------------------------------------------

  double _dpPerUnit() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return 0.4;
    final m = box.getTransformTo(null);
    return math.sqrt(m.storage[0] * m.storage[0] + m.storage[1] * m.storage[1]);
  }

  double _pressureOf(PointerEvent e) {
    if (e.kind != PointerDeviceKind.stylus && e.kind != PointerDeviceKind.invertedStylus) {
      return 0.5;
    }
    final range = e.pressureMax - e.pressureMin;
    if (range <= 0) return 0.5;
    final p = ((e.pressure - e.pressureMin) / range).clamp(0.0, 1.0);
    // Caneta que não informa pressão (0 constante): largura média.
    return p <= 0 ? 0.5 : p;
  }

  /// Ganha a arena de gestos deste ponteiro na hora (antes de o
  /// InteractiveViewer, pai desta página, poder reconhecer um arrasto): assim
  /// a caneta/mouse/dedo-que-desenha nunca rola nem dá zoom na página, sem
  /// depender de um rebuild.
  void _claim(int pointer) {
    GestureBinding.instance.gestureArena
        .add(pointer, _Claim())
        .resolve(GestureDisposition.accepted);
  }

  void _onDown(PointerDownEvent e) {
    widget.onActivate();
    final kind = e.kind;
    if (kind == PointerDeviceKind.stylus || kind == PointerDeviceKind.invertedStylus) {
      _stylusDown.add(e.pointer);
    }
    // Palma: toque enquanto a caneta está no papel (não desenha nem rola).
    if (kind == PointerDeviceKind.touch && _stylusDown.isNotEmpty) {
      _claim(e.pointer);
      return;
    }
    if (_ptr != null) return;

    final s = widget.settings;
    var erase = false;
    var act = false;
    switch (kind) {
      case PointerDeviceKind.invertedStylus:
        act = true;
        erase = true;
      case PointerDeviceKind.stylus:
        act = true;
        erase = (e.buttons & (kPrimaryStylusButton | kSecondaryStylusButton)) != 0;
      case PointerDeviceKind.mouse:
        act = e.buttons == kPrimaryMouseButton;
      case PointerDeviceKind.touch:
      case PointerDeviceKind.unknown:
      case PointerDeviceKind.trackpad:
        act = s.fingerDraws;
    }
    var mode = _Mode.none;
    if (act) {
      if (erase || s.kind == ToolKind.eraser) {
        mode = _Mode.erase;
      } else {
        mode = switch (s.kind) {
          ToolKind.draw => _Mode.draw,
          ToolKind.lasso => _Mode.lasso,
          ToolKind.text => _Mode.tap,
          ToolKind.eraser => _Mode.erase,
        };
      }
    } else if (kind == PointerDeviceKind.touch && s.kind == ToolKind.text) {
      mode = _Mode.tap; // toque curto posiciona texto; o pan continua valendo
    }
    if (mode == _Mode.none) return;

    _ptr = e.pointer;
    _before = widget.doc;
    _downPos = _last = e.localPosition;
    _downTime = e.timeStamp;
    _travel = 0;
    if (!(kind == PointerDeviceKind.touch && !s.fingerDraws)) _claim(e.pointer);

    switch (mode) {
      case _Mode.draw:
        _pts = [InkPoint(e.localPosition.dx, e.localPosition.dy, _pressureOf(e))];
        _live
          ..tool = s.pen
          ..argb = withPenAlpha(widget.penArgb, s.pen)
          ..width = s.baseWidth * penWidthFactor(s.pen)
          ..points = _pts
          ..changed();
        _mode = _Mode.draw;
      case _Mode.erase:
        _mode = _Mode.erase;
        _working = widget.doc;
        _live
          ..eraserPos = e.localPosition
          ..eraserRadius = kEraserRadius
          ..changed();
        _eraseTo(e.localPosition, null);
      case _Mode.lasso:
        _startLasso(e.localPosition);
      case _Mode.tap:
        _mode = _Mode.tap;
      default:
        break;
    }
  }

  void _startLasso(Offset pos) {
    final sel = widget.selection;
    final rect = sel.isEmpty ? null : itemsBounds(_doc, sel);
    if (rect != null) {
      final u = 1 / math.max(_dpPerUnit(), 0.01);
      final hit = 22 * u;
      final corners = [rect.topLeft, rect.topRight, rect.bottomLeft, rect.bottomRight];
      final opposite = [rect.bottomRight, rect.bottomLeft, rect.topRight, rect.topLeft];
      for (var i = 0; i < 4; i++) {
        if ((corners[i] - pos).distance <= hit) {
          _beginTransform(sel, rect);
          _anchor = opposite[i];
          _startDist = math.max((pos - _anchor).distance, 1);
          _mode = _Mode.scale;
          return;
        }
      }
      if (rect.inflate(6 * u).contains(pos)) {
        _beginTransform(sel, rect);
        _mode = _Mode.move;
        return;
      }
    }
    _lasso = [pos];
    _live
      ..lasso = _lasso
      ..changed();
    _mode = _Mode.lasso;
  }

  void _beginTransform(Set<String> ids, Rect rect) {
    _movingIds = ids;
    _working = widget.doc;
    final moving = extractItems(widget.doc, ids);
    setState(() => _hidden = Set.unmodifiable(ids));
    _live
      ..movingDoc = moving
      ..moveMatrix = Matrix2x3.identity
      ..changed();
  }

  void _eraseTo(Offset pos, Offset? from) {
    final doc = _doc;
    PageDoc next = doc;
    if (widget.settings.eraserMode == EraserMode.partial) {
      next = erasePartial(doc, [from ?? pos, pos], kEraserRadius, newInkId);
    } else {
      final ids = hitStrokes(doc, pos, kEraserRadius, from: from);
      if (ids.isNotEmpty) next = doc.without(ids);
    }
    if (!identical(next, doc)) setState(() => _working = next);
  }

  void _onMove(PointerMoveEvent e) {
    if (e.pointer != _ptr) return;
    final pos = e.localPosition;
    _travel += (pos - _last).distance;
    switch (_mode) {
      case _Mode.draw:
        if ((pos - _last).distance >= 0.4) {
          _pts.add(InkPoint(pos.dx, pos.dy, _pressureOf(e)));
          _live
            ..points = _pts
            ..changed();
        }
      case _Mode.erase:
        _live
          ..eraserPos = pos
          ..changed();
        _eraseTo(pos, _last);
      case _Mode.lasso:
        _lasso.add(pos);
        _live
          ..lasso = _lasso
          ..changed();
      case _Mode.move:
        _live
          ..moveMatrix = Matrix2x3.translation(pos.dx - _downPos.dx, pos.dy - _downPos.dy)
          ..changed();
      case _Mode.scale:
        final f = (pos - _anchor).distance / _startDist;
        _live
          ..moveMatrix = Matrix2x3.scaling(f.clamp(0.1, 10.0), anchor: _anchor)
          ..changed();
      default:
        break;
    }
    _last = pos;
  }

  void _onUp(PointerUpEvent e) {
    if (e.kind == PointerDeviceKind.stylus || e.kind == PointerDeviceKind.invertedStylus) {
      _stylusDown.remove(e.pointer);
    }
    if (e.pointer != _ptr) return;
    final before = _before ?? widget.doc;
    final mode = _mode;
    switch (mode) {
      case _Mode.draw:
        if (_pts.isNotEmpty) {
          final st = Stroke(
            id: newInkId(),
            tool: _live.tool,
            argb: _live.argb,
            width: _live.width,
            points: _pts,
          );
          widget.onEdit(before, widget.doc.withStroke(st));
        }
      case _Mode.erase:
        final w = _working;
        if (w != null && !identical(w, before)) widget.onEdit(before, w);
      case _Mode.lasso:
        _finishLasso();
      case _Mode.move:
      case _Mode.scale:
        _finishTransform(before);
      case _Mode.tap:
        _finishTap(e);
      default:
        break;
    }
    _endGesture();
  }

  void _finishLasso() {
    final pts = _lasso;
    final box = pts.length < 3 ? Rect.zero : _bounds(pts);
    if (box.width < 4 && box.height < 4) {
      if (widget.selection.isNotEmpty) widget.onSelectionChanged(const {});
      return;
    }
    widget.onSelectionChanged(lassoSelect(widget.doc, pts));
  }

  Rect _bounds(List<Offset> pts) {
    var l = double.infinity, t = double.infinity, r = -double.infinity, b = -double.infinity;
    for (final p in pts) {
      l = math.min(l, p.dx);
      r = math.max(r, p.dx);
      t = math.min(t, p.dy);
      b = math.max(b, p.dy);
    }
    return Rect.fromLTRB(l, t, r, b);
  }

  void _finishTransform(PageDoc before) {
    final m = _live.moveMatrix;
    final unchanged = m.a == 1 && m.d == 1 && m.tx.abs() < 0.5 && m.ty.abs() < 0.5;
    if (unchanged || _movingIds.isEmpty) return;
    final r = transformItemsMapped(widget.doc, _movingIds, m);
    widget.onEdit(before, r.doc);
    widget.onSelectionChanged({for (final id in _movingIds) r.idMap[id] ?? id});
  }

  void _finishTap(PointerUpEvent e) {
    final dt = e.timeStamp - _downTime;
    if (_travel > 12 || dt > const Duration(milliseconds: 600)) return;
    TextBox? hit;
    for (final t in widget.doc.texts.reversed) {
      final r = Rect.fromLTWH(t.x, t.y, t.w, math.max(measureTextHeight(t), t.size));
      if (r.inflate(6).contains(_downPos)) {
        hit = t;
        break;
      }
    }
    widget.onTextTap(_downPos, hit);
  }

  void _onCancel(PointerCancelEvent e) {
    _stylusDown.remove(e.pointer);
    if (e.pointer != _ptr) return;
    _working = null;
    _endGesture();
  }

  void _endGesture() {
    _ptr = null;
    _mode = _Mode.none;
    _before = null;
    _pts = [];
    _lasso = [];
    _movingIds = const {};
    _live.clear();
    // O pai atualiza `widget.doc`; até lá mostramos o resultado do gesto.
    setState(() {
      _hidden = const {};
    });
  }

  // ---- build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final org = context.org;
    final doc = _doc;
    final sel = widget.selection;
    Rect? selRect;
    if (sel.isNotEmpty) selRect = itemsBounds(doc, sel);
    return Listener(
      key: ValueKey('nb-page-${widget.index}'),
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onUp,
      onPointerCancel: _onCancel,
      child: SizedBox(
        width: pageWidth,
        height: pageHeight,
        child: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: CustomPaint(
                painter: PageBackgroundPainter(
                  background: widget.background,
                  paper: org.surfaceRaised,
                  line: org.line,
                ),
              ),
            ),
            RepaintBoundary(
              child: CustomPaint(
                key: const ValueKey('nb-committed'),
                painter: CommittedInkPainter(
                  cache: _cache,
                  doc: doc,
                  hidden: _hidden,
                  epoch: _epoch,
                  images: _images,
                ),
              ),
            ),
            RepaintBoundary(
              child: CustomPaint(
                key: const ValueKey('nb-live'),
                painter: LiveInkPainter(
                  live: _live,
                  selectionRect: selRect,
                  accent: org.accent,
                  pixelRatio: MediaQuery.devicePixelRatioOf(context),
                  images: _images,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
