import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide TextBox;
import 'package:flutter/services.dart';

import '../../ui/org_theme.dart';
import '../core/notebook_core.dart';
import 'ink_page_view.dart';
import 'notebook_session.dart';
import 'notebook_toolbar.dart';
import 'tool_settings.dart';

export 'notebook_session.dart';

/// Imagem escolhida pelo usuário (galeria/arquivo).
class PickedImage {
  const PickedImage({required this.bytes, required this.ext, this.width, this.height});

  final Uint8List bytes;

  /// Extensão sem ponto (`png`, `jpg`…).
  final String ext;

  /// Dimensões em pixels, se já conhecidas (senão a tela decodifica).
  final int? width, height;
}

/// Abre o seletor de arquivos do sistema (Android e Linux).
Future<PickedImage?> pickImageFromSystem() async {
  final res = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
  if (res == null || res.files.isEmpty) return null;
  final f = res.files.first;
  var bytes = f.bytes;
  if (bytes == null && f.path != null) bytes = await File(f.path!).readAsBytes();
  if (bytes == null) return null;
  var ext = (f.extension ?? '').toLowerCase();
  if (ext.isEmpty) ext = 'png';
  return PickedImage(bytes: bytes, ext: ext);
}

/// Escala horizontal de [m] (o `getMaxScaleOnAxis` conta o eixo z, que é 1).
double _xScale(Matrix4 m) => math.sqrt(m.storage[0] * m.storage[0] + m.storage[1] * m.storage[1]);

const int kMaxImageBytes = 10 * 1024 * 1024;

class _Slot {
  _Slot(this.doc, this.background);

  PageDoc doc;
  PageBackground background;
  History history = const History();
}

/// Tela do Caderno (rota `/caderno/:id`): páginas A4 em rolagem vertical,
/// caneta/borracha/laço/texto/imagem, desfazer/refazer, zoom 50–400 %.
///
/// Recebe uma [NotebookSession] (ver `notebook_session.dart`): não conhece o
/// repositório nem o Supabase.
class NotebookScreen extends StatefulWidget {
  const NotebookScreen({
    super.key,
    required this.noteId,
    required this.session,
    required this.title,
    this.pickImage,
  });

  final String noteId;
  final NotebookSession session;
  final String title;

  /// Escolhe uma imagem (padrão: seletor do sistema). Injetável nos testes.
  final Future<PickedImage?> Function()? pickImage;

  @override
  State<NotebookScreen> createState() => _NotebookScreenState();
}

class _NotebookScreenState extends State<NotebookScreen> {
  final List<_Slot> _slots = [];
  bool _loaded = false;
  StreamSubscription<List<NotebookPageState>>? _pagesSub;
  StreamSubscription<SaveStatus>? _statusSub;
  late SaveStatus _status = widget.session.status;

  ToolSettings _settings = const ToolSettings();
  int _active = 0;
  int _selPage = -1;
  Set<String> _selIds = const {};
  PageDoc? _clip;

  final TransformationController _tc = TransformationController();
  final ValueNotifier<double> _zoom = ValueNotifier(1.0);
  final GlobalKey _viewportKey = GlobalKey();
  Size _viewport = Size.zero;
  Size _content = Size.zero;
  EdgeInsets _margin = const EdgeInsets.all(48);
  int? _middlePointer;

  @override
  void initState() {
    super.initState();
    _tc.addListener(_onTransform);
    _pagesSub = widget.session.pages.listen(_onPages);
    _statusSub = widget.session.statusChanges.listen((s) {
      if (mounted) setState(() => _status = s);
    });
  }

  @override
  void dispose() {
    _pagesSub?.cancel();
    _statusSub?.cancel();
    _tc.removeListener(_onTransform);
    _tc.dispose();
    _zoom.dispose();
    super.dispose();
  }

  void _onTransform() {
    final s = _xScale(_tc.value);
    if (s != _zoom.value) _zoom.value = s;
  }

  // ---- dados --------------------------------------------------------------

  void _onPages(List<NotebookPageState> list) {
    if (!mounted) return;
    setState(() {
      _loaded = true;
      for (var i = 0; i < list.length; i++) {
        final p = list[i];
        if (i < _slots.length) {
          final s = _slots[i];
          s.background = p.background;
          if (!identical(p.doc, s.doc)) {
            final merged = s.doc.merge(p.doc);
            if (merged != s.doc) s.doc = merged;
          }
        } else {
          _slots.add(_Slot(p.doc, p.background));
        }
      }
      if (_slots.length > list.length) _slots.removeRange(list.length, _slots.length);
      _active = _slots.isEmpty ? 0 : _active.clamp(0, _slots.length - 1);
      _cleanSelection();
    });
  }

