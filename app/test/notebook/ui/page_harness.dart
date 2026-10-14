import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide TextBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/core/notebook_core.dart';
import 'package:organizacional/notebook/ui/ink_page_view.dart';
import 'package:organizacional/notebook/ui/notebook_session.dart' show NotebookImageStore;
import 'package:organizacional/notebook/ui/pen_activity.dart';
import 'package:organizacional/notebook/ui/tool_settings.dart';
import 'package:organizacional/ui/org_theme.dart';

/// PNG 1x1 válido.
final Uint8List kTinyPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0,
  0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99, 0x3D, 0x1D, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

/// GIF 1x1 com 2 quadros (100 ms cada) e laço infinito.
Uint8List buildTwoFrameGif() {
  const frame = [
    0x21, 0xF9, 0x04, 0x00, 0x0A, 0x00, 0x00, 0x00, // controle: 100 ms
    0x2C, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, // descritor 1x1
    0x02, 0x02, 0x44, 0x01, 0x00, // dados LZW
  ];
  return Uint8List.fromList([
    ...'GIF89a'.codeUnits,
    0x01, 0x00, 0x01, 0x00, 0x80, 0x00, 0x00, // tela 1x1, tabela global de 2 cores
    0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF,
    0x21, 0xFF, 0x0B, ...'NETSCAPE2.0'.codeUnits, 0x03, 0x01, 0x00, 0x00, 0x00, // laço
    ...frame,
    ...frame,
    0x3B,
  ]);
}

class TinyImageStore implements NotebookImageStore {
  TinyImageStore({this.gif = false});
  final bool gif;

  @override
  Future<String> upload(Uint8List bytes, String ext) async => 'x.$ext';

  @override
  Future<ImageProvider> load(String path) async => MemoryImage(gif ? buildTwoFrameGif() : kTinyPng);
}

/// Páginas empilhadas dentro de um `InteractiveViewer` (como a tela do caderno),
/// com relógio da caneta controlável. Não depende da tela nem da sessão.
class PageHarness {
  PageHarness._(this.tester, this.docs, this.settings, this.debugInput, this.pageCount, this.gif);

  final WidgetTester tester;
  final List<PageDoc> docs;
  ToolSettings settings;
  final bool debugInput;
  final int pageCount;
  final bool gif;
  final TransformationController tc = TransformationController();
  Duration clock = Duration.zero;
  late final PenActivity pen = PenActivity(now: () => clock);
  final List<({int page, PageDoc before, PageDoc after})> edits = [];
  final List<Offset> textTaps = [];
  late StateSetter _set;

  static const double pageW = 400, pageH = 566, gap = 24;

