import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide TextBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/core/notebook_core.dart';
import 'package:organizacional/notebook/ui/ink_painting.dart';

import 'ui_support.dart';

void main() {
  group('contorno do traço', () {
    test('traço com vários pontos vira um polígono fechado ao redor da linha', () {
      final st = testStroke('s', const Offset(100, 100), const Offset(300, 100));
      final b = strokeOutlinePath(st.points, st.tool, st.width).getBounds();
      expect(b.left, lessThan(100.5));
      expect(b.right, greaterThan(299));
      expect(b.height, greaterThan(1));
      expect(b.height, lessThan(st.width * 2));
    });

    test('um ponto só (pingo) vira um círculo visível', () {
      final b = strokeOutlinePath(const [InkPoint(50, 50, 0.5)], PenTool.pen, 6).getBounds();
      expect(b.width, greaterThan(1));
      expect(b.center.dx, closeTo(50, 0.5));
    });

    test('mais pressão deixa o tinteiro mais grosso', () {
      List<InkPoint> line(double p) => [for (var i = 0; i < 20; i++) InkPoint(10.0 * i, 0, p)];
      final thin = strokeOutlinePath(line(0.1), PenTool.fountain, 6).getBounds().height;
      final thick = strokeOutlinePath(line(0.95), PenTool.fountain, 6).getBounds().height;
      expect(thick, greaterThan(thin * 1.5));
    });
  });

  group('cache dos traços prontos', () {
    PageDoc docOf(int n) => PageDoc.empty.withStrokes([
      for (var i = 0; i < n; i++)
        testStroke('s${i.toString().padLeft(4, '0')}', Offset(10, 10.0 + i * 3), Offset(200, 10.0 + i * 3)),
    ]);

    test('mesmo PageDoc não regrava o Picture', () {
      final cache = PageInkCache();
      final doc = docOf(50);
      const hidden = <String>{};
      cache.pictureFor(doc, hidden, 0, const {});
      cache.pictureFor(doc, hidden, 0, const {});
      expect(cache.rebuilds, 1);
      expect(cache.outlinesComputed, 50);
      cache.dispose();
    });

    test('um traço novo só calcula o contorno do traço novo', () {
      final cache = PageInkCache();
      final doc = docOf(50);
      cache.pictureFor(doc, const {}, 0, const {});
      final doc2 = doc.withStroke(testStroke('zzzz', const Offset(5, 5), const Offset(50, 90)));
      cache.pictureFor(doc2, const {}, 0, const {});
      expect(cache.rebuilds, 2);
      expect(cache.outlinesComputed, 51);
      cache.dispose();
    });

    test('esconder itens (mover seleção) regrava sem recalcular contornos', () {
      final cache = PageInkCache();
      final doc = docOf(20);
      cache.pictureFor(doc, const {}, 0, const {});
      cache.pictureFor(doc, {'s0003'}, 0, const {});
      expect(cache.rebuilds, 2);
      expect(cache.outlinesComputed, 20);
      cache.dispose();
    });

    test('imagem que termina de carregar (epoch) regrava o Picture', () {
      final cache = PageInkCache();
      final doc = docOf(3);
      cache.pictureFor(doc, const {}, 0, const {});
      cache.pictureFor(doc, const {}, 1, const {});
      expect(cache.rebuilds, 2);
      cache.dispose();
    });

    testWidgets('traço em andamento não regrava os traços prontos', (tester) async {
      final s = FakeSession(docs: [docOf(200)]);
      await pumpNotebook(tester, s);
      CommittedInkPainter painter() =>
          tester.widget<CustomPaint>(find.byKey(const ValueKey('nb-committed'))).painter! as CommittedInkPainter;
      final doc0 = painter().doc;
      final rebuilds0 = painter().cache.rebuilds;
      final pen = SimPointer(tester, PointerDeviceKind.stylus);
      await pen.down(const Offset(300, 800));
      for (var i = 1; i <= 30; i++) {
        await pen.move(Offset(300 + i * 8.0, 800 + i * 2.0));
        await tester.pump();
      }
      expect(painter().doc, same(doc0), reason: 'o doc só muda quando o gesto termina');
      expect(painter().cache.rebuilds, rebuilds0);
      await pen.up();
      expect(painter().doc.strokes, hasLength(201));
      expect(painter().cache.outlinesComputed, 201, reason: 'só o traço novo foi calculado');
    });
  });

  testWidgets('páginas pintam sem exceção em todos os fundos, com texto e marca-texto', (tester) async {
    final doc = PageDoc.empty
        .withStroke(testStroke('a', const Offset(100, 200), const Offset(500, 260), tool: PenTool.highlighter, width: 24, argb: 0x66FBBF24))
        .withStroke(testStroke('b', const Offset(100, 300), const Offset(500, 330), tool: PenTool.fountain))
        .withText(TextBox(id: 'c', x: 100, y: 400, w: 300, text: 'Olá, caderno!', size: 30, argb: 0xFFFFFFFF));
    final s = FakeSession(pageCount: 4, docs: [doc, doc, doc, doc]);
    await pumpNotebook(tester, s, size: const Size(800, 6000));
    for (final b in PageBackground.values) {
      s.setBackground(b.index, b);
    }
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    for (var i = 0; i < 4; i++) {
      expect(find.byKey(ValueKey('nb-page-$i')), findsOneWidget);
    }
  });
}