  void _cleanSelection() {
    if (_selIds.isEmpty) return;
    if (_selPage < 0 || _selPage >= _slots.length) {
      _selIds = const {};
      _selPage = -1;
      return;
    }
    final doc = _slots[_selPage].doc;
    final keep = {for (final id in _selIds) if (doc.contains(id)) id};
    if (keep.length != _selIds.length) _selIds = keep;
  }

  void _commit(int idx, PageDoc before, PageDoc after) {
    if (idx >= _slots.length || identical(before, after)) return;
    final s = _slots[idx];
    setState(() {
      s.history = s.history.record(before, after);
      s.doc = identical(s.doc, before) ? after : s.doc.merge(after);
      _active = idx;
    });
    widget.session.updatePage(idx, s.doc);
  }

  void _undoRedo({required bool undo}) {
    if (_slots.isEmpty) return;
    final s = _slots[_active];
    final step = undo ? s.history.undo(s.doc) : s.history.redo(s.doc);
    if (step == null) return;
    setState(() {
      s.history = step.history;
      s.doc = step.doc;
      _selIds = const {};
      _selPage = -1;
    });
    widget.session.updatePage(_active, s.doc);
  }

  // ---- ferramentas --------------------------------------------------------

  int _penArgb(OrgThemeSpec org) => _settings.argb ?? org.ink.toARGB32();

  void _setSettings(ToolSettings s) {
    setState(() {
      if (s.kind != _settings.kind && s.kind != ToolKind.lasso) {
        _selIds = const {};
        _selPage = -1;
      }
      _settings = s;
    });
  }

  Future<void> _pickCustomColor() async {
    final c = await showDialog<Color>(
      context: context,
      builder: (_) => _ColorDialog(initial: Color(_penArgb(context.org))),
    );
    if (c != null) _setSettings(_settings.copyWith(argb: c.toARGB32()));
  }

  // ---- seleção ------------------------------------------------------------

  void _copySelection() {
    if (_selPage < 0 || _selIds.isEmpty) return;
    setState(() => _clip = extractItems(_slots[_selPage].doc, _selIds));
  }

  void _deleteSelection() {
    if (_selPage < 0 || _selIds.isEmpty) return;
    final idx = _selPage;
    final ids = _selIds;
    final before = _slots[idx].doc;
    setState(() {
      _selIds = const {};
      _selPage = -1;
    });
    _commit(idx, before, before.without(ids));
  }

  Future<void> _recolorSelection() async {
    if (_selPage < 0 || _selIds.isEmpty) return;
    final org = context.org;
    final c = await showDialog<Color>(
      context: context,
      builder: (_) => _ColorDialog(initial: Color(_penArgb(org))),
    );
    if (c == null || !mounted || _selPage < 0) return;
    final idx = _selPage;
    final before = _slots[idx].doc;
    final r = recolorMapped(before, _selIds, c.toARGB32());
    setState(() => _selIds = {for (final id in _selIds) r.idMap[id] ?? id});
    _commit(idx, before, r.doc);
  }

  void _pasteClip() {
    final clip = _clip;
    if (clip == null || _slots.isEmpty) return;
    final idx = _active;
    final before = _slots[idx].doc;
    final r = pasteDocMapped(before, clip, dx: 30, dy: 30);
    setState(() {
      _selPage = idx;
      _selIds = r.idMap.values.toSet();
    });
    _commit(idx, before, r.doc);
  }

  // ---- texto --------------------------------------------------------------

  Future<void> _editText(int idx, Offset at, TextBox? existing) async {
    final org = context.org;
    final res = await showDialog<_TextResult>(
      context: context,
      builder: (_) => _TextDialog(initial: existing?.text ?? '', canDelete: existing != null),
    );
    if (res == null || !mounted || idx >= _slots.length) return;
    final before = _slots[idx].doc;
    var after = before;
    if (existing != null) after = after.without({existing.id});
    final text = res.text.trim();
    if (!res.delete && text.isNotEmpty) {
      final x = existing?.x ?? at.dx.clamp(0.0, pageWidth - 120);
      final y = existing?.y ?? at.dy.clamp(0.0, pageHeight - 40);
      final argb = existing?.argb ?? (_penArgb(org) & 0x00FFFFFF) | 0xFF000000;
      final size = existing?.size ?? 22.0 + _settings.widthIndex * 6.0;
      final w = existing?.w ?? math.min(520.0, pageWidth - x - 20);
      after = after.withText(
        TextBox(id: newInkId(), x: x, y: y, w: w, text: text, size: size, argb: argb),
      );
    }
    _commit(idx, before, after);
  }

