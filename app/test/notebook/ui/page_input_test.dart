import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide TextBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/core/notebook_core.dart';
import 'package:organizacional/notebook/ui/pen_activity.dart';
import 'package:organizacional/notebook/ui/tool_settings.dart';

import 'page_harness.dart';

void main() {
  group('palma: estado global da caneta', () {
    testWidgets('controle: sem caneta, um dedo rola a página', (tester) async {
      final h = await PageHarness.pump(tester);
      final before = h.ty;
      await P(tester, PointerDeviceKind.touch).drag(h.g(const Offset(500, 700)), h.g(const Offset(500, 700)) + const Offset(0, -150));
      expect(h.ty, lessThan(before - 50));
      expect(h.edits, isEmpty);
    });

    testWidgets('caneta pairando (hover): um dedo é ignorado, não rola nem desenha', (tester) async {
      final h = await PageHarness.pump(tester);
      final before = h.view;
      await P(tester, PointerDeviceKind.stylus).hover(h.g(const Offset(100, 100)));
      await P(tester, PointerDeviceKind.touch).drag(h.g(const Offset(500, 700)), h.g(const Offset(500, 700)) + const Offset(0, -200), steps: 12);
      expect(h.view, before);
      expect(h.edits, isEmpty);
    });

    testWidgets('o hover vale para todas as páginas, não só a que a caneta sobrevoa', (tester) async {
      final h = await PageHarness.pump(tester, pages: 2, surface: const Size(800, 1300));
      final before = h.view;
      await P(tester, PointerDeviceKind.stylus).hover(h.g(const Offset(100, 100), page: 0));
      final from = h.g(const Offset(500, 700), page: 1);
      await P(tester, PointerDeviceKind.touch).drag(from, from + const Offset(0, -120));
      expect(h.view, before);
    });

    testWidgets('depois de levantar a caneta, o dedo só volta a rolar após 1,5 s', (tester) async {
      final h = await PageHarness.pump(tester);
      final pen = P(tester, PointerDeviceKind.stylus);
      await pen.hover(h.g(const Offset(100, 100)));
      await pen.down(h.g(const Offset(100, 100)));
      await pen.move(h.g(const Offset(200, 120)));
      await pen.up();
      expect(h.edits, hasLength(1));

      final before = h.view;
      h.clock += const Duration(milliseconds: 1000);
      var from = h.g(const Offset(500, 700));
      await P(tester, PointerDeviceKind.touch).drag(from, from + const Offset(0, -150));
      expect(h.view, before, reason: 'ainda dentro dos 1,5 s');

      h.clock += const Duration(milliseconds: 700); // 1,7 s no total
      from = h.g(const Offset(500, 700));
      await P(tester, PointerDeviceKind.touch).drag(from, from + const Offset(0, -150));
      expect(h.ty, lessThan(h.view.getTranslation().y + 1));
      expect(h.tx != before.getTranslation().x || h.ty != before.getTranslation().y, isTrue, reason: 'rolou');
    });

    testWidgets('com a caneta ativa, dois dedos rolam e dão zoom', (tester) async {
      final h = await PageHarness.pump(tester);
      await P(tester, PointerDeviceKind.stylus).hover(h.g(const Offset(100, 100)));
      final before = h.view;
      final a = P(tester, PointerDeviceKind.touch), b = P(tester, PointerDeviceKind.touch);
      final a0 = h.g(const Offset(400, 700)), b0 = h.g(const Offset(600, 700));
      await a.down(a0);
      await b.down(b0);
      for (var i = 1; i <= 10; i++) {
        await a.move(a0 + Offset(-6.0 * i, 0));
        await b.move(b0 + Offset(6.0 * i, 0));
      }
      await a.up();
      await b.up();
      final after = h.view;
      expect(after.getMaxScaleOnAxis(), greaterThan(before.getMaxScaleOnAxis() + 0.05), reason: 'zoom');
    });

    testWidgets('a caneta tem prioridade: ao encostar cancela o pan do toque em andamento', (tester) async {
      final h = await PageHarness.pump(tester);
      final touch = P(tester, PointerDeviceKind.touch);
      final t0 = h.g(const Offset(500, 700));
      await touch.down(t0);
      for (var i = 1; i <= 8; i++) {
        await touch.move(t0 + Offset(0, -15.0 * i));
      }
      final panned = h.ty;
      expect(panned, lessThan(-50), reason: 'o toque estava rolando');

      final pen = P(tester, PointerDeviceKind.stylus);
      await pen.down(h.g(const Offset(100, 100)));
      await tester.pump();
      for (var i = 9; i <= 20; i++) {
        await touch.move(t0 + Offset(0, -15.0 * i));
      }
      expect(h.ty, closeTo(panned, 0.5), reason: 'depois da caneta, o toque não rola mais');
      await pen.up();
      await touch.up();
    });

    testWidgets('"dedo desenha" ligado: toque grande (palma) é ignorado; dedo normal desenha', (tester) async {
      final h = await PageHarness.pump(tester, settings: const ToolSettings(fingerDraws: true));
      final palm = P(tester, PointerDeviceKind.touch);
      final a = h.g(const Offset(200, 300));
      await palm.down(a, radiusMajor: kPalmRadiusMajor * 2);
      await palm.move(a + const Offset(60, 20), radiusMajor: kPalmRadiusMajor * 2);
      await palm.move(a + const Offset(120, 40), radiusMajor: kPalmRadiusMajor * 2);
      await palm.up();
      expect(h.edits, isEmpty, reason: 'palma não desenha');

      final finger = P(tester, PointerDeviceKind.touch);
      await finger.down(a, radiusMajor: 8);
      await finger.move(a + const Offset(60, 20), radiusMajor: 8);
      await finger.move(a + const Offset(120, 40), radiusMajor: 8);
      await finger.up();
      expect(h.edits, hasLength(1));
    });

    testWidgets('"dedo desenha" ligado e caneta ativa: o dedo é ignorado', (tester) async {
      final h = await PageHarness.pump(tester, settings: const ToolSettings(fingerDraws: true));
      await P(tester, PointerDeviceKind.stylus).hover(h.g(const Offset(100, 100)));
      final a = h.g(const Offset(200, 300));
      await P(tester, PointerDeviceKind.touch).drag(a, a + const Offset(150, 40));
      expect(h.edits, isEmpty);
    });

    testWidgets('toque curto com a ferramenta Texto: posiciona sem caneta, é ignorado com a caneta ativa', (tester) async {
      final h = await PageHarness.pump(tester, settings: const ToolSettings(kind: ToolKind.text));
      final t = P(tester, PointerDeviceKind.touch);
      await t.down(h.g(const Offset(300, 300)));
      await t.up();
      expect(h.textTaps, hasLength(1), reason: 'controle: sem caneta o toque curto cria texto');

      await P(tester, PointerDeviceKind.stylus).hover(h.g(const Offset(100, 100)));
      final t2 = P(tester, PointerDeviceKind.touch);
      await t2.down(h.g(const Offset(300, 300)));
      await t2.up();
      expect(h.textTaps, hasLength(1), reason: 'palma não cria texto');
    });
  });

  group('PenActivity (unidade)', () {
    PointerDownEvent down(PointerDeviceKind k, int id) => PointerDownEvent(pointer: id, kind: k);

    test('ativa durante o contato, em hover e por 1,5 s depois', () {
      var now = Duration.zero;
      final a = PenActivity(now: () => now);
      expect(a.isActive, isFalse);
      a.note(const PointerHoverEvent(kind: PointerDeviceKind.stylus));
      expect(a.isActive, isTrue);
      now = const Duration(milliseconds: 1499);
      expect(a.isActive, isTrue);
      now = const Duration(milliseconds: 1501);
      expect(a.isActive, isFalse);
      final d = down(PointerDeviceKind.stylus, 1);
      a.note(d);
      now += const Duration(seconds: 30);
      expect(a.isActive, isTrue, reason: 'encostada o tempo todo');
      a.note(const PointerUpEvent(pointer: 1, kind: PointerDeviceKind.stylus));
      expect(a.isActive, isTrue);
      now += const Duration(milliseconds: 1600);
      expect(a.isActive, isFalse);
    });

    test('toque não ativa a caneta; ponta de borracha conta como caneta', () {
      final a = PenActivity(now: () => Duration.zero);
      a.note(down(PointerDeviceKind.touch, 1));
      expect(a.isActive, isFalse);
      a.note(const PointerHoverEvent(kind: PointerDeviceKind.invertedStylus));
      expect(a.isActive, isTrue);
    });

    test('caneta que encosta cancela os toques em andamento, uma vez', () {
      final cancelled = <int>[];
      final a = PenActivity(now: () => Duration.zero, cancelTouch: cancelled.add);
      a.note(down(PointerDeviceKind.touch, 7));
      a.note(down(PointerDeviceKind.touch, 8));
      a.note(const PointerUpEvent(pointer: 8, kind: PointerDeviceKind.touch));
      a.note(down(PointerDeviceKind.stylus, 1));
      expect(cancelled, [7]);
      a.note(down(PointerDeviceKind.stylus, 2));
      expect(cancelled, [7]);
    });

    test('o mesmo evento visto duas vezes (página e rota global) conta uma só', () {
      final cancelled = <int>[];
      final a = PenActivity(now: () => Duration.zero, cancelTouch: cancelled.add);
      a.note(down(PointerDeviceKind.touch, 7));
      final d = down(PointerDeviceKind.stylus, 1);
      a.note(d);
      a.note(d);
      expect(cancelled, [7]);
    });

    test('describe mostra kind, buttons e pressão normalizada', () {
      final s = PenActivity.describe(
        const PointerDownEvent(kind: PointerDeviceKind.stylus, buttons: 2, pressure: 1, pressureMin: 0, pressureMax: 4),
      );
      expect(s, contains('kind=stylus'));
      expect(s, contains('buttons=2'));
      expect(s, contains('pressure=0.25'));
    });
  });

  group('botão da S Pen', () {
    PageDoc withLine() => PageDoc.empty.withStroke(lineStroke('a1', const Offset(100, 300), const Offset(600, 300)));

    Future<PageHarness> erase(WidgetTester tester, int buttons) async {
      final h = await PageHarness.pump(tester, docs: [withLine()]);
      final pen = P(tester, PointerDeviceKind.stylus, buttons: buttons);
      await pen.drag(h.g(const Offset(300, 250)), h.g(const Offset(300, 350)));
      return h;
    }

    for (final (name, b) in [
      ('primário da caneta', kPrimaryStylusButton),
      ('secundário da caneta', kSecondaryStylusButton),
      ('secundário do mouse (BUTTON_SECONDARY dos Samsung)', kSecondaryMouseButton),
      ('combinado com contato', kPrimaryButton | kSecondaryMouseButton),
    ]) {
      testWidgets('botão $name apaga', (tester) async {
        final h = await erase(tester, b);
        expect(h.docs[0].strokes, isEmpty);
        expect(h.docs[0].deleted, contains('a1'));
      });
    }

    testWidgets('sem botão a caneta desenha por cima', (tester) async {
      final h = await erase(tester, 0);
      expect(h.docs[0].strokes, hasLength(2));
    });

    testWidgets('botão do meio do mouse (terciário) não apaga com a caneta', (tester) async {
      final h = await PageHarness.pump(tester, docs: [withLine()]);
      // kMiddleMouseButton == kSecondaryStylusButton (4): para a caneta apaga; para o mouse não.
      final mouse = P(tester, PointerDeviceKind.mouse);
      await mouse.drag(h.g(const Offset(300, 250)), h.g(const Offset(300, 350)));
      expect(h.docs[0].strokes, hasLength(2));
    });
  });

  group('debugInput (modo de diagnóstico escondido)', () {
    testWidgets('desligado por padrão: nada na tela', (tester) async {
      final h = await PageHarness.pump(tester);
      await P(tester, PointerDeviceKind.stylus).hover(h.g(const Offset(100, 100)));
      expect(find.byKey(const ValueKey('nb-debug-input')), findsNothing);
    });

    testWidgets('ligado: mostra kind, buttons e pressure do último evento', (tester) async {
      final h = await PageHarness.pump(tester, debugInput: true);
      expect(find.byKey(const ValueKey('nb-debug-input')), findsOneWidget);
      final pen = P(tester, PointerDeviceKind.stylus, buttons: kPrimaryStylusButton);
      await pen.down(h.g(const Offset(100, 100)), pressure: 0.37);
      await tester.pump();
      var text = tester.widget<Text>(find.descendant(of: find.byKey(const ValueKey('nb-debug-input')), matching: find.byType(Text))).data!;
      expect(text, contains('kind=stylus'));
      expect(text, contains('buttons=$kPrimaryStylusButton'));
      expect(text, contains('pressure=0.37'));
      await pen.up();
      await P(tester, PointerDeviceKind.mouse).hover(h.g(const Offset(200, 200)));
      await tester.pump();
      text = tester.widget<Text>(find.descendant(of: find.byKey(const ValueKey('nb-debug-input')), matching: find.byType(Text))).data!;
      expect(text, contains('kind=mouse'));
    });
  });
}