  static Future<PageHarness> pump(
    WidgetTester tester, {
    int pages = 1,
    List<PageDoc>? docs,
    ToolSettings settings = const ToolSettings(),
    bool debugInput = false,
    bool gif = false,
    Size surface = const Size(800, 1300),
  }) async {
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final h = PageHarness._(
      tester,
      [for (var i = 0; i < pages; i++) docs != null && i < docs.length ? docs[i] : PageDoc.empty],
      settings,
      debugInput,
      pages,
      gif,
    );
    addTearDown(h.tc.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildOrgTheme(orgThemes.first, googleFonts: false),
        home: Scaffold(
          body: PenActivityScope(
            activity: h.pen,
            child: StatefulBuilder(
              builder: (context, set) {
                h._set = set;
                return InteractiveViewer(
                  transformationController: h.tc,
                  constrained: false,
                  boundaryMargin: const EdgeInsets.all(double.infinity),
                  minScale: 0.5,
                  maxScale: 4,
                  child: Column(
                    children: [
                      for (var i = 0; i < h.pageCount; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: gap),
                          child: SizedBox(
                            width: pageW,
                            height: pageH,
                            child: FittedBox(
                              fit: BoxFit.fill,
                              child: InkPageView(
                                index: i,
                                doc: h.docs[i],
                                background: PageBackground.lined,
                                settings: h.settings,
                                penArgb: 0xFFFFFFFF,
                                selection: const {},
                                imageStore: TinyImageStore(gif: h.gif),
                                debugInput: h.debugInput,
                                onEdit: (b, a) {
                                  h.edits.add((page: i, before: b, after: a));
                                  h._set(() => h.docs[i] = a);
                                },
                                onSelectionChanged: (_) {},
                                onActivate: () {},
                                onTextTap: (at, _) => h.textTaps.add(at),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return h;
  }

  Future<void> setSettings(ToolSettings s) async {
    _set(() => settings = s);
    await tester.pump();
  }

  /// Posição global do ponto [u] (unidades de página) da página [i].
  Offset g(Offset u, {int page = 0}) {
    final r = tester.getRect(find.byKey(ValueKey('nb-page-$page')));
    return r.topLeft + Offset(u.dx / pageWidth * r.width, u.dy / pageHeight * r.height);
  }

  Matrix4 get view => tc.value.clone();
  double get tx => tc.value.getTranslation().x;
  double get ty => tc.value.getTranslation().y;
}

int _ptr = 5000;

/// Um ponteiro sintético em coordenadas **globais**.
class P {
  P(this.tester, this.kind, {this.buttons = 0}) : id = _ptr++;

  final WidgetTester tester;
  final PointerDeviceKind kind;
  int buttons;
  final int id;
  Offset _at = Offset.zero;
  bool _added = false;

  int get _downButtons {
    if (buttons != 0) return buttons;
    return kind == PointerDeviceKind.mouse || kind == PointerDeviceKind.touch || kind == PointerDeviceKind.stylus
        ? kPrimaryButton
        : 0;
  }

  Future<void> _add(Offset at) async {
    if (_added) return;
    _added = true;
    await tester.sendEventToBinding(PointerAddedEvent(pointer: id, kind: kind, position: at));
  }

  Future<void> hover(Offset at) async {
    await _add(at);
    await tester.sendEventToBinding(PointerHoverEvent(pointer: id, kind: kind, position: at, delta: at - _at));
    _at = at;
  }

  Future<void> down(Offset at, {double pressure = 0.5, double radiusMajor = 0}) async {
    await _add(at);
    _at = at;
    await tester.sendEventToBinding(
      PointerDownEvent(
        pointer: id,
        kind: kind,
        position: at,
        buttons: _downButtons,
        pressure: pressure,
        pressureMin: 0,
        pressureMax: 1,
        radiusMajor: radiusMajor,
      ),
    );
  }

  Future<void> move(Offset to, {double pressure = 0.5, double radiusMajor = 0}) async {
    await tester.sendEventToBinding(
      PointerMoveEvent(
        pointer: id,
        kind: kind,
        position: to,
        delta: to - _at,
        buttons: _downButtons,
        pressure: pressure,
        pressureMin: 0,
        pressureMax: 1,
        radiusMajor: radiusMajor,
      ),
    );
    _at = to;
  }

  Future<void> up() async {
    await tester.sendEventToBinding(PointerUpEvent(pointer: id, kind: kind, position: _at));
    await tester.sendEventToBinding(PointerRemovedEvent(pointer: id, kind: kind, position: _at));
    await tester.pump();
  }

  /// Arrasta de [from] até [to] em [steps] passos.
  Future<void> drag(Offset from, Offset to, {int steps = 10}) async {
    await down(from);
    for (var i = 1; i <= steps; i++) {
      await move(Offset.lerp(from, to, i / steps)!);
    }
    await up();
  }
}

Stroke lineStroke(String id, Offset a, Offset b, {int n = 20, double width = 4}) => Stroke(
  id: id,
  tool: PenTool.pen,
  argb: 0xFFFFFFFF,
  width: width,
  points: [
    for (var i = 0; i < n; i++)
      InkPoint(a.dx + (b.dx - a.dx) * i / (n - 1), a.dy + (b.dy - a.dy) * i / (n - 1), 0.5),
  ],
);