  // ---- imagem -------------------------------------------------------------

  Future<void> _insertImage() async {
    if (_slots.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final idx = _active;
    final picked = await (widget.pickImage ?? pickImageFromSystem)();
    if (picked == null || !mounted) return;
    if (picked.bytes.length > kMaxImageBytes) {
      messenger.showSnackBar(const SnackBar(content: Text('Imagem maior que 10 MB.')));
      return;
    }
    try {
      var w = picked.width, h = picked.height;
      if (w == null || h == null) {
        final codec = await ui.instantiateImageCodec(picked.bytes);
        final frame = await codec.getNextFrame();
        w = frame.image.width;
        h = frame.image.height;
        frame.image.dispose();
        codec.dispose();
      }
      final path = await widget.session.images.upload(picked.bytes, picked.ext);
      if (!mounted || idx >= _slots.length) return;
      final bw = math.min(500.0, w.toDouble());
      final bh = bw * h / math.max(w, 1);
      final before = _slots[idx].doc;
      final box = ImageBox(
        id: newInkId(),
        x: (pageWidth - bw) / 2,
        y: 160,
        w: bw,
        h: math.min(bh, pageHeight - 200),
        path: path,
      );
      _commit(idx, before, before.withImage(box));
      setState(() {
        _selPage = idx;
        _selIds = {box.id};
        _settings = _settings.copyWith(kind: ToolKind.lasso);
      });
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Não foi possível enviar a imagem.')));
    }
  }

  // ---- páginas ------------------------------------------------------------

  Future<void> _deletePage(int idx) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Apagar a página ${idx + 1}?'),
        content: const Text('O conteúdo da página será apagado.'),
        actions: [
          TextButton(
            key: const ValueKey('nb-confirm-no'),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const ValueKey('nb-confirm-yes'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted || idx >= _slots.length) return;
    setState(() {
      _slots.removeAt(idx);
      if (_selPage == idx) {
        _selIds = const {};
        _selPage = -1;
      } else if (_selPage > idx) {
        _selPage--;
      }
      _active = _slots.isEmpty ? 0 : _active.clamp(0, _slots.length - 1);
    });
    widget.session.deletePage(idx);
  }

  // ---- zoom / rolagem -----------------------------------------------------

  void _setTransform(double scale, Offset tx) {
    final s = scale.clamp(0.5, 4.0);
    final vw = _viewport.width, vh = _viewport.height;
    double clampAxis(double t, double view, double content, double margin) {
      final lo = view - content * s - margin, hi = margin;
      if (lo > hi) return (lo + hi) / 2;
      return t.clamp(lo, hi);
    }

    final x = clampAxis(tx.dx, vw, _content.width, _margin.left);
    final y = clampAxis(tx.dy, vh, _content.height, _margin.top);
    _tc.value = Matrix4.identity()
      ..translateByDouble(x, y, 0, 1)
      ..scaleByDouble(s, s, 1, 1);
  }

  void _zoomBy(double factor, [Offset? focal]) {
    final m = _tc.value;
    final s = _xScale(m);
    final t = m.getTranslation();
    final f = focal ?? Offset(_viewport.width / 2, _viewport.height / 2);
    final ns = (s * factor).clamp(0.5, 4.0);
    final cp = Offset((f.dx - t.x) / s, (f.dy - t.y) / s);
    _setTransform(ns, Offset(f.dx - cp.dx * ns, f.dy - cp.dy * ns));
  }

  void _panBy(Offset d) {
    final t = _tc.value.getTranslation();
    _setTransform(_xScale(_tc.value), Offset(t.x + d.dx, t.y + d.dy));
  }

  Offset _toViewport(Offset global) {
    final box = _viewportKey.currentContext?.findRenderObject();
    if (box is RenderBox && box.hasSize) return box.globalToLocal(global);
    return global;
  }

  void _onSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent || e.kind != PointerDeviceKind.mouse) return;
    GestureBinding.instance.pointerSignalResolver.register(e, (ev) {
      final se = ev as PointerScrollEvent;
      final ctrl = HardwareKeyboard.instance.isControlPressed;
      if (ctrl) {
        _zoomBy(se.scrollDelta.dy > 0 ? 1 / 1.15 : 1.15, _toViewport(se.position));
      } else {
        _panBy(Offset(-se.scrollDelta.dx, -se.scrollDelta.dy));
      }
    });
  }

