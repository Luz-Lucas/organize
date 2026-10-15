import 'package:flutter/gestures.dart';

import 'package:flutter/material.dart' hide TextBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/ui/notebook_prefs.dart';
import 'package:organizacional/notebook/ui/notebook_screen.dart';
import 'package:organizacional/notebook/ui/tool_settings.dart';
import 'package:organizacional/ui/org_theme.dart';

import 'ui_support.dart';

Future<List<Map<String, dynamic>>> pumpWithPrefs(
  WidgetTester tester,
  FakeSession session, {
  Map<String, dynamic> prefs = const {},
}) async {
  final saved = <Map<String, dynamic>>[];
  await setSurface(tester, const Size(800, 1300));
  await tester.pumpWidget(
    MaterialApp(
      theme: buildOrgTheme(orgThemes.first, googleFonts: false),
      home: NotebookScreen(
        noteId: 'n1',
        session: session,
        title: 'Caderno',
        prefs: prefs,
        onPrefsChanged: (m) async => saved.add(m),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return saved;
}

/// Desenha um traço horizontal e passa a borracha numa linha paralela 20 px abaixo.
Future<void> drawThenEraseNearby(WidgetTester tester) async {
  await SimPointer(tester, PointerDeviceKind.stylus).drag(linePath(const Offset(200, 300), const Offset(500, 300)));
  await tester.tap(find.byKey(const ValueKey('nb-tool-eraser')));
  await tester.pump();
  await SimPointer(tester, PointerDeviceKind.stylus).drag(linePath(const Offset(200, 320), const Offset(500, 320)));
}

void main() {
  test('tamanhos da borracha: raios crescentes, padrão = o raio antigo', () {
    expect(kEraserRadii, hasLength(kEraserSizeLabels.length));
    for (var i = 1; i < kEraserRadii.length; i++) {
      expect(kEraserRadii[i], greaterThan(kEraserRadii[i - 1]));
    }
    expect(const ToolSettings().eraserRadius, kEraserRadius);
    expect(const ToolSettings().copyWith(eraserSize: 3).eraserRadius, kEraserRadii[3]);
    expect(const ToolSettings(eraserSize: 99).eraserRadius, kEraserRadii.last, reason: 'índice fora da faixa não quebra');
  });

  test('preferências: o tamanho da borracha vai e volta; valor inválido usa o padrão', () {
    final p = NotebookPrefs.fromMap(const {}).withEraserSize(2);
    expect(NotebookPrefs.fromMap(p.toMap()).eraserSize, 2);
    expect(NotebookPrefs.fromMap(const {'eraser': 9}).eraserSize, kDefaultEraserSize);
    expect(NotebookPrefs.fromMap(const {'eraser': 'grande'}).eraserSize, kDefaultEraserSize);
    expect(NotebookPrefs.fromMap(null).eraserSize, kDefaultEraserSize);
  });

  testWidgets('borracha padrão não alcança um traço a 20 px; a enorme (salva nas preferências) apaga', (tester) async {
    final small = FakeSession();
    await pumpWithPrefs(tester, small);
    await drawThenEraseNearby(tester);
    expect(small.docOf(0).strokes, hasLength(1));

    final big = FakeSession();
    await pumpWithPrefs(tester, big, prefs: const {'eraser': 3});
    await drawThenEraseNearby(tester);
    expect(big.docOf(0).strokes, isEmpty);
  });

  testWidgets('tocar de novo na borracha mostra os tamanhos; escolher um salva nas preferências', (tester) async {
    final saved = await pumpWithPrefs(tester, FakeSession());
    await tester.tap(find.byKey(const ValueKey('nb-tool-eraser')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('nb-tool-eraser')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('nb-eraser-size-0')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nb-eraser-size-2')));
    await tester.pumpAndSettle();
    expect(saved.last['eraser'], 2);
  });
}
