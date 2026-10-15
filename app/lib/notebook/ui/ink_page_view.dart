import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide TextBox;
import 'package:flutter/scheduler.dart';

import '../../ui/org_theme.dart';
import '../core/notebook_core.dart';
import 'eraser_session.dart';
import 'ink_painting.dart';
import 'notebook_session.dart';
import 'page_images.dart';
import 'pen_activity.dart';
import 'stroke_grid.dart';
import 'tool_settings.dart';

/// Modo de diagnóstico da entrada (escondido): `--dart-define=NB_DEBUG_INPUT=true`
/// mostra, em cada página, kind, buttons e pressure do último evento do ponteiro.
const bool kNbDebugInput = bool.fromEnvironment('NB_DEBUG_INPUT');

/// Botões da caneta que viram borracha: o lateral da S Pen (alguns Samsung
/// informam `BUTTON_SECONDARY`, que é [kSecondaryMouseButton]).
const int kStylusEraseButtons = kPrimaryStylusButton | kSecondaryStylusButton | kSecondaryMouseButton;

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
/// * palma ([PenActivity], global a todas as páginas): com a caneta ativa
///   (no papel, em hover ou até 1,5 s depois de levantar) e sem "dedo desenha",
///   um dedo é ignorado (nem rola) e dois dedos rolam/dão zoom; com "dedo
///   desenha", toque grande (`radiusMajor` > [kPalmRadiusMajor]) é palma;
/// * a caneta tem prioridade: ao encostar, cancela toques em andamento;
/// * fora da área visível a página fica leve: só o fundo, sem `Picture`.
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
    this.onInkTap,
    this.overlay,
    this.debugInput = kNbDebugInput,
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

  /// Toque curto (sem arrasto) com o laço, em [at] (unidades de página). Se
  /// devolver `true` o toque foi usado (ex.: abrir as sugestões do corretor) e a
  /// seleção fica como está.
  final bool Function(Offset at)? onInkTap;

  /// Camada desenhada por cima da tinta, em unidades de página, sem receber toques
  /// (o sublinhado do corretor).
  final Widget? overlay;

  /// Mostra kind, buttons e pressure do último evento (diagnóstico).
  final bool debugInput;

  @override
  State<InkPageView> createState() => _InkPageViewState();
}

class _InkPageViewState extends State<InkPageView> {
  final PageInkCache _cache = PageInkCache();
  final LiveInk _live = LiveInk();
  final PageImageSet _imageSet = PageImageSet();
  final Set<String> _requested = {};
  int _epoch = 0;

  Map<String, ui.Image> get _images => _imageSet.images;

  // Borracha: processada por quadro, com índice espacial e sem regravar tudo.
  final ErasePreview _erasePreview = ErasePreview();
  EraseSession? _erase;
  bool _eraseScheduled = false;
  PageDoc? _gridDoc;
  StrokeGrid? _grid;

  // Caneta/palma (estado global compartilhado entre as páginas).
  late PenActivity _pen;
  final Map<int, Offset> _palmTouches = {};
  final Map<int, GestureArenaEntry> _palmEntries = {};
  bool _palmClaimed = false;

  // Visibilidade: página fora da tela fica leve.
  TransformationController? _viewer;
  bool _visible = true;
  bool _visibilityScheduled = false;

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

  /// O traço já saiu pela borda da página: o resto do gesto não vira tinta.
  bool _exited = false;
  List<Offset> _lasso = [];
  Set<String> _movingIds = const {};
  Offset _anchor = Offset.zero;
  double _startDist = 1;

  PageDoc get _doc => _working ?? widget.doc;

  @override
  void initState() {
    super.initState();
    _pen = PenActivity.of(context)..attach();
    if (widget.debugInput) _pen.debugEnabled = true;
    final viewer = context.findAncestorWidgetOfExactType<InteractiveViewer>();
    _viewer = viewer?.transformationController;
    // Sem o InteractiveViewer da tela não há como saber o que é visível.
    _visible = _viewer == null || widget.index == 0;
    _viewer?.addListener(_scheduleVisibility);
    _scheduleVisibility();
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
    _viewer?.removeListener(_scheduleVisibility);
    _pen.detach();
    _imageSet.dispose();
    _cache.dispose();
    _live.dispose();
    _erasePreview.dispose();
    super.dispose();
  }

  // ---- visibilidade -------------------------------------------------------

  void _scheduleVisibility() {
    if (_visibilityScheduled || !mounted) return;
    _visibilityScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _visibilityScheduled = false;
      if (mounted) _updateVisibility();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  /// Aparece com uma folga de meia tela e só se esconde a uma tela inteira de
  /// distância (histerese: evita piscar na borda).
  void _updateVisibility() {
    final box = context.findRenderObject();
    final view = View.maybeOf(context);
    if (box is! RenderBox || !box.hasSize || !box.attached || view == null) return;
    final screen = view.physicalSize / view.devicePixelRatio;
    final rect = MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size);
    final vp = Offset.zero & screen;
    final show = rect.overlaps(vp.inflate(screen.height * 0.5));
    final keep = rect.overlaps(vp.inflate(screen.height));
    if (!_visible && show) {
      setState(() => _visible = true);
    } else if (_visible && !keep && _ptr == null) {
      _cache.dispose(); // solta o Picture; os contornos continuam em cache
      _grid = null;
      _gridDoc = null;
      setState(() => _visible = false);
    }
  }

