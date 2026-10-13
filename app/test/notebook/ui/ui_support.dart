import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide TextBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/core/notebook_core.dart';
import 'package:organizacional/notebook/ui/notebook_screen.dart';
import 'package:organizacional/ui/org_theme.dart';

/// PNG 1x1 válido.
final Uint8List kPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0,
  0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99, 0x3D, 0x1D, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

class FakeImageStore implements NotebookImageStore {
  final List<({Uint8List bytes, String ext})> uploads = [];
  final List<String> loads = [];

  @override
  Future<String> upload(Uint8List bytes, String ext) async {
    uploads.add((bytes: bytes, ext: ext));
    return 'u/n/img-${uploads.length}.$ext';
  }

  @override
  Future<ImageProvider> load(String path) async {
    loads.add(path);
    return MemoryImage(kPng);
  }
}

/// Sessão falsa em memória: guarda o que a tela manda e repete `pages`.
///
/// As operações por página recebem o **id** da página (como o contrato real);
/// por conveniência dos testes antigos também aceitam o índice (`int`).
class FakeSession implements NotebookSession {
  FakeSession({int pageCount = 1, List<PageDoc>? docs}) {
    for (var i = 0; i < pageCount; i++) {
      _pages.add(
        NotebookPageState(
          id: 'p${_seq++}',
          idx: i,
          background: PageBackground.lined,
          doc: docs != null && i < docs.length ? docs[i] : PageDoc.empty,
        ),
      );
    }
  }

  int _seq = 0;
  final List<NotebookPageState> _pages = [];
  final _pagesCtl = StreamController<List<NotebookPageState>>.broadcast();
  final _statusCtl = StreamController<SaveStatus>.broadcast();
  SaveStatus _status = SaveStatus.saved;
  final List<({int idx, String id, PageDoc doc})> updates = [];

  @override
  final FakeImageStore images = FakeImageStore();

  List<NotebookPageState> get current => List.unmodifiable(_pages);
  PageDoc docOf(int i) => _pages[i].doc;
  String idOf(int i) => _pages[i].id;
  int indexOfId(String id) => _pages.indexWhere((p) => p.id == id);

  int _at(Object key) => key is int ? key : indexOfId(key as String);

  void _reindex() {
    for (var i = 0; i < _pages.length; i++) {
      _pages[i] = _pages[i].copyWith(idx: i);
    }
  }

  @override
  Stream<List<NotebookPageState>> get pages =>
      Stream.multi((c) {
        c.add(List.of(_pages));
        final sub = _pagesCtl.stream.listen(c.add);
        c.onCancel = sub.cancel;
      });

  @override
  SaveStatus get status => _status;

  @override
  Stream<SaveStatus> get statusChanges => _statusCtl.stream;

  void setStatus(SaveStatus s) {
    _status = s;
    _statusCtl.add(s);
  }

  void _emit() => _pagesCtl.add(List.of(_pages));

  /// Simula chegada de página mais nova vinda de outro aparelho.
  void remoteDoc(int idx, PageDoc doc) {
    _pages[idx] = _pages[idx].copyWith(doc: doc);
    _emit();
  }

  /// Simula uma página nova inserida por outro aparelho na posição [at].
  String remoteInsert(int at, {PageDoc? doc}) {
    final id = 'r${_seq++}';
    _pages.insert(
      at,
      NotebookPageState(id: id, idx: at, background: PageBackground.lined, doc: doc ?? PageDoc.empty),
    );
    _reindex();
    _emit();
    return id;
  }

  /// Simula outro aparelho trocando o aviso de uma página (página grande, versão nova…).
  void remoteNotice(int idx, PageNotice notice) {
    _pages[idx] = _pages[idx].copyWith(notice: notice);
    _emit();
  }

  @override
  void updatePage(Object id, PageDoc doc) {
    final i = _at(id);
    if (i < 0) return;
    updates.add((idx: i, id: _pages[i].id, doc: doc));
    _pages[i] = _pages[i].copyWith(doc: doc);
  }

  @override
  void addPage({PageBackground background = PageBackground.lined}) {
    _pages.add(
      NotebookPageState(
        id: 'p${_seq++}',
        idx: _pages.length,
        background: background,
        doc: PageDoc.empty,
      ),
    );
    _emit();
  }

  @override
  void deletePage(Object id) {
    final i = _at(id);
    if (i < 0) return;
    _pages.removeAt(i);
    _reindex();
    _emit();
  }

  @override
  void duplicatePage(Object id) {
    final i = _at(id);
    if (i < 0) return;
    _pages.insert(i + 1, _pages[i].copyWith(id: 'p${_seq++}'));
    _reindex();
    _emit();
  }

