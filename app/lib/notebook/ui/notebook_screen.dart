import 'dart:async';
import 'dart:convert';
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
import '../intelligence/gestures.dart';
import '../intelligence/ink_to_text.dart';
import '../intelligence/straighten.dart';
import '../intelligence/transcript.dart';
import 'ink_page_view.dart';
import 'notebook_intelligence.dart';
import 'notebook_prefs.dart';
import 'notebook_session.dart';
import 'notebook_toolbar.dart';
import 'notebook_tools_menu.dart';
import 'tool_settings.dart';

export 'notebook_intelligence.dart';
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

/// Estado de uma página na tela. Casado com a sessão **pelo id** da página.
class _Slot {
  _Slot(this.id, this.doc, this.background, this.notice);

  final String id;
  PageDoc doc;
  PageBackground background;
  PageNotice notice;
  History history = const History();

  bool get readOnly => notice == PageNotice.newerVersion;
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
    this.prefs = const {},
    this.onPrefsChanged,
    this.intelligence = NotebookIntelligence.off,
  });

  final String noteId;
  final NotebookSession session;
  final String title;

  /// Escolhe uma imagem (padrão: seletor do sistema). Injetável nos testes.
  final Future<PickedImage?> Function()? pickImage;

  /// Favoritos do Caderno (JSON de `user_settings.notebook_prefs`). Quando mudam
  /// (outro aparelho), a barra se atualiza.
  final Map<String, dynamic> prefs;

  /// Chamado com os favoritos novos quando o usuário os edita. Se falhar, a tela
  /// avisa e mantém a edição neste aparelho.
  final Future<void> Function(Map<String, dynamic> prefs)? onPrefsChanged;

  /// Conversão em texto, corretor e gestos (fase 2). Padrão: tudo desligado.
  final NotebookIntelligence intelligence;

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
  late NotebookPrefs _prefs = NotebookPrefs.fromMap(widget.prefs);

  /// Avisa o menu/ajuste rápido abertos (rotas separadas) de que algo mudou.
  final ValueNotifier<int> _rev = ValueNotifier(0);
  void _touch() => _rev.value++;

  /// Página ativa e página da seleção, por id (o índice muda quando a lista muda).
  String? _activeId;
  String? _selPageId;
  Set<String> _selIds = const {};
  PageDoc? _clip;

  final TransformationController _tc = TransformationController();
  final ValueNotifier<double> _zoom = ValueNotifier(1.0);
  final GlobalKey _viewportKey = GlobalKey();
  Size _viewport = Size.zero;
  Size _content = Size.zero;
  EdgeInsets _margin = const EdgeInsets.all(48);
  int? _middlePointer;

  // ---- escrita à mão (fase 2) ----
  NotebookIntelligence get _intel => widget.intelligence;
  StreamSubscription<({String pageId, PageTranscript transcript})>? _transcriptSub;

  /// Palavras sublinhadas pelo corretor, por página (da última transcrição).
  final Map<String, List<SpellMark>> _marks = {};
  final Map<String, int> _markGen = {};

  /// Palavras ignoradas nesta tela antes de o dicionário pessoal voltar atualizado.
  final Set<String> _ignoredHere = {};

  /// Uma conversão em texto em andamento.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tc.addListener(_onTransform);
    _transcriptSub = _intel.transcripts.listen((e) => _refreshMarks(e.pageId, e.transcript));
    _pagesSub = widget.session.pages.listen(_onPages);
    _statusSub = widget.session.statusChanges.listen((s) {
      if (mounted) setState(() => _status = s);
    });
  }

  @override
  void didUpdateWidget(NotebookScreen old) {
    super.didUpdateWidget(old);
    if (jsonEncode(old.prefs) != jsonEncode(widget.prefs)) {
      setState(() => _prefs = NotebookPrefs.fromMap(widget.prefs));
      // Estamos no meio de uma construção: o menu aberto só pode ser avisado depois.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _touch();
      });
    }
    final was = old.intelligence, now = widget.intelligence;
    if (was.transcripts != now.transcripts) {
      _transcriptSub?.cancel();
      _transcriptSub = now.transcripts.listen((e) => _refreshMarks(e.pageId, e.transcript));
    }
    if (was.spellCheck && !now.spellCheck) {
      _marks.clear();
    } else if (!was.spellCheck && now.spellCheck) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refreshAllMarks());
    }
  }

  @override
  void dispose() {
    _rev.dispose();
    _pagesSub?.cancel();
    _statusSub?.cancel();
    _transcriptSub?.cancel();
    _tc.removeListener(_onTransform);
    _tc.dispose();
    _zoom.dispose();
    super.dispose();
  }

  _Slot? _slotById(String? id) {
    if (id == null) return null;
    for (final s in _slots) {
      if (s.id == id) return s;
    }
    return null;
  }

  int _indexOfId(String? id) => id == null ? -1 : _slots.indexWhere((s) => s.id == id);

  /// Índice da página ativa (a primeira, se a ativa sumiu).
  int get _active {
    final i = _indexOfId(_activeId);
    return i >= 0 ? i : 0;
  }

  void _clearSelection() {
    _selIds = const {};
    _selPageId = null;
  }

  void _onTransform() {
    final s = _xScale(_tc.value);
    if (s != _zoom.value) _zoom.value = s;
  }

  // ---- dados --------------------------------------------------------------

  void _onPages(List<NotebookPageState> list) {
    if (!mounted) return;
    final fresh = <String>[];
    setState(() {
      _loaded = true;
      final known = {for (final s in _slots) s.id: s};
      final next = <_Slot>[];
      for (final p in list) {
        final s = known[p.id];
        if (s == null) {
          next.add(_Slot(p.id, p.doc, p.background, p.notice));
          fresh.add(p.id);
          continue;
        }
        s.background = p.background;
        s.notice = p.notice;
        if (!identical(p.doc, s.doc)) {
          final merged = s.doc.merge(p.doc);
          if (merged != s.doc) s.doc = merged;
        }
        next.add(s);
      }
      _slots
        ..clear()
        ..addAll(next);
      if (_slotById(_activeId) == null) _activeId = _slots.isEmpty ? null : _slots.first.id;
      _cleanSelection();
      _marks.removeWhere((id, _) => _slotById(id) == null);
    });
    _touch();
    for (final id in fresh) {
      final t = _intel.transcriptOf?.call(id);
      if (t != null) unawaited(_refreshMarks(id, t));
    }
  }

  void _cleanSelection() {
    if (_selIds.isEmpty) return;
    final page = _slotById(_selPageId);
    if (page == null) {
      _clearSelection();
      return;
    }
    final doc = page.doc;
    final keep = {for (final id in _selIds) if (doc.contains(id)) id};
    if (keep.length != _selIds.length) _selIds = keep;
  }

  void _commit(String id, PageDoc before, PageDoc after) {
    final s = _slotById(id);
    if (s == null || s.readOnly || identical(before, after)) return;
    // Itens que nasceram e morreram dentro do gesto (pedaços da borracha parcial)
    // não precisam de tombstone: nenhum outro aparelho os viu.
    final settled = after.withoutEphemeralTombstones(before);
    setState(() {
      s.history = s.history.record(before, settled);
      s.doc = identical(s.doc, before) ? settled : s.doc.merge(settled);
      _activeId = id;
    });
    widget.session.updatePage(id, s.doc);
  }

  void _undoRedo({required bool undo}) {
    if (_slots.isEmpty) return;
    final s = _slots[_active];
    if (s.readOnly) return;
    final step = undo ? s.history.undo(s.doc) : s.history.redo(s.doc);
    if (step == null) return;
    setState(() {
      s.history = step.history;
      s.doc = step.doc;
      _clearSelection();
    });
    widget.session.updatePage(s.id, s.doc);
  }

  // ---- ferramentas --------------------------------------------------------

  int _penArgb(OrgThemeSpec org) => _settings.argb ?? org.ink.toARGB32();

  void _setSettings(ToolSettings s) {
    setState(() {
      if (s.kind != _settings.kind && s.kind != ToolKind.lasso) _clearSelection();
      _settings = s;
    });
    _touch();
  }

  /// Aplica uma cor à caneta; com borracha/laço ativos volta para a caneta.
  void _applyColor(int argb) {
    final k = _settings.kind;
    _setSettings(
      _settings.copyWith(argb: argb, kind: k == ToolKind.eraser || k == ToolKind.lasso ? ToolKind.draw : k),
    );
  }

  // ---- favoritos ----------------------------------------------------------

  void _updatePrefs(NotebookPrefs next) {
    setState(() => _prefs = next);
    _touch();
    final save = widget.onPrefsChanged;
    if (save == null) return;
    final messenger = ScaffoldMessenger.of(context);
    save(next.toMap()).catchError((Object _) {
      messenger.showSnackBar(const SnackBar(content: Text('Não foi possível sincronizar os favoritos.')));
    });
  }

  void _tapFavoritePen(int i) {
    if (i < 0 || i >= _prefs.pens.length) return;
    final pen = _prefs.pens[i];
    final org = context.org;
    final selected = _settings.kind == ToolKind.draw && pen.sameAs(FavoritePen.fromSettings(_settings), org);
    if (selected) {
      _showPanel(
        (ctx) => NotebookQuickAdjust(
          settings: _settings,
          favoriteColors: _prefs.colorsFor(org),
          currentColor: Color(_penArgb(org)),
          onSettings: _setSettings,
          onSave: () {
            Navigator.of(ctx).pop();
            _updatePrefs(_prefs.replacePenAt(i, FavoritePen.fromSettings(_settings)));
          },
        ),
      );
    } else {
      _setSettings(pen.applyTo(_settings));
    }
  }

  void _tapFavoriteColor(int i) {
    final colors = _prefs.colorsFor(context.org);
    if (i >= 0 && i < colors.length) _applyColor(colors[i]);
  }

  void _eraserOptions() => _showPanel(
    (ctx) => NotebookEraserQuick(settings: _settings, onSettings: _setSettings),
  );

  void _openToolsMenu() {
    final org = context.org;
    final palette = notebookPalette(org);
    _showPanel(
      side: true,
      (ctx) {
        final slot = _slots.isEmpty ? null : _slots[_active.clamp(0, _slots.length - 1)];
        return NotebookToolsMenu(
          settings: _settings,
          prefs: _prefs,
          palette: palette,
          currentColor: Color(_penArgb(org)),
          background: slot?.background ?? PageBackground.lined,
          zoom: _zoom,
          canDeletePage: _slots.length > 1,
          onSettings: _setSettings,
          onColor: _applyColor,
          onCustomColor: _pickCustomColor,
          onBackground: (b) => _setBackground(slot, b),
          onAddPage: widget.session.addPage,
          onDuplicatePage: () {
            if (slot != null) widget.session.duplicatePage(slot.id);
          },
          onDeletePage: () {
            if (slot != null) _deletePage(slot.id);
          },
          onInsertImage: _insertImage,
          onZoomIn: () => _zoomBy(1.25),
          onZoomOut: () => _zoomBy(0.8),
          onPrefs: _updatePrefs,
          canConvert: _intel.recognizer.supported && !_busy,
          onConvertPage: slot == null || slot.readOnly ? null : () => unawaited(_convert(slot.id, _allInk(slot.doc))),
          onStraightenPage: slot == null || slot.readOnly
              ? null
              : () {
                  if (_straighten(slot.id, _allInk(slot.doc)) != null) setState(_clearSelection);
                },
          onCopyPageText: slot == null ? null : () => unawaited(_copyPageText(slot.id)),
        );
      },
    );
  }

  void _setBackground(_Slot? slot, PageBackground b) {
    if (slot == null || slot.readOnly) return;
    setState(() => slot.background = b);
    widget.session.setBackground(slot.id, b);
    _touch();
  }

  /// Mostra [content] numa folha inferior (celular) ou, se [side] e a tela é
  /// larga, num painel lateral. O conteúdo é reconstruído a cada [_touch].
  Future<void> _showPanel(Widget Function(BuildContext) content, {bool side = false}) {
    Widget live(BuildContext ctx) => ListenableBuilder(listenable: _rev, builder: (_, _) => content(ctx));
    final wide = MediaQuery.sizeOf(context).width >= 600;
    if (side && wide) {
      return showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Fechar',
        barrierColor: Colors.black38,
        transitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (ctx, _, _) => Align(
          alignment: Alignment.centerRight,
          child: SizedBox(width: 380, height: double.infinity, child: live(ctx)),
        ),
        transitionBuilder: (_, anim, _, child) => SlideTransition(
          position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(
            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      );
    }
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: live,
    );
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
    final page = _slotById(_selPageId);
    if (page == null || _selIds.isEmpty) return;
    setState(() => _clip = extractItems(page.doc, _selIds));
  }

  void _deleteSelection() {
    final page = _slotById(_selPageId);
    if (page == null || _selIds.isEmpty) return;
    final ids = _selIds;
    final before = page.doc;
    setState(_clearSelection);
    _commit(page.id, before, before.without(ids));
  }

  Future<void> _recolorSelection() async {
    final target = _selPageId;
    if (_slotById(target) == null || _selIds.isEmpty) return;
    final org = context.org;
    final c = await showDialog<Color>(
      context: context,
      builder: (_) => _ColorDialog(initial: Color(_penArgb(org))),
    );
    final page = _slotById(target);
    if (c == null || !mounted || page == null || _selPageId != target) return;
    final before = page.doc;
    final r = recolorMapped(before, _selIds, c.toARGB32());
    setState(() => _selIds = {for (final id in _selIds) r.idMap[id] ?? id});
    _commit(page.id, before, r.doc);
  }

  void _pasteClip() {
    final clip = _clip;
    if (clip == null || _slots.isEmpty) return;
    final page = _slots[_active];
    final before = page.doc;
    final r = pasteDocMapped(before, clip, dx: 30, dy: 30);
    setState(() {
      _selPageId = page.id;
      _selIds = r.idMap.values.toSet();
    });
    _commit(page.id, before, r.doc);
  }

  // ---- escrita à mão: gestos, conversão, corretor -------------------------

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  /// Ids dos traços de caneta (não marca-texto) de [ids] em [doc].
  static Set<String> _inkIds(PageDoc doc, Iterable<String> ids) => {
    for (final id in ids)
      if (doc.strokeById(id) case final s? when s.tool != PenTool.highlighter) id,
  };

  static Set<String> _allInk(PageDoc doc) => _inkIds(doc, [for (final s in doc.strokes) s.id]);

  /// Um gesto da página terminou. Com a caneta, o traço novo pode ser um toque
  /// no sublinhado do corretor (abre as sugestões, nada é gravado) ou um gesto de
  /// edição (aplica o gesto no lugar da tinta); senão grava como sempre.
  void _onPageEdit(String pageId, PageDoc before, PageDoc after) {
    final drawn = _drawnStroke(before, after);
    if (drawn != null) {
      if (_isDot(drawn) && _tapWord(pageId, drawn.bounds.center, underlineOnly: true)) return;
      if (_intel.gestures) {
        final g = gestureEdit(before, drawn);
        if (g != null) {
          _commit(pageId, before, g.doc);
          _gestureDone(g.gesture);
          return;
        }
      }
    }
    _commit(pageId, before, after);
  }

  /// O traço que a caneta acabou de acrescentar (e só isso), ou `null`.
  Stroke? _drawnStroke(PageDoc before, PageDoc after) {
    if (_settings.kind != ToolKind.draw) return null;
    if (after.strokes.length != before.strokes.length + 1 ||
        after.deleted.length != before.deleted.length ||
        after.texts.length != before.texts.length ||
        after.images.length != before.images.length) {
      return null;
    }
    for (final s in after.strokes.reversed) {
      if (before.strokeById(s.id) == null) return s;
    }
    return null;
  }

  /// Toque curto da caneta (um pingo).
  static bool _isDot(Stroke s) {
    final b = s.bounds.deflate(s.width / 2);
    return b.width <= 6 && b.height <= 6;
  }

  void _gestureDone(InkGesture g) {
    final text = switch (g) {
      ScratchOut() => 'Apagado com o rabisco',
      InsertSpace() => 'Espaço aberto',
      SplitWord() => 'Palavra separada',
      JoinWords() => 'Palavras juntadas',
    };
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const ValueKey('nb-gesture-done'),
          content: Text(text),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(label: 'Desfazer', onPressed: () => _undoRedo(undo: true)),
        ),
      );
  }

  /// Converte a escrita de [ids] da página [pageId] em texto. Avisa quando falta o
  /// modelo ou nada foi reconhecido.
  Future<InkToTextResult?> _convert(String pageId, Set<String> ids) async {
    final rec = _intel.recognizer;
    if (!rec.supported || _busy || ids.isEmpty) return null;
    setState(() => _busy = true);
    try {
      bool ready;
      try {
        ready = await rec.isModelReady();
      } catch (_) {
        ready = false;
      }
      if (!ready) {
        _snack('Baixe o modelo de escrita em Ajustes → Escrita à mão.');
        return null;
      }
      final page = _slotById(pageId);
      if (page == null || page.readOnly) return null;
      final before = page.doc;
      final r = await convertInkToText(before, ids, rec);
      if (!mounted || _slotById(pageId) == null) return null;
      if (r.converted == 0) {
        _snack('Não deu para reconhecer a escrita.');
        return r;
      }
      _commit(pageId, before, r.doc);
      if (r.failed > 0) {
        _snack(r.failed == 1
            ? '1 linha não foi reconhecida e ficou como escrita.'
            : '${r.failed} linhas não foram reconhecidas e ficaram como escrita.');
      }
      return r;
    } catch (_) {
      _snack('Não foi possível converter a escrita.');
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _convertSelection() async {
    final page = _slotById(_selPageId);
    if (page == null || _selIds.isEmpty) return;
    final r = await _convert(page.id, _inkIds(page.doc, _selIds));
    if (r == null || r.textIds.isEmpty || !mounted || _slotById(page.id) == null) return;
    final keep = {for (final id in _selIds) if (page.doc.contains(id)) id};
    setState(() {
      _selPageId = page.id;
      _selIds = {...keep, ...r.textIds};
    });
  }

  /// Endireita a escrita de [ids]; devolve os ids que a seleção deve ter depois.
  Set<String>? _straighten(String pageId, Set<String> ids) {
    final page = _slotById(pageId);
    if (page == null || page.readOnly) return null;
    final before = page.doc;
    final after = straighten(before, _inkIds(before, ids), newInkId);
    if (identical(after, before)) {
      _snack('A escrita já está reta.');
      return null;
    }
    _commit(pageId, before, after);
    return {
      for (final id in ids)
        if (after.contains(id)) id,
      for (final s in after.strokes)
        if (before.strokeById(s.id) == null) s.id,
    };
  }

  void _straightenSelection() {
    final pageId = _selPageId;
    if (pageId == null || _selIds.isEmpty) return;
    final next = _straighten(pageId, _selIds);
    if (next != null) setState(() => _selIds = next);
  }

  Future<void> _copyPageText(String pageId) async {
    final page = _slotById(pageId);
    if (page == null) return;
    var text = _intel.recognizedTextOf?.call(pageId) ?? _intel.transcriptOf?.call(pageId)?.text ?? '';
    final rec = _intel.recognizer;
    if (text.trim().isEmpty && rec.supported) {
      try {
        if (await rec.isModelReady()) text = (await transcribe(page.doc, rec)).text;
      } catch (_) {
        // Sem texto: o aviso abaixo cobre.
      }
    }
    if (!mounted) return;
    if (text.trim().isEmpty) {
      _snack('Ainda não há texto reconhecido nesta página.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    _snack('Texto da página copiado.');
  }

  Set<String> get _ignored => {..._intel.ignoredWords, ..._ignoredHere};

  /// Recalcula o sublinhado da página a partir de [t] (a transcrição mais recente).
  Future<void> _refreshMarks(String pageId, PageTranscript t) async {
    if (!_intel.spellCheck || !mounted) return;
    final slot = _slotById(pageId);
    if (slot == null) return;
    final gen = (_markGen[pageId] ?? 0) + 1;
    _markGen[pageId] = gen;
    final marks = await findSpellMarks(slot.doc, t, _intel.spellChecker, ignored: _ignored);
    if (!mounted || _markGen[pageId] != gen) return;
    setState(() => _marks[pageId] = marks);
  }

  void _refreshAllMarks() {
    if (!mounted) return;
    for (final s in _slots) {
      final t = _intel.transcriptOf?.call(s.id);
      if (t != null) unawaited(_refreshMarks(s.id, t));
    }
  }

  /// Marcas ainda válidas: a palavra continua na página e não foi ignorada.
  List<SpellMark> _visibleMarks(_Slot s) {
    if (!_intel.spellCheck) return const [];
    final all = _marks[s.id];
    if (all == null || all.isEmpty) return const [];
    final ignored = _ignored;
    return [
      for (final m in all)
        if (!ignored.contains(ignoreKey(m.text)) && m.word.strokeIds.every((id) => s.doc.strokeById(id) != null)) m,
    ];
  }

  /// Toque em [at]: se cai numa palavra sublinhada, abre as sugestões. Com a
  /// caneta só vale o toque **no sublinhado** (abaixo da palavra), para não
  /// roubar o pingo do "i" nem a pontuação.
  bool _tapWord(String pageId, Offset at, {required bool underlineOnly}) {
    final slot = _slotById(pageId);
    if (slot == null || slot.readOnly) return false;
    for (final m in _visibleMarks(slot)) {
      final b = m.bounds;
      final zone = underlineOnly ? Rect.fromLTRB(b.left - 4, b.bottom - 4, b.right + 4, b.bottom + 16) : b.inflate(6);
      if (zone.contains(at)) {
        unawaited(_showSuggestions(pageId, m));
        return true;
      }
    }
    return false;
  }

  static const _kIgnore = '\u0000ignorar';

  Future<void> _showSuggestions(String pageId, SpellMark m) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        final text = Theme.of(ctx).textTheme;
        return SafeArea(
          child: SingleChildScrollView(
            key: const ValueKey('nb-spell-sheet'),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  title: Text('“${m.text}”', style: text.titleMedium),
                  subtitle: Text(
                    m.suggestions.isEmpty ? 'O corretor não tem sugestões.' : 'Toque numa sugestão para trocar a palavra.',
                  ),
                ),
                for (var i = 0; i < m.suggestions.length && i < 6; i++)
                  ListTile(
                    key: ValueKey('nb-spell-sug-$i'),
                    leading: const Icon(Icons.spellcheck),
                    title: Text(m.suggestions[i]),
                    onTap: () => Navigator.pop(ctx, m.suggestions[i]),
                  ),
                ListTile(
                  key: const ValueKey('nb-spell-ignore'),
                  leading: const Icon(Icons.block),
                  title: const Text('Ignorar'),
                  subtitle: const Text('Não marcar mais esta palavra neste aparelho'),
                  onTap: () => Navigator.pop(ctx, _kIgnore),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (choice == null || !mounted) return;
    if (choice == _kIgnore) {
      final key = ignoreKey(m.text);
      setState(() => _ignoredHere.add(key));
      _intel.onIgnoreWord?.call(key);
      return;
    }
    final slot = _slotById(pageId);
    if (slot == null || slot.readOnly) return;
    final before = slot.doc;
    if (!m.word.strokeIds.every((id) => before.strokeById(id) != null)) return;
    final r = replaceWordWithText(before, m.line, m.word, choice);
    setState(() => _marks[pageId] = [for (final x in _marks[pageId] ?? const <SpellMark>[]) if (!identical(x, m)) x]);
    _commit(pageId, before, r.doc);
  }

  // ---- texto --------------------------------------------------------------

  Future<void> _editText(String pageId, Offset at, TextBox? existing) async {
    final org = context.org;
    final res = await showDialog<_TextResult>(
      context: context,
      builder: (_) => _TextDialog(initial: existing?.text ?? '', canDelete: existing != null),
    );
    final page = _slotById(pageId);
    if (res == null || !mounted || page == null) return;
    final before = page.doc;
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
    _commit(pageId, before, after);
  }

  // ---- imagem -------------------------------------------------------------

  Future<void> _insertImage() async {
    if (_slots.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final pageId = _slots[_active].id; // fixa a página já: a lista pode mudar durante o envio
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
      final page = _slotById(pageId);
      if (!mounted || page == null) return; // a página foi apagada enquanto isso
      final bw = math.min(500.0, w.toDouble());
      final bh = bw * h / math.max(w, 1);
      final before = page.doc;
      final box = ImageBox(
        id: newInkId(),
        x: (pageWidth - bw) / 2,
        y: 160,
        w: bw,
        h: math.min(bh, pageHeight - 200),
        path: path,
      );
      _commit(pageId, before, before.withImage(box));
      setState(() {
        _selPageId = pageId;
        _selIds = {box.id};
        _settings = _settings.copyWith(kind: ToolKind.lasso);
      });
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Não foi possível enviar a imagem.')));
    }
  }

  // ---- páginas ------------------------------------------------------------

  Future<void> _deletePage(String pageId) async {
    final number = _indexOfId(pageId) + 1;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Apagar a página $number?'),
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
    final idx = _indexOfId(pageId);
    if (ok != true || !mounted || idx < 0) return;
    setState(() {
      _slots.removeAt(idx);
      if (_selPageId == pageId) _clearSelection();
      if (_activeId == pageId) {
        _activeId = _slots.isEmpty ? null : _slots[idx.clamp(0, _slots.length - 1)].id;
      }
    });
    widget.session.deletePage(pageId);
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
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _buildViewer(context)),
          if (_settings.kind == ToolKind.lasso && (_selIds.isNotEmpty || _clip != null))
            _selectionBar(context),
          _toolbarFor(org, palette, slot),
        ],
      ),
    );
  }

  // A barra é reaproveitada (mesma instância) enquanto nada que ela mostra mudar: o Flutter
  // então pula a reconstrução dela a cada traço, que era a maior parte do travamento.
  Widget? _toolbar;
  Object? _toolbarKey;

  Widget _toolbarFor(OrgThemeSpec org, List<Color> palette, _Slot? slot) {
    final canUndo = slot != null && slot.history.canUndo;
    final canRedo = slot != null && slot.history.canRedo;
    final key = (
      _settings,
      _prefs,
      org,
      Object.hashAll(palette),
      _penArgb(org),
      slot?.background ?? PageBackground.lined,
      _zoom,
      canUndo,
      canRedo,
    );
    if (_toolbar == null || _toolbarKey != key) {
      _toolbarKey = key;
      _toolbar = NotebookToolbar(
        settings: _settings,
        prefs: _prefs,
        palette: palette,
        currentColor: Color(_penArgb(org)),
        background: slot?.background ?? PageBackground.lined,
        zoom: _zoom,
        onSettings: _setSettings,
        onCustomColor: _pickCustomColor,
        // Busca a página ativa na hora (a barra pode ser de um build anterior).
        onBackground: (b) => _setBackground(_activeSlot, b),
        onAddPage: widget.session.addPage,
        onInsertImage: _insertImage,
        onZoomIn: () => _zoomBy(1.25),
        onZoomOut: () => _zoomBy(0.8),
        onUndo: canUndo ? () => _undoRedo(undo: true) : null,
        onRedo: canRedo ? () => _undoRedo(undo: false) : null,
        onMore: _openToolsMenu,
        onFavoritePen: _tapFavoritePen,
        onFavoriteColor: _tapFavoriteColor,
        onEraserOptions: _eraserOptions,
      );
    }
    return _toolbar!;
  }

  _Slot? get _activeSlot => _slots.isEmpty ? null : _slots[_active.clamp(0, _slots.length - 1)];

  String _statusLabel(SaveStatus s) => switch (s) {
    SaveStatus.saving => 'Salvando…',
    SaveStatus.saved => 'Salvo',
    SaveStatus.offline => 'Sem conexão (salvo no aparelho)',
    SaveStatus.problem => 'Algumas alterações não puderam ser salvas',
    SaveStatus.noteDeleted => 'Este caderno foi excluído em outro aparelho',
  };

  Widget _selectionBar(BuildContext context) {
    final org = context.org;
    final has = _selIds.isNotEmpty;
    final selPage = _slotById(_selPageId);
    final hasInk = selPage != null && !selPage.readOnly && _inkIds(selPage.doc, _selIds).isNotEmpty;
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
            b('nb-sel-straighten', Icons.format_align_left, 'Endireitar', hasInk ? _straightenSelection : null),
            if (_intel.recognizer.supported)
              b('nb-sel-convert', Icons.text_fields, 'Converter em texto', hasInk && !_busy ? _convertSelection : null)
            else
              Center(
                key: const ValueKey('nb-sel-convert-hint'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'Converter em texto: disponível no Android',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: org.inkMuted),
                  ),
                ),
              ),
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

  Widget? _spellOverlay(BuildContext context, int i, _Slot slot) {
    final marks = _visibleMarks(slot);
    if (marks.isEmpty) return null;
    return CustomPaint(
      key: ValueKey('nb-spell-$i'),
      painter: _SpellPainter(marks, Theme.of(context).colorScheme.error),
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
      key: ValueKey('nb-block-${slot.id}'),
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
                    color: slot.id == _slots[_active].id ? org.accentText : org.inkMuted,
                  ),
                ),
                const Spacer(),
                IconButton(
                  key: ValueKey('nb-page-dup-$i'),
                  tooltip: 'Duplicar página',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.copy_all_outlined, size: 20),
                  onPressed: () => widget.session.duplicatePage(slot.id),
                ),
                IconButton(
                  key: ValueKey('nb-page-del-$i'),
                  tooltip: 'Apagar página',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: _slots.length > 1 ? () => _deletePage(slot.id) : null,
                ),
              ],
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: slot.id == _slots[_active].id ? org.accent : org.line),
              boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2))],
            ),
            child: SizedBox(
              width: pageW,
              height: pageH,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: slot.readOnly,
                      child: FittedBox(
                        fit: BoxFit.fill,
                        child: InkPageView(
                          index: i,
                          doc: slot.doc,
                          background: slot.background,
                          settings: _settings,
                          penArgb: penArgb,
                          selection: slot.id == _selPageId ? _selIds : const {},
                          imageStore: widget.session.images,
                          onEdit: (b, a) => _onPageEdit(slot.id, b, a),
                          onInkTap: (at) => _tapWord(slot.id, at, underlineOnly: false),
                          overlay: _spellOverlay(context, i, slot),
                          onSelectionChanged: (ids) => setState(() {
                            _selPageId = ids.isEmpty ? null : slot.id;
                            _selIds = ids;
                          }),
                          onActivate: () {
                            if (_activeId != slot.id) setState(() => _activeId = slot.id);
                          },
                          onTextTap: (at, existing) => _editText(slot.id, at, existing),
                        ),
                      ),
                    ),
                  ),
                  if (slot.notice != PageNotice.none)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      child: IgnorePointer(child: _NoticeBanner(notice: slot.notice)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sublinhado ondulado das palavras que o corretor marcou (unidades de página).
class _SpellPainter extends CustomPainter {
  _SpellPainter(this.marks, this.color);

  final List<SpellMark> marks;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final m in marks) {
      final b = m.bounds;
      final y = b.bottom + 4;
      final path = Path()..moveTo(b.left, y);
      var x = b.left;
      var up = true;
      while (x < b.right) {
        final nx = math.min(x + 4, b.right);
        path.quadraticBezierTo((x + nx) / 2, y + (up ? -3 : 3), nx, y);
        x = nx;
        up = !up;
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_SpellPainter old) => old.color != color || !listEquals(old.marks, marks);
}

/// Faixa de aviso no topo de uma página.
class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({required this.notice});

  final PageNotice notice;

  static String text(PageNotice n) => switch (n) {
    PageNotice.none => '',
    PageNotice.nearLimit => 'Esta página está quase no limite de tamanho — considere continuar em outra página',
    PageNotice.tooLarge => 'Página grande demais — divida em outra página',
    PageNotice.newerVersion => 'Esta página foi feita numa versão mais nova do app',
  };

  @override
  Widget build(BuildContext context) {
    final org = context.org;
    final severe = notice != PageNotice.nearLimit;
    return Container(
      key: ValueKey('nb-notice-${notice.name}'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: severe ? org.accentSoft : org.accentSoft.withValues(alpha: 0.7),
      child: Text(
        text(notice),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: org.accentText),
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
