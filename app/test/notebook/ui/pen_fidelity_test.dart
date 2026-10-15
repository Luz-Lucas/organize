import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide TextBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/core/notebook_core.dart';
import 'package:organizacional/notebook/ui/tool_settings.dart';

import 'page_harness.dart';

/// Fidelidade da entrada da caneta: o traço gravado precisa chegar até onde a
/// caneta realmente saiu e sobreviver a um cancelamento do sistema.
void main() {
  Future<void> upAt(WidgetTester tester, P p, Offset at) async {
    await tester.sendEventToBinding(PointerUpEvent(pointer: p.id, kind: p.kind, position: at));
    await tester.sendEventToBinding(PointerRemovedEvent(pointer: p.id, kind: p.kind, position: at));
    await tester.pump();
  }

  Future<void> cancelAt(WidgetTester tester, P p, Offset at) async {
    await tester.sendEventToBinding(PointerCancelEvent(pointer: p.id, kind: p.kind, position: at));
    await tester.sendEventToBinding(PointerRemovedEvent(pointer: p.id, kind: p.kind, position: at));
    await tester.pump();
  }

  group('ponto final do traço', () {
    testWidgets('o traço termina onde a caneta saiu (o up acrescenta a própria posição)', (tester) async {
      final h = await PageHarness.pump(tester);
      final pen = P(tester, PointerDeviceKind.stylus);
      await pen.down(h.g(const Offset(100, 100)), pressure: 0.6);
      await pen.move(h.g(const Offset(150, 100)), pressure: 0.7);
      await upAt(tester, pen, h.g(const Offset(260, 100)));
      expect(h.edits, hasLength(1));
      final pts = h.docs[0].strokes.single.points;
      expect(pts.last.x, closeTo(260, 0.2));
      expect(pts.last.y, closeTo(100, 0.2));
      expect(pts.last.p, closeTo(pts[pts.length - 2].p, 0.01), reason: 'usa a pressão do último ponto');
      expect(pts.length, 3);
    });

    testWidgets('up no mesmo lugar do último ponto não duplica o ponto', (tester) async {
      final h = await PageHarness.pump(tester);
      final pen = P(tester, PointerDeviceKind.stylus);
      await pen.down(h.g(const Offset(100, 100)));
      await pen.move(h.g(const Offset(150, 100)));
      await upAt(tester, pen, h.g(const Offset(150, 100)));
      expect(h.docs[0].strokes.single.points, hasLength(2));
    });

    testWidgets('um toque (down + up longe, sem move) vira um traço de dois pontos', (tester) async {
      final h = await PageHarness.pump(tester);
      final pen = P(tester, PointerDeviceKind.stylus);
      await pen.down(h.g(const Offset(100, 100)));
      await upAt(tester, pen, h.g(const Offset(180, 100)));
      expect(h.docs[0].strokes.single.points, hasLength(2));
      expect(h.docs[0].strokes.single.points.last.x, closeTo(180, 0.2));
    });
  });

  group('cancelamento do ponteiro', () {
    testWidgets('desenhando: grava o traço parcial como no up', (tester) async {
      final h = await PageHarness.pump(tester);
      final pen = P(tester, PointerDeviceKind.stylus);
      await pen.down(h.g(const Offset(100, 100)));
      for (var i = 1; i <= 5; i++) {
        await pen.move(h.g(Offset(100.0 + i * 20, 100)));
      }
      await cancelAt(tester, pen, h.g(const Offset(200, 100)));
      expect(h.edits, hasLength(1), reason: 'o traço parcial é gravado');
      final st = h.docs[0].strokes.single;
      expect(st.points.length, greaterThanOrEqualTo(6));
      expect(st.points.last.x, closeTo(200, 0.2));
    });

    testWidgets('desenhando com um ponto só: o cancelamento não grava nada', (tester) async {
      final h = await PageHarness.pump(tester);
      final pen = P(tester, PointerDeviceKind.stylus);
      await pen.down(h.g(const Offset(100, 100)));
      await cancelAt(tester, pen, h.g(const Offset(100, 100)));
      expect(h.edits, isEmpty);
      expect(h.docs[0].strokes, isEmpty);
    });

    testWidgets('depois do cancelamento a página aceita um novo traço', (tester) async {
      final h = await PageHarness.pump(tester);
      final pen = P(tester, PointerDeviceKind.stylus);
      await pen.down(h.g(const Offset(100, 100)));
      await pen.move(h.g(const Offset(160, 100)));
      await pen.move(h.g(const Offset(220, 100)));
      await cancelAt(tester, pen, h.g(const Offset(220, 100)));
      await P(tester, PointerDeviceKind.stylus).drag(h.g(const Offset(100, 300)), h.g(const Offset(300, 300)));
      expect(h.docs[0].strokes, hasLength(2));
    });

    testWidgets('borracha: o cancelamento continua descartando o gesto', (tester) async {
      final stroke = lineStroke('a', const Offset(100, 300), const Offset(500, 300));
      final h = await PageHarness.pump(tester, docs: [PageDoc.empty.withStroke(stroke)]);
      await h.setSettings(h.settings.copyWith(kind: ToolKind.eraser));
      final pen = P(tester, PointerDeviceKind.stylus);
      await pen.down(h.g(const Offset(300, 300)));
      await pen.move(h.g(const Offset(320, 300)));
      await cancelAt(tester, pen, h.g(const Offset(320, 300)));
      expect(h.edits, isEmpty);
      expect(h.docs[0].strokes, hasLength(1));
    });

    testWidgets('laço: o cancelamento não muda a seleção nem grava', (tester) async {
      final h = await PageHarness.pump(tester, docs: [PageDoc.empty.withStroke(lineStroke('a', const Offset(100, 300), const Offset(500, 300)))]);
      await h.setSettings(h.settings.copyWith(kind: ToolKind.lasso));
      final pen = P(tester, PointerDeviceKind.stylus);
      await pen.down(h.g(const Offset(50, 250)));
      await pen.move(h.g(const Offset(600, 250)));
      await pen.move(h.g(const Offset(600, 350)));
      await cancelAt(tester, pen, h.g(const Offset(600, 350)));
      expect(h.edits, isEmpty);
    });
  });

  group('diagnóstico: amostras cruas', () {
    Finder live() => find.byKey(const ValueKey('nb-live'));

    testWidgets('desligado: nenhum pontinho', (tester) async {
      final h = await PageHarness.pump(tester);
      final pen = P(tester, PointerDeviceKind.stylus);
      await pen.down(h.g(const Offset(100, 100)));
      await pen.move(h.g(const Offset(150, 100)));
      await tester.pump();
      expect(tester.renderObject(live()), paintsExactlyCountTimes(#drawCircle, 0));
      await pen.up();
    });

    testWidgets('ligado: um pontinho por amostra do traço atual', (tester) async {
      final h = await PageHarness.pump(tester, debugInput: true);
      final pen = P(tester, PointerDeviceKind.stylus);
      await pen.down(h.g(const Offset(100, 100)));
      await pen.move(h.g(const Offset(150, 100)));
      await pen.move(h.g(const Offset(200, 100)));
      await tester.pump();
      expect(tester.renderObject(live()), paintsExactlyCountTimes(#drawCircle, 3));
      await pen.up();
    });

    testWidgets('ligado: depois de soltar, as amostras do último traço continuam à vista', (tester) async {
      final h = await PageHarness.pump(tester, debugInput: true);
      final pen = P(tester, PointerDeviceKind.stylus);
      await pen.down(h.g(const Offset(100, 100)));
      await pen.move(h.g(const Offset(150, 100)));
      await pen.move(h.g(const Offset(200, 100)));
      await pen.up();
      await tester.pump();
      expect(tester.renderObject(live()), paintsExactlyCountTimes(#drawCircle, 3));
      // novo traço: mostra as amostras do atual e as do último
      final pen2 = P(tester, PointerDeviceKind.stylus);
      await pen2.down(h.g(const Offset(100, 300)));
      await pen2.move(h.g(const Offset(150, 300)));
      await tester.pump();
      expect(tester.renderObject(live()), paintsExactlyCountTimes(#drawCircle, 5));
      await pen2.up();
    });
  });

  group('borda da página', () {
    void expectInside(List<InkPoint> pts) {
      for (final p in pts) {
        expect(p.x, inInclusiveRange(0, pageWidth), reason: 'x=${p.x}');
        expect(p.y, inInclusiveRange(0, pageHeight), reason: 'y=${p.y}');
      }
    }

    testWidgets('traço que começa dentro e sai pela direita é cortado na borda', (tester) async {
      final h = await PageHarness.pump(tester);
      final pen = P(tester, PointerDeviceKind.stylus);
      await pen.down(h.g(const Offset(900, 300)));
      await pen.move(h.g(const Offset(950, 300)));
      await pen.move(h.g(const Offset(1100, 300)));
      await pen.move(h.g(const Offset(1300, 300)));
      await upAt(tester, pen, h.g(const Offset(1300, 300)));
      final pts = h.docs[0].strokes.single.points;
      expectInside(pts);
      expect(pts.last.x, closeTo(1000, 0.2), reason: 'termina na borda, onde a caneta saiu da página');
      expect(pts.last.y, closeTo(300, 0.2));
    });

    testWidgets('sai por cima, por baixo e pela esquerda: sempre só pontos dentro', (tester) async {
      final h = await PageHarness.pump(tester, surface: const Size(900, 1500));
      for (final (from, to) in [
        (const Offset(300, 40), const Offset(300, -60)),
        (const Offset(300, 1380), const Offset(300, 1480)),
        (const Offset(40, 600), const Offset(-60, 700)),
      ]) {
        final pen = P(tester, PointerDeviceKind.stylus);
        await pen.down(h.g(from));
        await pen.move(h.g(Offset.lerp(from, to, 0.5)!));
        await pen.move(h.g(to));
        await upAt(tester, pen, h.g(to));
      }
      expect(h.docs[0].strokes, hasLength(3));
      for (final st in h.docs[0].strokes) {
        expectInside(st.points);
      }
    });

    testWidgets('sai e volta: nada fora da página e o resto depois da borda não vira tinta', (tester) async {
      final h = await PageHarness.pump(tester);
      final pen = P(tester, PointerDeviceKind.stylus);
      await pen.down(h.g(const Offset(900, 300)));
      await pen.move(h.g(const Offset(990, 300)));
      await pen.move(h.g(const Offset(1100, 320)));
      await pen.move(h.g(const Offset(1100, 400)));
      await pen.move(h.g(const Offset(950, 420)));
      await upAt(tester, pen, h.g(const Offset(940, 430)));
      final pts = h.docs[0].strokes.single.points;
      expectInside(pts);
      expect(pts.every((p) => p.x <= 1000), isTrue);
    });

    testWidgets('traço inteiramente dentro não muda', (tester) async {
      final h = await PageHarness.pump(tester);
      await P(tester, PointerDeviceKind.stylus).drag(h.g(const Offset(100, 100)), h.g(const Offset(300, 200)));
      final pts = h.docs[0].strokes.single.points;
      expect(pts.first.x, closeTo(100, 0.2));
      expect(pts.last.x, closeTo(300, 0.2));
    });

    testWidgets('a pintura dos traços prontos é recortada pela borda da página', (tester) async {
      // dado antigo/importado com pontos fora da página: a tinta não aparece fora
      final stroke = lineStroke('a', const Offset(900, 300), const Offset(1200, 300));
      final h = await PageHarness.pump(tester, docs: [PageDoc.empty.withStroke(stroke)]);
      expect(h.docs[0].strokes, hasLength(1));
      expect(
        tester.renderObject(find.byKey(const ValueKey('nb-committed'))),
        paints..clipRect(rect: const Rect.fromLTWH(0, 0, pageWidth, pageHeight))..something((name, args) => name == #drawPicture),
      );
    });

    testWidgets('a prévia ao vivo é recortada pela borda da página', (tester) async {
      final h = await PageHarness.pump(tester);
      final pen = P(tester, PointerDeviceKind.stylus);
      await pen.down(h.g(const Offset(900, 300)));
      await pen.move(h.g(const Offset(990, 300)));
      await tester.pump();
      expect(
        tester.renderObject(find.byKey(const ValueKey('nb-live'))),
        paints..clipRect(rect: const Rect.fromLTWH(0, 0, pageWidth, pageHeight))..path(),
      );
      await pen.up();
    });
  });
}
