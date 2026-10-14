import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide TextBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/core/notebook_core.dart';
import 'package:organizacional/notebook/ui/ink_painting.dart';
import 'package:organizacional/notebook/ui/tool_settings.dart';

import 'page_harness.dart';

CommittedInkPainter committedOf(WidgetTester t, {int page = 0}) => t
    .widget<CustomPaint>(
      find.descendant(of: find.byKey(ValueKey('nb-page-$page')), matching: find.byKey(const ValueKey('nb-committed'))),
    )
    .painter! as CommittedInkPainter;

Finder committedFinder(int page) =>
    find.descendant(of: find.byKey(ValueKey('nb-page-$page')), matching: find.byKey(const ValueKey('nb-committed')));

PageDoc denseDoc(int n) => PageDoc.empty.withStrokes([
  for (var i = 0; i < n; i++)
    lineStroke('s${i.toString().padLeft(4, '0')}', Offset(20 + (i % 20) * 45.0, 100 + (i ~/ 20) * 20.0), Offset(55 + (i % 20) * 45.0, 100 + (i ~/ 20) * 20.0), n: 12),
]);

void main() {
  group('borracha: um lote por quadro', () {
    testWidgets('muitos eventos entre dois quadros regravam o Picture no máximo uma vez', (tester) async {
      final doc = denseDoc(400);
      final h = await PageHarness.pump(tester, docs: [doc], settings: const ToolSettings(kind: ToolKind.eraser));
      final cache = committedOf(tester).cache;
      final rebuilds0 = cache.rebuilds, outlines0 = cache.outlinesComputed;
      final pen = P(tester, PointerDeviceKind.stylus);
      await pen.down(h.g(const Offset(30, 105)));
      await tester.pump();
      final afterDown = cache.rebuilds;
      for (var i = 1; i <= 60; i++) {
        await pen.move(h.g(Offset(30 + i * 14.0, 105 + (i % 3) * 20.0)));
      }
      // nenhum quadro entre os 60 eventos: nada foi regravado ainda
      expect(cache.rebuilds, afterDown);
      await tester.pump();
      expect(cache.rebuilds, lessThanOrEqualTo(afterDown + 1), reason: 'um Picture para os 60 eventos');
      expect(cache.outlinesComputed, outlines0, reason: 'apagar não recalcula contornos');
      expect(committedOf(tester).doc, same(doc), reason: 'o documento só muda no fim do gesto');
      await pen.up();
      expect(h.edits, hasLength(1), reason: 'um onEdit por gesto');
      expect(h.docs[0].strokes.length, lessThan(400));
      expect(cache.rebuilds, greaterThan(rebuilds0));
    });

    testWidgets('borracha parcial: o que se vê durante o gesto é o que fica salvo', (tester) async {
      final doc = denseDoc(200);
      final h = await PageHarness.pump(
        tester,
        docs: [doc],
        settings: const ToolSettings(kind: ToolKind.eraser, eraserMode: EraserMode.partial),
      );
      final pen = P(tester, PointerDeviceKind.stylus);
      await pen.down(h.g(const Offset(30, 105)));
      for (var i = 1; i <= 40; i++) {
        await pen.move(h.g(Offset(30 + i * 20.0, 108)));
      }
      await tester.pump();
      await pen.up();
      await tester.pump();
      final saved = h.docs[0];
      expect(saved.deleted, isNotEmpty);
      expect(saved.strokes.any((s) => !doc.contains(s.id)), isTrue, reason: 'pedaços novos');
      // depois do gesto o painter já mostra o documento final
      expect(committedOf(tester).doc, same(saved));
    });
  });

  group('páginas fora da tela ficam leves', () {
    testWidgets('só as páginas perto da área visível têm camada de traços', (tester) async {
      final doc = denseDoc(30);
      final h = await PageHarness.pump(tester, pages: 12, docs: List.filled(12, doc));
      final withLayer = [for (var i = 0; i < 12; i++) if (committedFinder(i).evaluate().isNotEmpty) i];
      expect(withLayer, contains(0));
      expect(withLayer.length, lessThan(6), reason: 'visíveis: $withLayer');
      expect(withLayer, isNot(contains(11)));
      // o fundo continua em todas
      for (var i = 0; i < 12; i++) {
        expect(find.byKey(ValueKey('nb-page-$i')), findsOneWidget);
      }

      // rola até o fim: a última aparece e a primeira esvazia
      h.tc.value = Matrix4.translationValues(0, -(PageHarness.pageH + PageHarness.gap) * 11, 0);
      await tester.pump();
      await tester.pump();
      expect(committedFinder(11), findsOneWidget);
      expect(committedFinder(0), findsNothing);
    });

    testWidgets('tocar numa página ainda escondida a traz de volta na hora', (tester) async {
      final h = await PageHarness.pump(tester, pages: 12);
      expect(committedFinder(10), findsNothing);
      // rola de uma vez e desenha antes de o observador de visibilidade rodar
      h.tc.value = Matrix4.translationValues(0, -(PageHarness.pageH + PageHarness.gap) * 10, 0);
      await tester.pump();
      final pen = P(tester, PointerDeviceKind.stylus);
      await pen.down(h.g(const Offset(200, 300), page: 10));
      await pen.move(h.g(const Offset(260, 330), page: 10));
      await pen.move(h.g(const Offset(320, 340), page: 10));
      await pen.up();
      await tester.pump();
      expect(h.edits, hasLength(1));
      expect(h.edits.single.page, 10);
      expect(committedFinder(10), findsOneWidget);
    });
  });

  group('imagens', () {
    ImageBox box() => const ImageBox(id: 'i1', x: 100, y: 100, w: 200, h: 200, path: 'p/a.png');

    testWidgets('a imagem decodificada é liberada ao desmontar a página', (tester) async {
      final doc = PageDoc.empty.withImage(box());
      await PageHarness.pump(tester, docs: [doc]);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump();
      final img = committedOf(tester).images['p/a.png'];
      expect(img, isNotNull, reason: 'a imagem carregou');
      expect(img!.debugDisposed, isFalse);
      await tester.pumpWidget(const SizedBox());
      expect(img.debugDisposed, isTrue);
    });

    testWidgets('GIF animado: só o primeiro quadro, a página não é regravada a cada quadro', (tester) async {
      final doc = PageDoc.empty.withImage(box());
      await PageHarness.pump(tester, docs: [doc], gif: true);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump();
      final p0 = committedOf(tester);
      expect(p0.images['p/a.png'], isNotNull);
      final epoch = p0.epoch, rebuilds = p0.cache.rebuilds;
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
        await tester.pump(const Duration(milliseconds: 150));
      }
      final p1 = committedOf(tester);
      expect(p1.epoch, epoch);
      expect(p1.cache.rebuilds, rebuilds);
    });
  });

  test('GIF de teste tem 2 quadros', () {
    final gif = buildTwoFrameGif();
    expect(gif.length, greaterThan(40));
    expect(gif.where((b) => b == 0x2C).length, greaterThanOrEqualTo(2));
  });
}