  @override
  void setBackground(Object id, PageBackground background) {
    final i = _at(id);
    if (i < 0) return;
    _pages[i] = _pages[i].copyWith(background: background);
    _emit();
  }
}

Future<void> setSurface(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> pumpNotebook(
  WidgetTester tester,
  FakeSession session, {
  Size size = const Size(800, 1300),
  Future<PickedImage?> Function()? pickImage,
}) async {
  await setSurface(tester, size);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildOrgTheme(orgThemes.first, googleFonts: false),
      home: NotebookScreen(
        noteId: 'n1',
        session: session,
        title: 'Meu caderno',
        pickImage: pickImage,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// Posição global do ponto [u] (unidades de página) da página [idx].
Offset pagePoint(WidgetTester tester, Offset u, {int idx = 0}) {
  final r = tester.getRect(find.byKey(ValueKey('nb-page-$idx')));
  return r.topLeft + Offset(u.dx / pageWidth * r.width, u.dy / pageHeight * r.height);
}

int _nextPointer = 100;

/// Simula um ponteiro com [kind], pressão e botões. Todas as posições são
/// em unidades de página.
class SimPointer {
  SimPointer(this.tester, this.kind, {this.idx = 0, this.buttons = 0})
    : id = _nextPointer++;

  final WidgetTester tester;
  final PointerDeviceKind kind;
  final int idx;
  final int buttons;
  final int id;
  Offset _last = Offset.zero;
  bool isDown = false;

  Offset _g(Offset u) => pagePoint(tester, u, idx: idx);

  int get _downButtons {
    if (buttons != 0) return buttons;
    if (kind == PointerDeviceKind.mouse) return kPrimaryMouseButton;
    if (kind == PointerDeviceKind.touch) return kPrimaryButton;
    if (kind == PointerDeviceKind.stylus) return kPrimaryButton;
    return 0;
  }

  Future<void> down(
    Offset u, {
    double pressure = 0.5,
    double pressureMin = 0,
    double pressureMax = 1,
  }) async {
    _last = _g(u);
    isDown = true;
    await tester.sendEventToBinding(
      PointerAddedEvent(pointer: id, kind: kind, position: _last, pressureMin: pressureMin, pressureMax: pressureMax),
    );
    await tester.sendEventToBinding(
      PointerDownEvent(
        pointer: id,
        kind: kind,
        position: _last,
        buttons: _downButtons,
        pressure: pressure,
        pressureMin: pressureMin,
        pressureMax: pressureMax,
      ),
    );
  }

  Future<void> move(
    Offset u, {
    double pressure = 0.5,
    double pressureMin = 0,
    double pressureMax = 1,
  }) async {
    final g = _g(u);
    await tester.sendEventToBinding(
      PointerMoveEvent(
        pointer: id,
        kind: kind,
        position: g,
        delta: g - _last,
        buttons: _downButtons,
        pressure: pressure,
        pressureMin: pressureMin,
        pressureMax: pressureMax,
      ),
    );
    _last = g;
  }

  Future<void> up() async {
    isDown = false;
    await tester.sendEventToBinding(
      PointerUpEvent(pointer: id, kind: kind, position: _last, pressureMin: 0, pressureMax: 1),
    );
    await tester.sendEventToBinding(PointerRemovedEvent(pointer: id, kind: kind, position: _last));
    await tester.pump();
  }

  Future<void> cancel() async {
    isDown = false;
    await tester.sendEventToBinding(PointerCancelEvent(pointer: id, kind: kind, position: _last));
    await tester.pump();
  }

  /// Arrasta por [path] (unidades de página) de ponta a ponta.
  Future<void> drag(
    List<Offset> path, {
    double Function(int i, int n)? pressure,
  }) async {
    double p(int i) => pressure?.call(i, path.length) ?? 0.5;
    await down(path.first, pressure: p(0));
    for (var i = 1; i < path.length; i++) {
      await move(path[i], pressure: p(i));
    }
    await up();
  }
}

/// Retas de [a] a [b] com [n] pontos.
List<Offset> linePath(Offset a, Offset b, {int n = 12}) => [
  for (var i = 0; i < n; i++) Offset.lerp(a, b, i / (n - 1))!,
];

Stroke testStroke(
  String id,
  Offset a,
  Offset b, {
  int n = 20,
  double width = 4,
  PenTool tool = PenTool.pen,
  int argb = 0xFFFFFFFF,
}) => Stroke(
  id: id,
  tool: tool,
  argb: argb,
  width: width,
  points: [
    for (var i = 0; i < n; i++)
      InkPoint(
        a.dx + (b.dx - a.dx) * i / (n - 1),
        a.dy + (b.dy - a.dy) * i / (n - 1),
        0.5,
      ),
  ],
);