  // ---- imagens ------------------------------------------------------------

  void _requestImages() {
    for (final im in widget.doc.images) {
      if (!_requested.add(im.path)) continue;
      final path = im.path;
      widget.imageStore.load(path).then((provider) {
        if (!mounted) return;
        final stream = provider.resolve(ImageConfiguration.empty);
        _imageSet.attach(path, stream, () {
          if (!mounted) return;
          setState(() => _epoch++);
        });
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
    _pen.note(e);
    final kind = e.kind;
    final s = widget.settings;
    if (kind == PointerDeviceKind.touch) {
      final penOn = _pen.isActive;
      final palm = s.fingerDraws && e.radiusMajor > kPalmRadiusMajor;
      if (penOn && !s.fingerDraws) {
        // Um dedo é ignorado (nem rola); dois dedos rolam e dão zoom. Por isso
        // só seguramos um lugar na arena (impede o InteractiveViewer de ganhar
        // por ser o único) e decidimos quando o dedo se mexe (ver [_onMove]).
        _palmTouches[e.pointer] = e.position;
        final entry = GestureBinding.instance.gestureArena.add(e.pointer, _Claim());
        _palmEntries[e.pointer] = entry;
        if (_palmClaimed) entry.resolve(GestureDisposition.accepted);
        return;
      }
      if (penOn || palm) {
        _claim(e.pointer);
        return;
      }
    }
    if (!_visible) setState(() => _visible = true);
    widget.onActivate();
    if (_ptr != null) return;

    var erase = false;
    var act = false;
    switch (kind) {
      case PointerDeviceKind.invertedStylus:
        act = true;
        erase = true;
      case PointerDeviceKind.stylus:
        act = true;
        erase = (e.buttons & kStylusEraseButtons) != 0;
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
        final start = _clampToPage(e.localPosition);
        _exited = false;
        _pts = [InkPoint(start.dx, start.dy, _pressureOf(e))];
        _live
          ..tool = s.pen
          ..argb = withPenAlpha(widget.penArgb, s.pen)
          ..width = s.baseWidth * penWidthFactor(s.pen)
          ..points = _pts
          ..changed();
        _mode = _Mode.draw;
      case _Mode.erase:
        _mode = _Mode.erase;
        if (!identical(_gridDoc, widget.doc)) {
          _grid = StrokeGrid.build(widget.doc.strokes);
          _gridDoc = widget.doc;
        }
        _erase = EraseSession(base: widget.doc, mode: s.eraserMode, index: _grid, radius: s.eraserRadius);
        _live
          ..eraserPos = e.localPosition
          ..eraserRadius = s.eraserRadius
          ..changed();
        _erase!.add(e.localPosition);
        _flushErase(); // o primeiro toque apaga na hora
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

  /// Junta os eventos da borracha por quadro: a S Pen manda ~240/s e a tela só
  /// desenha 60/s, então um lote (caminho acumulado) por quadro basta.
  void _scheduleErase() {
    if (_eraseScheduled) return;
    _eraseScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _eraseScheduled = false;
      _flushErase();
    });
  }

  void _flushErase() {
    final e = _erase;
    if (e != null && e.flush()) _erasePreview.show(e);
  }

  void _onMove(PointerMoveEvent e) {
    _pen.note(e);
    final palmDown = _palmTouches[e.pointer];
    if (palmDown != null) {
      // Um dedo sozinho que se mexe com a caneta ativa: ignora (a arena é
      // fechada antes de o InteractiveViewer aceitar o pan). Com dois dedos
      // (ou mais) deixa passar: rolam e dão zoom.
      if (!_palmClaimed && _palmTouches.length == 1 && (e.position - palmDown).distance > 3) {
        _palmClaimed = true;
        for (final entry in _palmEntries.values) {
          entry.resolve(GestureDisposition.accepted);
        }
      }
      return;
    }
    if (e.pointer != _ptr) return;
    final pos = e.localPosition;
    _travel += (pos - _last).distance;
    switch (_mode) {
      case _Mode.draw:
        if (_addDrawPoint(pos, _pressureOf(e), minStep: 0.4)) {
          _live
            ..points = _pts
            ..changed();
        }
      case _Mode.erase:
        _live
          ..eraserPos = pos
          ..changed();
        _erase?.add(pos);
        _scheduleErase();
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

  static bool _insidePage(Offset o) => o.dx >= 0 && o.dx <= pageWidth && o.dy >= 0 && o.dy <= pageHeight;

  static Offset _clampToPage(Offset o) =>
      Offset(o.dx.clamp(0.0, pageWidth).toDouble(), o.dy.clamp(0.0, pageHeight).toDouble());

  /// Acrescenta [pos] ao traço, limitado à página: um ponto que cai fora vira o
  /// ponto da borda por onde o traço saiu (corte do segmento) e o resto do
  /// gesto deixa de virar tinta (sem linha ao longo da borda nem corda de volta).
  /// Devolve se o traço mudou.
  bool _addDrawPoint(Offset pos, double pressure, {required double minStep}) {
    if (_exited || _pts.isEmpty) return false;
    final last = _pts.last.offset;
    var at = pos;
    if (!_insidePage(pos)) {
      _exited = true;
      final d = pos - last;
      var t = 1.0;
      if (pos.dx < 0) t = math.min(t, (0 - last.dx) / d.dx);
      if (pos.dx > pageWidth) t = math.min(t, (pageWidth - last.dx) / d.dx);
      if (pos.dy < 0) t = math.min(t, (0 - last.dy) / d.dy);
      if (pos.dy > pageHeight) t = math.min(t, (pageHeight - last.dy) / d.dy);
      at = _clampToPage(last + d * t.clamp(0.0, 1.0));
      if ((at - last).distance <= 0) return false;
    } else if ((at - last).distance < math.max(minStep, 1e-9)) {
      return false;
    }
    _pts.add(InkPoint(at.dx, at.dy, pressure));
    return true;
  }

  /// Grava o traço em andamento (se houver pontos) como uma edição.
  void _commitStroke(PageDoc before) {
    if (_pts.isEmpty) return;
    final st = Stroke(
      id: newInkId(),
      tool: _live.tool,
      argb: _live.argb,
      width: _live.width,
      points: _pts,
    );
    widget.onEdit(before, widget.doc.withStroke(st));
  }

  void _onUp(PointerUpEvent e) {
    _pen.note(e);
    _forgetPalm(e.pointer);
    if (e.pointer != _ptr) return;
    final before = _before ?? widget.doc;
    final mode = _mode;
    switch (mode) {
      case _Mode.draw:
        // O `up` também é uma posição: sem ela o trecho entre a última amostra
        // de movimento e o ponto onde a caneta saiu se perdia (a pressão é a do
        // último ponto, pois o `up` costuma vir com pressão 0).
        if (_pts.isNotEmpty) _addDrawPoint(e.localPosition, _pts.last.p, minStep: 0);
        _commitStroke(before);
      case _Mode.erase:
        _flushErase();
        final w = _erase?.result();
        if (w != null && !identical(w, before)) {
          _working = w; // até o pai atualizar `widget.doc`
          widget.onEdit(before, w);
        }
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
      if (widget.onInkTap?.call(pts.isEmpty ? _downPos : pts.first) ?? false) return;
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
    _pen.note(e);
    _forgetPalm(e.pointer);
    if (e.pointer != _ptr) return;
    // O sistema cancelou a caneta (rejeição de palma, troca de app): o que já
    // foi escrito é do usuário, então o traço parcial é gravado como no `up`.
    // Não acrescentamos a posição do cancelamento (pode ser inválida).
    if (_mode == _Mode.draw && _pts.length >= 2) {
      _commitStroke(_before ?? widget.doc);
    } else {
      _working = null;
    }
    _endGesture();
  }

  void _forgetPalm(int pointer) {
    _palmEntries.remove(pointer);
    if (_palmTouches.remove(pointer) != null && _palmTouches.isEmpty) _palmClaimed = false;
  }

  void _endGesture() {
    if (widget.debugInput && _mode == _Mode.draw && _pts.isNotEmpty) _live.lastPoints = _pts;
    _erase = null;
    _erasePreview.clear();
    _ptr = null;
    _mode = _Mode.none;
    _before = null;
    _pts = [];
    _exited = false;
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
      onPointerHover: _pen.note,
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
            // Fora da tela: só o fundo (sem Picture dos traços, sem camada ao vivo).
            if (_visible) ...[
              RepaintBoundary(
                child: CustomPaint(
                  key: const ValueKey('nb-committed'),
                  painter: CommittedInkPainter(
                    cache: _cache,
                    doc: doc,
                    hidden: _hidden,
                    epoch: _epoch,
                    images: _images,
                    erase: _erasePreview,
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
                    debugSamples: widget.debugInput,
                  ),
                ),
              ),
            ],
            if (_visible && widget.overlay != null)
              Positioned.fill(child: IgnorePointer(child: widget.overlay!)),
            if (widget.debugInput)
              Positioned(
                left: 12,
                top: 12,
                child: IgnorePointer(
                  child: ValueListenableBuilder<String>(
                    valueListenable: _pen.lastEvent,
                    builder: (context, text, _) => Container(
                      key: const ValueKey('nb-debug-input'),
                      padding: const EdgeInsets.all(10),
                      color: const Color(0xCC000000),
                      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 26)),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