  // ---- build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final org = context.org;
    final palette = notebookPalette(org);
    final slot = _slots.isEmpty ? null : _slots[_active.clamp(0, _slots.length - 1)];
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              _statusLabel(_status),
              key: const ValueKey('nb-save-status'),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: org.inkMuted),
            ),
          ],
        ),
        actions: [
          IconButton(
            key: const ValueKey('nb-undo'),
            tooltip: 'Desfazer',
            icon: const Icon(Icons.undo),
            onPressed: slot != null && slot.history.canUndo ? () => _undoRedo(undo: true) : null,
          ),
          IconButton(
            key: const ValueKey('nb-redo'),
            tooltip: 'Refazer',
            icon: const Icon(Icons.redo),
            onPressed: slot != null && slot.history.canRedo ? () => _undoRedo(undo: false) : null,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _buildViewer(context)),
          if (_settings.kind == ToolKind.lasso && (_selIds.isNotEmpty || _clip != null))
            _selectionBar(context),
          NotebookToolbar(
            settings: _settings,
            palette: palette,
            currentColor: Color(_penArgb(org)),
            background: slot?.background ?? PageBackground.lined,
            zoom: _zoom,
            onSettings: _setSettings,
            onCustomColor: _pickCustomColor,
            onBackground: (b) {
              if (slot == null) return;
              setState(() => slot.background = b);
              widget.session.setBackground(_active, b);
            },
            onAddPage: widget.session.addPage,
            onInsertImage: _insertImage,
            onZoomIn: () => _zoomBy(1.25),
            onZoomOut: () => _zoomBy(0.8),
          ),
        ],
      ),
    );
  }

  String _statusLabel(SaveStatus s) => switch (s) {
    SaveStatus.saving => 'Salvando…',
    SaveStatus.saved => 'Salvo',
    SaveStatus.offline => 'Sem conexão (salvo no aparelho)',
  };

  Widget _selectionBar(BuildContext context) {
    final org = context.org;
    final has = _selIds.isNotEmpty;
    Widget b(String key, IconData i, String label, VoidCallback? f) => TextButton.icon(
      key: ValueKey(key),
      onPressed: f,
      icon: Icon(i, size: 18),
      label: Text(label),
    );
    return Material(
      color: org.accentSoft,
      child: SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            b('nb-sel-copy', Icons.copy, 'Copiar', has ? _copySelection : null),
            b('nb-sel-paste', Icons.paste, 'Colar', _clip != null ? _pasteClip : null),
            b('nb-sel-color', Icons.palette_outlined, 'Cor', has ? _recolorSelection : null),
            b('nb-sel-delete', Icons.delete_outline, 'Apagar', has ? _deleteSelection : null),
          ],
        ),
      ),
    );
  }

  Widget _buildViewer(BuildContext context) {
    final org = context.org;
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    return LayoutBuilder(
      key: _viewportKey,
      builder: (context, c) {
        _viewport = Size(c.maxWidth, c.maxHeight);
        final pageW = math.min(c.maxWidth - 24, 820.0);
        final pageH = pageW * pageHeight / pageWidth;
        const headerH = 40.0, gap = 12.0, endH = 88.0;
        final total = _slots.length * (headerH + pageH + gap) + endH + 12;
        _content = Size(c.maxWidth, total);
        // O InteractiveViewer só deixa dar zoom out até a área (conteúdo +
        // margem) ainda cobrir a janela; a margem abaixo garante os 50 %.
        _margin = EdgeInsets.symmetric(
          horizontal: math.max(48.0, (2 * c.maxWidth - c.maxWidth) / 2 + 1),
          vertical: math.max(48.0, (2 * c.maxHeight - total) / 2 + 1),
        );
        final penArgb = _penArgb(org);
        return ClipRect(
          child: InteractiveViewer(
            transformationController: _tc,
            constrained: false,
            // A roda do mouse é tratada em [_onSignal] (rola; Ctrl+roda = zoom);
            // sem isso o InteractiveViewer daria zoom a cada clique da roda.
            scaleFactor: double.infinity,
            minScale: 0.5,
            maxScale: 4,
            boundaryMargin: _margin,
            child: Listener(
              onPointerSignal: _onSignal,
              onPointerDown: (e) {
                if (e.kind == PointerDeviceKind.mouse && e.buttons == kMiddleMouseButton) {
                  _middlePointer = e.pointer;
                }
              },
              onPointerMove: (e) {
                if (e.pointer == _middlePointer) _panBy(e.delta);
              },
              onPointerUp: (e) {
                if (e.pointer == _middlePointer) _middlePointer = null;
              },
              child: SizedBox(
                width: c.maxWidth,
                height: total,
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    for (var i = 0; i < _slots.length; i++)
                      _pageBlock(context, i, pageW, pageH, headerH, gap, penArgb),
                    SizedBox(
                      height: endH,
                      child: Center(
                        child: OutlinedButton.icon(
                          key: const ValueKey('nb-add-page-end'),
                          onPressed: widget.session.addPage,
                          icon: const Icon(Icons.add),
                          label: const Text('Página'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _pageBlock(
    BuildContext context,
    int i,
    double pageW,
    double pageH,
    double headerH,
    double gap,
    int penArgb,
  ) {
    final org = context.org;
    final slot = _slots[i];
    return SizedBox(
      width: pageW,
      height: headerH + pageH + gap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: headerH,
            child: Row(
              children: [
                Text(
                  'Página ${i + 1}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: i == _active ? org.accentText : org.inkMuted,
                  ),
                ),
                const Spacer(),
                IconButton(
                  key: ValueKey('nb-page-dup-$i'),
                  tooltip: 'Duplicar página',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.copy_all_outlined, size: 20),
                  onPressed: () => widget.session.duplicatePage(i),
                ),
                IconButton(
                  key: ValueKey('nb-page-del-$i'),
                  tooltip: 'Apagar página',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: _slots.length > 1 ? () => _deletePage(i) : null,
                ),
              ],
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: i == _active ? org.accent : org.line),
              boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2))],
            ),
            child: SizedBox(
              width: pageW,
              height: pageH,
              child: FittedBox(
                fit: BoxFit.fill,
                child: InkPageView(
                  index: i,
                  doc: slot.doc,
                  background: slot.background,
                  settings: _settings,
                  penArgb: penArgb,
                  selection: i == _selPage ? _selIds : const {},
                  imageStore: widget.session.images,
                  onEdit: (b, a) => _commit(i, b, a),
                  onSelectionChanged: (ids) => setState(() {
                    _selPage = ids.isEmpty ? -1 : i;
                    _selIds = ids;
                  }),
                  onActivate: () {
                    if (_active != i) setState(() => _active = i);
                  },
                  onTextTap: (at, existing) => _editText(i, at, existing),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Diálogos
// ---------------------------------------------------------------------------

class _TextResult {
  const _TextResult(this.text, {this.delete = false});
  final String text;
  final bool delete;
}

class _TextDialog extends StatefulWidget {
  const _TextDialog({required this.initial, required this.canDelete});
  final String initial;
  final bool canDelete;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final TextEditingController _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Texto'),
      content: TextField(
        key: const ValueKey('nb-text-field'),
        controller: _c,
        autofocus: true,
        minLines: 2,
        maxLines: 6,
        decoration: const InputDecoration(hintText: 'Digite o texto'),
      ),
      actions: [
        if (widget.canDelete)
          TextButton(
            key: const ValueKey('nb-text-delete'),
            onPressed: () => Navigator.pop(context, const _TextResult('', delete: true)),
            child: const Text('Apagar'),
          ),
        TextButton(
          key: const ValueKey('nb-text-cancel'),
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const ValueKey('nb-text-ok'),
          onPressed: () => Navigator.pop(context, _TextResult(_c.text)),
          child: const Text('Ok'),
        ),
      ],
    );
  }
}

class _ColorDialog extends StatefulWidget {
  const _ColorDialog({required this.initial});
  final Color initial;

  @override
  State<_ColorDialog> createState() => _ColorDialogState();
}

class _ColorDialogState extends State<_ColorDialog> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);

  @override
  Widget build(BuildContext context) {
    final color = _hsv.toColor();
    return AlertDialog(
      title: const Text('Outra cor'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 36,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.org.line),
            ),
          ),
          _slider('nb-hue', 'Matiz', _hsv.hue, 360, (v) => _hsv = _hsv.withHue(v)),
          _slider('nb-sat', 'Saturação', _hsv.saturation, 1, (v) => _hsv = _hsv.withSaturation(v)),
          _slider('nb-val', 'Brilho', _hsv.value, 1, (v) => _hsv = _hsv.withValue(v)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          key: const ValueKey('nb-color-ok'),
          onPressed: () => Navigator.pop(context, color),
          child: const Text('Ok'),
        ),
      ],
    );
  }

  Widget _slider(String key, String label, double v, double max, void Function(double) set) => Row(
    children: [
      SizedBox(width: 78, child: Text(label)),
      Expanded(
        child: Slider(
          key: ValueKey(key),
          value: v.clamp(0, max),
          max: max,
          onChanged: (x) => setState(() => set(x)),
        ),
      ),
    ],
  );
}
