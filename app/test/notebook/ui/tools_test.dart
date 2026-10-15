import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide TextBox;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/core/notebook_core.dart';
import 'package:organizacional/notebook/ui/notebook_screen.dart';
import 'package:organizacional/ui/org_theme.dart';

import 'menu_support.dart';
import 'ui_support.dart';

Future<void> tapKey(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pump();
}

PageDoc oneLine() => PageDoc.empty.withStroke(
  testStroke('a1', const Offset(200, 300), const Offset(400, 300)),
);

Offset centerOf(Stroke s) => s.bounds.center;

void main() {
  group('canetas, cores e espessuras', () {
    testWidgets('cada caneta grava o tool certo e o marca-texto é largo e translúcido', (tester) async {
      final s = FakeSession();
      await pumpNotebook(tester, s);
      for (final (key, tool) in [
        ('nb-tool-pen', PenTool.pen),
        ('nb-tool-pencil', PenTool.pencil),
        ('nb-tool-highlighter', PenTool.highlighter),
        ('nb-tool-fountain', PenTool.fountain),
      ]) {
        await tapMenu(tester, key);
        await SimPointer(tester, PointerDeviceKind.stylus).drag(
          linePath(const Offset(100, 100), const Offset(400, 100)),
        );
        expect(s.docOf(0).strokes.last.tool, tool);
      }
      final strokes = s.docOf(0).strokes;
      final hl = strokes.firstWhere((e) => e.tool == PenTool.highlighter);
      final pen = strokes.firstWhere((e) => e.tool == PenTool.pen);
      expect(hl.width, greaterThan(pen.width * 2));
      expect((hl.argb >> 24) & 0xFF, lessThan(0xFF));
      expect((pen.argb >> 24) & 0xFF, 0xFF);
    });

    testWidgets('cor da paleta do tema e espessura mudam o próximo traço', (tester) async {
      final s = FakeSession();
      await pumpNotebook(tester, s);
      final org = tester.element(find.byKey(const ValueKey('nb-page-0'))).org;
      await openMenu(tester);
      await tapInMenu(tester, 'nb-color-2');
      await tapInMenu(tester, 'nb-width-4');
      await closeMenu(tester);
      await SimPointer(tester, PointerDeviceKind.stylus).drag(
        linePath(const Offset(100, 100), const Offset(400, 100)),
      );
      final st = s.docOf(0).strokes.single;
      expect(st.argb, org.accent.toARGB32());
      expect(st.width, 14.0);
    });

    testWidgets('seletor de cor própria', (tester) async {
      final s = FakeSession();
      await pumpNotebook(tester, s);
      await openMenu(tester);
      await tapInMenu(tester, 'nb-color-custom');
      await tester.drag(find.byKey(const ValueKey('nb-hue')), const Offset(60, 0));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('nb-color-ok')));
      await tester.pumpAndSettle();
      await closeMenu(tester);
      await SimPointer(tester, PointerDeviceKind.stylus).drag(
        linePath(const Offset(100, 100), const Offset(400, 100)),
      );
      final ink = tester.element(find.byKey(const ValueKey('nb-page-0'))).org.ink;
      expect(s.docOf(0).strokes.single.argb, isNot(ink.toARGB32()));
    });
  });

  group('desfazer e refazer', () {
    testWidgets('desfazer remove o traço, refazer volta', (tester) async {
      final s = FakeSession();
      await pumpNotebook(tester, s);
      expect(tester.widget<IconButton>(find.byKey(const ValueKey('nb-undo'))).onPressed, isNull);
      await SimPointer(tester, PointerDeviceKind.stylus).drag(
        linePath(const Offset(100, 100), const Offset(400, 100)),
      );
      expect(s.docOf(0).strokes, hasLength(1));
      await tapKey(tester, 'nb-undo');
      expect(s.docOf(0).strokes, isEmpty);
      expect(s.updates.last.doc.strokes, isEmpty);
      await tapKey(tester, 'nb-redo');
      expect(s.docOf(0).strokes, hasLength(1));
    });

    testWidgets('desfazer a borracha traz o traço de volta', (tester) async {
      final s = FakeSession(docs: [oneLine()]);
      await pumpNotebook(tester, s);
      await SimPointer(tester, PointerDeviceKind.invertedStylus).drag(
        linePath(const Offset(300, 250), const Offset(300, 350), n: 8),
      );
      expect(s.docOf(0).strokes, isEmpty);
      await tapKey(tester, 'nb-undo');
      expect(s.docOf(0).strokes, hasLength(1));
    });
  });

  group('laço', () {
    testWidgets('laço seleciona e arrastar move o traço', (tester) async {
      final s = FakeSession(docs: [oneLine()]);
      await pumpNotebook(tester, s);
      await tapKey(tester, 'nb-tool-lasso');
      final pen = SimPointer(tester, PointerDeviceKind.stylus);
      await pen.drag([
        const Offset(150, 250),
        const Offset(450, 250),
        const Offset(450, 350),
        const Offset(150, 350),
        const Offset(150, 252),
      ]);
      // seleção feita: barra de ações visível
      expect(find.byKey(const ValueKey('nb-sel-delete')), findsOneWidget);
      final before = centerOf(s.docOf(0).strokes.single);
      // arrasta de dentro da caixa da seleção
      await SimPointer(tester, PointerDeviceKind.stylus).drag(
        linePath(const Offset(300, 300), const Offset(300, 500), n: 10),
      );
      final strokes = s.docOf(0).strokes;
      expect(strokes, hasLength(1));
      final after = centerOf(strokes.single);
      expect(after.dy - before.dy, closeTo(200, 2));
      expect(after.dx - before.dx, closeTo(0, 2));
    });

    testWidgets('alça do canto redimensiona', (tester) async {
      final s = FakeSession(docs: [oneLine()]);
      await pumpNotebook(tester, s);
      await tapKey(tester, 'nb-tool-lasso');
      await SimPointer(tester, PointerDeviceKind.stylus).drag([
        const Offset(150, 250),
        const Offset(450, 250),
        const Offset(450, 350),
        const Offset(150, 350),
        const Offset(150, 252),
      ]);
      final b = s.docOf(0).strokes.single.bounds;
      await SimPointer(tester, PointerDeviceKind.stylus).drag(
        linePath(b.bottomRight, b.bottomRight + Offset(b.width, b.height), n: 8),
      );
      final nb = s.docOf(0).strokes.single.bounds;
      expect(nb.width, closeTo(b.width * 2, 6));
    });

    testWidgets('apagar a seleção', (tester) async {
      final s = FakeSession(docs: [oneLine()]);
      await pumpNotebook(tester, s);
      await tapKey(tester, 'nb-tool-lasso');
      await SimPointer(tester, PointerDeviceKind.stylus).drag([
        const Offset(150, 250),
        const Offset(450, 250),
        const Offset(450, 350),
        const Offset(150, 350),
      ]);
      await tapKey(tester, 'nb-sel-delete');
      expect(s.docOf(0).strokes, isEmpty);
      await tapKey(tester, 'nb-undo');
      expect(s.docOf(0).strokes, hasLength(1));
    });

    testWidgets('copiar e colar duplica o traço deslocado', (tester) async {
      final s = FakeSession(docs: [oneLine()]);
      await pumpNotebook(tester, s);
      await tapKey(tester, 'nb-tool-lasso');
      await SimPointer(tester, PointerDeviceKind.stylus).drag([
        const Offset(150, 250),
        const Offset(450, 250),
        const Offset(450, 350),
        const Offset(150, 350),
      ]);
      await tapKey(tester, 'nb-sel-copy');
      await tapKey(tester, 'nb-sel-paste');
      expect(s.docOf(0).strokes, hasLength(2));
    });

    testWidgets('mudar a cor da seleção', (tester) async {
      final s = FakeSession(docs: [oneLine()]);
      await pumpNotebook(tester, s);
      await tapKey(tester, 'nb-tool-lasso');
      await SimPointer(tester, PointerDeviceKind.stylus).drag([
        const Offset(150, 250),
        const Offset(450, 250),
        const Offset(450, 350),
        const Offset(150, 350),
      ]);
      await tapKey(tester, 'nb-sel-color');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nb-color-ok')));
      await tester.pumpAndSettle();
      final st = s.docOf(0).strokes.single;
      expect(st.argb, isNot(0xFFFFFFFF));
    });

    testWidgets('toque fora da seleção limpa a seleção', (tester) async {
      final s = FakeSession(docs: [oneLine()]);
      await pumpNotebook(tester, s);
      await tapKey(tester, 'nb-tool-lasso');
      await SimPointer(tester, PointerDeviceKind.stylus).drag([
        const Offset(150, 250),
        const Offset(450, 250),
        const Offset(450, 350),
        const Offset(150, 350),
      ]);
      expect(find.byKey(const ValueKey('nb-sel-delete')), findsOneWidget);
      final p = SimPointer(tester, PointerDeviceKind.stylus);
      await p.down(const Offset(800, 900));
      await p.up();
      expect(find.byKey(const ValueKey('nb-sel-delete')), findsNothing);
    });
  });

  group('texto', () {
    testWidgets('toque com a ferramenta Texto cria uma caixa de texto', (tester) async {
      final s = FakeSession();
      await pumpNotebook(tester, s);
      await tapMenu(tester, 'nb-tool-text');
      final p = SimPointer(tester, PointerDeviceKind.stylus);
      await p.down(const Offset(200, 300));
      await p.up();
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('nb-text-field')), 'Olá mundo');
      await tester.tap(find.byKey(const ValueKey('nb-text-ok')));
      await tester.pumpAndSettle();
      final texts = s.docOf(0).texts;
      expect(texts, hasLength(1));
      expect(texts.single.text, 'Olá mundo');
      expect(texts.single.x, closeTo(200, 1));
      expect(texts.single.y, closeTo(300, 1));
    });

    testWidgets('toque com o dedo na ferramenta Texto também posiciona', (tester) async {
      final s = FakeSession();
      await pumpNotebook(tester, s);
      await tapMenu(tester, 'nb-tool-text');
      final p = SimPointer(tester, PointerDeviceKind.touch);
      await p.down(const Offset(200, 300));
      await p.up();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('nb-text-field')), findsOneWidget);
    });

    testWidgets('editar o texto troca por outro id (apagar + criar)', (tester) async {
      final tb = TextBox(id: '0001', x: 100, y: 100, w: 400, text: 'antigo', size: 24, argb: 0xFFFFFFFF);
      final s = FakeSession(docs: [PageDoc.empty.withText(tb)]);
      await pumpNotebook(tester, s);
      await tapMenu(tester, 'nb-tool-text');
      final p = SimPointer(tester, PointerDeviceKind.stylus);
      await p.down(const Offset(150, 110));
      await p.up();
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('nb-text-field')), 'novo');
      await tester.tap(find.byKey(const ValueKey('nb-text-ok')));
      await tester.pumpAndSettle();
      final d = s.docOf(0);
      expect(d.texts.single.text, 'novo');
      expect(d.deleted, contains('0001'));
    });

    testWidgets('cancelar não cria nada', (tester) async {
      final s = FakeSession();
      await pumpNotebook(tester, s);
      await tapMenu(tester, 'nb-tool-text');
      final p = SimPointer(tester, PointerDeviceKind.stylus);
      await p.down(const Offset(200, 300));
      await p.up();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nb-text-cancel')));
      await tester.pumpAndSettle();
      expect(s.docOf(0).texts, isEmpty);
    });
  });

  group('imagem', () {
    testWidgets('inserir imagem envia ao store e cria ImageBox', (tester) async {
      final s = FakeSession();
      await pumpNotebook(
        tester,
        s,
        pickImage: () async => PickedImage(bytes: kPng, ext: 'png', width: 400, height: 200),
      );
      await openMenu(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('nb-tool-image')));
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('nb-tool-image')));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(s.images.uploads, hasLength(1));
      final images = s.docOf(0).images;
      expect(images, hasLength(1));
      expect(images.single.path, 'u/n/img-1.png');
      expect(images.single.w, closeTo(400, 1));
      expect(images.single.h, closeTo(200, 1));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(s.images.loads, contains('u/n/img-1.png'));
    });

    testWidgets('selecionar de novo pelo laço e apagar a imagem', (tester) async {
      final s = FakeSession();
      await pumpNotebook(
        tester,
        s,
        pickImage: () async => PickedImage(bytes: kPng, ext: 'png', width: 400, height: 200),
      );
      await openMenu(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('nb-tool-image')));
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('nb-tool-image')));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      // a imagem inserida já vem selecionada na ferramenta laço
      await tapKey(tester, 'nb-sel-delete');
      expect(s.docOf(0).images, isEmpty);
    });

    testWidgets('cancelar o seletor não faz nada', (tester) async {
      final s = FakeSession();
      await pumpNotebook(tester, s, pickImage: () async => null);
      await openMenu(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('nb-tool-image')));
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('nb-tool-image')));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();
      expect(s.images.uploads, isEmpty);
      expect(s.docOf(0).images, isEmpty);
    });
  });

  group('páginas e fundo', () {
    testWidgets('+ Página chama a sessão e a página nova aparece', (tester) async {
      final s = FakeSession();
      await pumpNotebook(tester, s);
      await tapMenu(tester, 'nb-add-page');
      await tester.pump();
      expect(s.current, hasLength(2));
      expect(find.byKey(const ValueKey('nb-page-1')), findsOneWidget);
    });

    testWidgets('botão + Página no fim da rolagem', (tester) async {
      final s = FakeSession();
      await pumpNotebook(tester, s);
      await tester.ensureVisible(find.byKey(const ValueKey('nb-add-page-end')));
      expect(find.byKey(const ValueKey('nb-add-page-end')), findsOneWidget);
    });

    testWidgets('trocar o fundo da página ativa', (tester) async {
      final s = FakeSession();
      await pumpNotebook(tester, s);
      await openMenu(tester);
      await tapInMenu(tester, 'nb-background');
      await tapInMenu(tester, 'nb-bg-grid');
      expect(s.current.single.background, PageBackground.grid);
    });

    testWidgets('duplicar e apagar página (com confirmação)', (tester) async {
      final s = FakeSession(docs: [oneLine()]);
      await pumpNotebook(tester, s, size: const Size(800, 3000));
      await tapKey(tester, 'nb-page-dup-0');
      await tester.pump();
      expect(s.current, hasLength(2));
      expect(s.docOf(1).strokes, hasLength(1));
      await tapKey(tester, 'nb-page-del-1');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nb-confirm-yes')));
      await tester.pumpAndSettle();
      expect(s.current, hasLength(1));
      expect(find.byKey(const ValueKey('nb-page-1')), findsNothing);
    });

    testWidgets('a última página não pode ser apagada', (tester) async {
      final s = FakeSession();
      await pumpNotebook(tester, s);
      expect(tester.widget<IconButton>(find.byKey(const ValueKey('nb-page-del-0'))).onPressed, isNull);
    });

    testWidgets('desenhar na segunda página grava no índice 1', (tester) async {
      final s = FakeSession(pageCount: 2);
      await pumpNotebook(tester, s, size: const Size(800, 3000));
      await SimPointer(tester, PointerDeviceKind.stylus, idx: 1).drag(
        linePath(const Offset(100, 100), const Offset(400, 100)),
      );
      expect(s.updates.single.idx, 1);
      expect(s.docOf(1).strokes, hasLength(1));
      expect(s.docOf(0).strokes, isEmpty);
    });
  });

  group('sincronização', () {
    testWidgets('página que chega de outro aparelho é mesclada sem perder o que está na tela', (tester) async {
      final s = FakeSession();
      await pumpNotebook(tester, s);
      await SimPointer(tester, PointerDeviceKind.stylus).drag(
        linePath(const Offset(100, 100), const Offset(400, 100)),
      );
      final mine = s.docOf(0).strokes.single.id;
      final remote = s.docOf(0).withStroke(testStroke('zz-remote', const Offset(100, 500), const Offset(500, 500)));
      s.remoteDoc(0, remote);
      await tester.pump();
      await tester.pump();
      // desfazer meu traço não pode apagar o do outro aparelho
      await tapKey(tester, 'nb-undo');
      final ids = s.docOf(0).strokes.map((e) => e.id).toList();
      expect(ids, contains('zz-remote'));
      expect(ids, isNot(contains(mine)));
    });

    testWidgets('status de salvamento aparece na barra', (tester) async {
      final s = FakeSession();
      await pumpNotebook(tester, s);
      expect(find.text('Salvo'), findsOneWidget);
      s.setStatus(SaveStatus.saving);
      await tester.pump();
      await tester.pump();
      expect(find.text('Salvando…'), findsOneWidget);
      s.setStatus(SaveStatus.offline);
      await tester.pump();
      await tester.pump();
      expect(find.text('Sem conexão (salvo no aparelho)'), findsOneWidget);
    });
  });

  group('zoom e rolagem', () {
    testWidgets('botões de zoom ficam entre 50% e 400%', (tester) async {
      final s = FakeSession();
      await pumpNotebook(tester, s);
      await openMenu(tester);
      for (var i = 0; i < 12; i++) {
        await tapInMenu(tester, 'nb-zoom-in');
      }
      expect(find.text('400%'), findsOneWidget);
      for (var i = 0; i < 25; i++) {
        await tapInMenu(tester, 'nb-zoom-out');
      }
      expect(find.text('50%'), findsOneWidget);
    });

    testWidgets('roda do mouse rola, Ctrl+roda dá zoom', (tester) async {
      final s = FakeSession();
      await pumpNotebook(tester, s);
      final iv = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      final before = iv.transformationController!.value.getTranslation().y;
      final pos = tester.getCenter(find.byKey(const ValueKey('nb-page-0')));
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(pos));
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 120)));
      await tester.pump();
      expect(iv.transformationController!.value.getTranslation().y, lessThan(before));
      expect(iv.transformationController!.value.storage[0], 1.0);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, -120)));
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(iv.transformationController!.value.storage[0], greaterThan(1.1));
    });
  });

  group('layout e desempenho', () {
    testWidgets('em 360 dp não estoura o layout e a barra rola na horizontal', (tester) async {
      final s = FakeSession();
      await pumpNotebook(tester, s, size: const Size(360, 780));
      expect(tester.takeException(), isNull);
      for (final k in ['nb-fav-pen-0', 'nb-tool-eraser', 'nb-undo', 'nb-redo', 'nb-more']) {
        expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
      }
      await openMenu(tester);
      for (final k in ['nb-tool-pen', 'nb-add-page']) {
        await tester.ensureVisible(find.byKey(ValueKey(k)));
        expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
      }
      expect(tester.takeException(), isNull);
      await closeMenu(tester);
      // página cabe na largura (sem rolagem horizontal)
      final r = tester.getRect(find.byKey(const ValueKey('nb-page-0')));
      expect(r.width, lessThanOrEqualTo(360));
      expect(r.left, greaterThanOrEqualTo(0));
      await SimPointer(tester, PointerDeviceKind.stylus).drag(
        linePath(const Offset(100, 100), const Offset(400, 160)),
      );
      expect(s.docOf(0).strokes, hasLength(1));
    });

    testWidgets('página com 5.000 traços monta e desenha sem exceção', (tester) async {
      var doc = PageDoc.empty;
      final strokes = <Stroke>[];
      for (var i = 0; i < 5000; i++) {
        final y = (i % 100) * 13.0 + 20;
        final x = (i ~/ 100) * 18.0 + 10;
        strokes.add(
          Stroke(
            id: newInkId(),
            tool: PenTool.values[i % 4],
            argb: 0xFFEFE9F7,
            width: 3,
            points: [
              for (var k = 0; k < 24; k++)
                InkPoint(x + k * 0.8, y + (k % 5) * 0.7, 0.3 + (k % 7) * 0.08),
            ],
          ),
        );
      }
      doc = doc.withStrokes(strokes);
      final s = FakeSession(docs: [doc]);
      final sw = Stopwatch()..start();
      await pumpNotebook(tester, s);
      await tester.pump(const Duration(milliseconds: 16));
      sw.stop();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('nb-committed')), findsOneWidget);
      // desenhar mais um traço em cima não pode quebrar nem regravar os 5.000 contornos
      await SimPointer(tester, PointerDeviceKind.stylus).drag(
        linePath(const Offset(100, 100), const Offset(700, 150), n: 30),
      );
      expect(s.docOf(0).strokes, hasLength(5001));
      // ignore: avoid_print
      print('PERF 5000 traços: montagem ${sw.elapsedMilliseconds} ms');
    });
  });
}
