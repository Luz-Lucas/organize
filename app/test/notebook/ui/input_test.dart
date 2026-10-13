import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide TextBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/core/notebook_core.dart';
import 'package:organizacional/ui/org_theme.dart';

import 'menu_support.dart';
import 'ui_support.dart';

void main() {
  group('entrada: caneta', () {
    testWidgets('stylus desenha um traço com a cor do tema e pontos em unidades de página', (tester) async {
      final s = FakeSession();
      await pumpNotebook(tester, s);
      await SimPointer(tester, PointerDeviceKind.stylus).drag(
        linePath(const Offset(100, 200), const Offset(500, 260)),
      );
      final doc = s.docOf(0);
      expect(doc.strokes, hasLength(1));
      final st = doc.strokes.single;
      expect(st.points.length, greaterThan(3));
      expect(st.points.first.x, closeTo(100, 1));
      expect(st.points.first.y, closeTo(200, 1));
      expect(st.points.last.x, closeTo(500, 1));
      expect(st.tool, PenTool.fountain);
      final ink = tester.element(find.byKey(const ValueKey('nb-page-0'))).org.ink;
      expect(st.argb, ink.toARGB32());
      expect(s.updates, hasLength(1), reason: 'um updatePage por gesto, não por ponto');
    });

    testWidgets('pressão é normalizada por pressureMin/pressureMax', (tester) async {
      final s = FakeSession();
      await pumpNotebook(tester, s);
      final p = SimPointer(tester, PointerDeviceKind.stylus);
      await p.down(const Offset(100, 100), pressure: 1, pressureMin: 0, pressureMax: 4);
      await p.move(const Offset(200, 100), pressure: 4, pressureMin: 0, pressureMax: 4);
      await p.move(const Offset(300, 100), pressure: 2, pressureMin: 0, pressureMax: 4);
      await p.up();
      final pts = s.docOf(0).strokes.single.points;
      expect(pts.first.p, closeTo(0.25, 0.011));
      expect(pts.map((e) => e.p).reduce((a, b) => a > b ? a : b), closeTo(1.0, 0.011));
      expect(pts.last.p, closeTo(0.5, 0.011));
    });

    testWidgets('desenhar com a caneta não move a página (pan só para toque)', (tester) async {
      final s = FakeSession();
      await pumpNotebook(tester, s);
      final iv = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      final before = iv.transformationController!.value.clone();
      await SimPointer(tester, PointerDeviceKind.stylus).drag(
        linePath(const Offset(100, 100), const Offset(700, 900), n: 30),
      );
      expect(iv.transformationController!.value, before);
      expect(s.docOf(0).strokes, hasLength(1));
    });
  });

  group('entrada: toque e mouse', () {
    testWidgets('toque (palma) não desenha', (tester) async {
      final s = FakeSession();
      await pumpNotebook(tester, s);
      await SimPointer(tester, PointerDeviceKind.touch).drag(
        linePath(const Offset(100, 200), const Offset(500, 260)),
      );
      expect(s.docOf(0).strokes, isEmpty);
      expect(s.updates, isEmpty);
    });

    testWidgets('toque rola a página (pan do InteractiveViewer)', (tester) async {
      final s = FakeSession();
      await pumpNotebook(tester, s);
      final iv = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      final before = iv.transformationController!.value.getTranslation().clone();
      await tester.dragFrom(
        tester.getCenter(find.byKey(const ValueKey('nb-page-0'))),
        const Offset(0, -200),
      );
      await tester.pump();
      final after = iv.transformationController!.value.getTranslation();
      expect(after.y, lessThan(before.y - 50));
    });

    testWidgets('toque da palma enquanto a caneta está no papel é ignorado', (tester) async {
      final s = FakeSession();
      await pumpNotebook(tester, s);
      final pen = SimPointer(tester, PointerDeviceKind.stylus);
      final palm = SimPointer(tester, PointerDeviceKind.touch);
      await pen.down(const Offset(100, 100));
      await palm.down(const Offset(300, 300));
      await palm.move(const Offset(320, 340));
      await pen.move(const Offset(200, 120));
      await palm.up();
      await pen.move(const Offset(300, 140));
      await pen.up();
      final doc = s.docOf(0);
      expect(doc.strokes, hasLength(1));
      expect(doc.strokes.single.points.every((p) => p.y < 200), isTrue);
    });

    testWidgets('"Desenhar com o dedo" liga o toque', (tester) async {
      final s = FakeSession();
      await pumpNotebook(tester, s);
      await tapMenu(tester, 'nb-finger-toggle');
      await SimPointer(tester, PointerDeviceKind.touch).drag(
        linePath(const Offset(100, 200), const Offset(500, 260)),
      );
      expect(s.docOf(0).strokes, hasLength(1));
    });

    testWidgets('mouse desenha (botão esquerdo)', (tester) async {
      final s = FakeSession();
      await pumpNotebook(tester, s);
      await SimPointer(tester, PointerDeviceKind.mouse).drag(
        linePath(const Offset(100, 200), const Offset(500, 260)),
      );
      expect(s.docOf(0).strokes, hasLength(1));
      // pressão constante, sem pressão real
      final ps = s.docOf(0).strokes.single.points.map((p) => p.p).toSet();
      expect(ps, hasLength(1));
    });

    testWidgets('mouse com botão do meio não desenha', (tester) async {
      final s = FakeSession();
      await pumpNotebook(tester, s);
      await SimPointer(tester, PointerDeviceKind.mouse, buttons: kMiddleMouseButton).drag(
        linePath(const Offset(100, 200), const Offset(500, 260)),
      );
      expect(s.docOf(0).strokes, isEmpty);
    });
  });

  group('entrada: borracha', () {
    PageDoc withLine() => PageDoc.empty.withStroke(
      testStroke('a1', const Offset(100, 300), const Offset(600, 300)),
    );

    testWidgets('ponta de borracha (invertedStylus) apaga o traço', (tester) async {
      final s = FakeSession(docs: [withLine()]);
      await pumpNotebook(tester, s);
      await SimPointer(tester, PointerDeviceKind.invertedStylus).drag(
        linePath(const Offset(300, 250), const Offset(300, 350), n: 8),
      );
      expect(s.docOf(0).strokes, isEmpty);
      expect(s.docOf(0).deleted, contains('a1'));
    });

    testWidgets('botão lateral da S Pen apaga enquanto pressionado', (tester) async {
      final s = FakeSession(docs: [withLine()]);
      await pumpNotebook(tester, s);
      await SimPointer(tester, PointerDeviceKind.stylus, buttons: kPrimaryStylusButton).drag(
        linePath(const Offset(300, 250), const Offset(300, 350), n: 8),
      );
      expect(s.docOf(0).strokes, isEmpty);
    });

    testWidgets('botão secundário da caneta também apaga', (tester) async {
      final s = FakeSession(docs: [withLine()]);
      await pumpNotebook(tester, s);
      await SimPointer(tester, PointerDeviceKind.stylus, buttons: kSecondaryStylusButton).drag(
        linePath(const Offset(300, 250), const Offset(300, 350), n: 8),
      );
      expect(s.docOf(0).strokes, isEmpty);
    });

    testWidgets('caneta sem botão desenha por cima sem apagar', (tester) async {
      final s = FakeSession(docs: [withLine()]);
      await pumpNotebook(tester, s);
      await SimPointer(tester, PointerDeviceKind.stylus).drag(
        linePath(const Offset(300, 250), const Offset(300, 350), n: 8),
      );
      expect(s.docOf(0).strokes, hasLength(2));
    });

    testWidgets('borracha por traço (ferramenta) apaga o traço inteiro', (tester) async {
      final s = FakeSession(docs: [withLine()]);
      await pumpNotebook(tester, s);
      await tester.tap(find.byKey(const ValueKey('nb-tool-eraser')));
      await tester.pump();
      await SimPointer(tester, PointerDeviceKind.stylus).drag(
        linePath(const Offset(300, 250), const Offset(300, 350), n: 8),
      );
      expect(s.docOf(0).strokes, isEmpty);
    });

    testWidgets('borracha parcial parte o traço em pedaços', (tester) async {
      final s = FakeSession(docs: [withLine()]);
      await pumpNotebook(tester, s);
      await tester.tap(find.byKey(const ValueKey('nb-tool-eraser')));
      await tester.pump();
      await tapMenu(tester, 'nb-eraser-mode');
      await SimPointer(tester, PointerDeviceKind.stylus).drag(
        linePath(const Offset(350, 250), const Offset(350, 350), n: 8),
      );
      final strokes = s.docOf(0).strokes;
      expect(strokes, hasLength(2));
      expect(strokes.every((e) => e.id != 'a1'), isTrue);
    });
  });

  group('entrada: a página não se mexe sob quem desenha', () {
    Matrix4 viewer(WidgetTester t) =>
        t.widget<InteractiveViewer>(find.byType(InteractiveViewer)).transformationController!.value.clone();

    testWidgets('palma enquanto a caneta está no papel não rola a página', (tester) async {
      final s = FakeSession();
      await pumpNotebook(tester, s);
      final before = viewer(tester);
      final pen = SimPointer(tester, PointerDeviceKind.stylus);
      final palm = SimPointer(tester, PointerDeviceKind.touch);
      await pen.down(const Offset(100, 100));
      await palm.down(const Offset(300, 300));
      for (var i = 1; i <= 10; i++) {
        await palm.move(Offset(300, 300.0 + i * 40));
        await pen.move(Offset(100.0 + i * 20, 100));
      }
      await palm.up();
      await pen.up();
      expect(viewer(tester), before);
    });

    testWidgets('dedo que desenha também não rola a página', (tester) async {
      final s = FakeSession();
      await pumpNotebook(tester, s);
      await tapMenu(tester, 'nb-finger-toggle');
      final before = viewer(tester);
      await SimPointer(tester, PointerDeviceKind.touch).drag(
        linePath(const Offset(100, 100), const Offset(600, 800), n: 30),
      );
      expect(viewer(tester), before);
      expect(s.docOf(0).strokes, hasLength(1));
    });

    testWidgets('mouse desenhando não rola; botão do meio arrasta a página', (tester) async {
      final s = FakeSession();
      await pumpNotebook(tester, s, size: const Size(800, 700));
      final before = viewer(tester);
      await SimPointer(tester, PointerDeviceKind.mouse).drag(
        linePath(const Offset(100, 100), const Offset(600, 800), n: 30),
      );
      expect(viewer(tester), before);
      await SimPointer(tester, PointerDeviceKind.mouse, buttons: kMiddleMouseButton).drag(
        linePath(const Offset(400, 600), const Offset(400, 100), n: 10),
      );
      expect(viewer(tester).getTranslation().y, lessThan(before.getTranslation().y - 100));
      expect(s.docOf(0).strokes, hasLength(1));
    });

    testWidgets('toque na ferramenta de caneta não cria texto nem traço', (tester) async {
      final s = FakeSession();
      await pumpNotebook(tester, s);
      final t = SimPointer(tester, PointerDeviceKind.touch);
      await t.down(const Offset(200, 300));
      await t.up();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('nb-text-field')), findsNothing);
      expect(s.docOf(0).strokes, isEmpty);
    });
  });
}
