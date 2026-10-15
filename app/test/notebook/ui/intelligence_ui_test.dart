import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide TextBox;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/core/notebook_core.dart';
import 'package:organizacional/notebook/intelligence/recognizer.dart';
import 'package:organizacional/notebook/intelligence/segmentation.dart';
import 'package:organizacional/notebook/intelligence/spell_checker.dart';
import 'package:organizacional/notebook/intelligence/transcript.dart';
import 'package:organizacional/notebook/ui/notebook_screen.dart';
import 'package:organizacional/ui/org_theme.dart';

import '../intelligence/fake_recognizer.dart';
import '../intelligence/handwriting.dart';
import 'menu_support.dart';
import 'ui_support.dart';

/// Uma linha escrita à mão com baseline em y = 400 e o reconhecedor que a "lê".
({PageDoc doc, Written w, FakeInkRecognizer rec}) written(String text, {Hand hand = const Hand(seed: 5)}) {
  final w = writeLine(text, start: const Offset(80, 400), ids: IdGen(), hand: hand);
  final words = text.split(' ');
  final rec = FakeInkRecognizer(resolve: (strokes) {
    final ids = {for (final s in strokes) s.id};
    final parts = [
      for (var i = 0; i < words.length; i++)
        if (w.wordIds[i].every(ids.contains)) words[i],
    ];
    return parts.isEmpty ? const [] : [parts.join(' ')];
  });
  return (doc: PageDoc.empty.withStrokes(w.strokes), w: w, rec: rec);
}

Future<void> pumpWith(WidgetTester tester, FakeSession session, NotebookIntelligence intel) async {
  await setSurface(tester, const Size(800, 1300));
  await tester.pumpWidget(
    MaterialApp(
      theme: buildOrgTheme(orgThemes.first, googleFonts: false),
      home: NotebookScreen(noteId: 'n1', session: session, title: 'Caderno', intelligence: intel),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> lassoAll(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('nb-tool-lasso')));
  await tester.pump();
  await SimPointer(tester, PointerDeviceKind.stylus).drag(const [
    Offset(30, 320),
    Offset(960, 320),
    Offset(960, 470),
    Offset(30, 470),
    Offset(30, 322),
  ]);
}

/// Rabisco (zigue-zague horizontal) sobre [b], em unidades de página.
List<Offset> scribblePath(Rect b, {int passes = 6}) => [
  for (var k = 0; k <= passes; k++)
    for (var i = 0; i < 8; i++)
      Offset(
        k.isEven ? b.left + b.width * i / 8 : b.right - b.width * i / 8,
        b.top + b.height * (k.isEven ? 0.15 + 0.7 * i / 8 : 0.85 - 0.7 * i / 8),
      ),
];

/// A lista rolável em volta de [anchorKey] (ou dentro dele, no caso do menu).
Finder scrollableNear(String anchorKey) {
  final anchor = find.byKey(ValueKey(anchorKey));
  final inside = find.descendant(of: anchor, matching: find.byType(Scrollable));
  if (inside.evaluate().isNotEmpty) return inside.first;
  return find.ancestor(of: anchor, matching: find.byType(Scrollable)).first;
}

/// Rola a lista que contém [anchorKey] até [key] aparecer e toca nele.
Future<void> scrollTap(WidgetTester tester, String key, {required String anchorKey, Offset delta = const Offset(-120, 0)}) async {
  final target = find.byKey(ValueKey(key));
  await tester.dragUntilVisible(target, scrollableNear(anchorKey), delta);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

/// Abre o menu Ferramentas, rola até [key] e toca.
Future<void> menuTap(WidgetTester tester, String key) async {
  // Um aviso (SnackBar) da ação anterior cobre a barra de ferramentas.
  tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).removeCurrentSnackBar();
  await tester.pumpAndSettle();
  await openMenu(tester);
  await scrollTap(tester, key, anchorKey: 'nb-tools-menu', delta: const Offset(0, -200));
  await closeMenu(tester);
}

class FakeSpell extends SpellChecker {
  FakeSpell(this.wrong);
  final Map<String, List<String>> wrong;

  @override
  Future<List<String>?> suggestions(String word) async => wrong[word];
}

void main() {
  group('laço: converter em texto e endireitar', () {
    testWidgets('converte a seleção numa caixa de texto e desfazer traz a escrita de volta', (tester) async {
      final p = written('o gato quase');
      final s = FakeSession(docs: [p.doc]);
      await pumpWith(tester, s, NotebookIntelligence(recognizer: p.rec));
      await lassoAll(tester);
      expect(find.byKey(const ValueKey('nb-sel-convert-hint')), findsNothing);
      await scrollTap(tester, 'nb-sel-convert', anchorKey: 'nb-sel-delete');

      final doc = s.docOf(0);
      expect(doc.strokes, isEmpty);
      expect(doc.texts.single.text, 'o gato quase');
      expect(doc.texts.single.argb, 0xFF101010);

      await tester.tap(find.byKey(const ValueKey('nb-undo')));
      await tester.pump();
      expect(s.docOf(0).texts, isEmpty);
      expect(s.docOf(0).strokes, hasLength(p.doc.strokes.length));
    });

    testWidgets('sem o modelo baixado avisa e não mexe na página', (tester) async {
      final p = written('o gato quase');
      p.rec.ready = false;
      final s = FakeSession(docs: [p.doc]);
      await pumpWith(tester, s, NotebookIntelligence(recognizer: p.rec));
      await lassoAll(tester);
      await scrollTap(tester, 'nb-sel-convert', anchorKey: 'nb-sel-delete');
      expect(find.text('Baixe o modelo de escrita em Ajustes → Escrita à mão.'), findsOneWidget);
      expect(s.updates, isEmpty);
      expect(p.rec.calls, isEmpty);
    });

    testWidgets('nada reconhecido: avisa e a escrita fica', (tester) async {
      final p = written('o gato quase');
      final s = FakeSession(docs: [p.doc]);
      await pumpWith(tester, s, NotebookIntelligence(recognizer: FakeInkRecognizer()));
      await lassoAll(tester);
      await scrollTap(tester, 'nb-sel-convert', anchorKey: 'nb-sel-delete');
      expect(find.text('Não deu para reconhecer a escrita.'), findsOneWidget);
      expect(s.updates, isEmpty);
    });

    testWidgets('sem reconhecedor (Linux): esconde a conversão com a dica, mas endireitar funciona', (tester) async {
      final p = written('o gato quase pegou', hand: const Hand(seed: 5, slopeDeg: 7));
      final s = FakeSession(docs: [p.doc]);
      await pumpWith(tester, s, NotebookIntelligence.off);
      await lassoAll(tester);
      await scrollTap(tester, 'nb-sel-straighten', anchorKey: 'nb-sel-delete');
      await tester.dragUntilVisible(find.byKey(const ValueKey('nb-sel-convert-hint')), scrollableNear('nb-sel-delete'), const Offset(-120, 0));
      expect(find.byKey(const ValueKey('nb-sel-convert')), findsNothing);
      expect(find.text('Converter em texto: disponível no Android'), findsOneWidget);

      final after = s.docOf(0);
      expect(after.strokes, hasLength(p.doc.strokes.length));
      final line = segmentLines(after).single;
      expect(line.angle.abs(), lessThan(segmentLines(p.doc).single.angle.abs()));
      expect(line.angle.abs(), lessThan(0.02));
    });
  });

  group('menu da página', () {
    testWidgets('converter, endireitar e copiar o texto da página', (tester) async {
      final p = written('o gato quase', hand: const Hand(seed: 5, slopeDeg: 6));
      final s = FakeSession(docs: [p.doc]);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await pumpWith(
        tester,
        s,
        NotebookIntelligence(recognizer: p.rec, recognizedTextOf: (id) => id == s.idOf(0) ? 'texto do servidor' : ''),
      );

      await menuTap(tester, 'nb-page-copy-text');
      expect(copied, 'texto do servidor');
      expect(find.text('Texto da página copiado.'), findsOneWidget);

      await menuTap(tester, 'nb-page-convert');
      expect(s.docOf(0).strokes, isEmpty);
      expect(s.docOf(0).texts.single.text, 'o gato quase');
    });

    testWidgets('endireitar a página deixa a linha horizontal', (tester) async {
      final p = written('o gato quase pegou', hand: const Hand(seed: 5, slopeDeg: 6));
      final s = FakeSession(docs: [p.doc]);
      await pumpWith(tester, s, NotebookIntelligence.off);
      await menuTap(tester, 'nb-page-straighten');
      expect(s.docOf(0).strokes, hasLength(p.doc.strokes.length));
      expect(segmentLines(s.docOf(0)).single.angle.abs(), lessThan(0.02));
    });

    testWidgets('sem reconhecedor: conversão desabilitada com a dica; sem texto avisa ao copiar', (tester) async {
      final s = FakeSession(docs: [written('o gato').doc]);
      await pumpWith(tester, s, NotebookIntelligence.off);
      await openMenu(tester);
      await tester.dragUntilVisible(find.byKey(const ValueKey('nb-page-convert-hint')), scrollableNear('nb-tools-menu'), const Offset(0, -200));
      expect(find.byKey(const ValueKey('nb-page-convert')), findsNothing);
      await scrollTap(tester, 'nb-page-copy-text', anchorKey: 'nb-tools-menu', delta: const Offset(0, -200));
      expect(find.text('Ainda não há texto reconhecido nesta página.'), findsOneWidget);
    });
  });

  group('gestos de edição', () {
    testWidgets('rabisco sobre uma palavra apaga a palavra; desfazer devolve', (tester) async {
      final p = written('o gato quase pegou');
      final s = FakeSession(docs: [p.doc]);
      await pumpWith(tester, s, const NotebookIntelligence(gestures: true));
      final word = segmentLines(p.doc).single.words[1];
      await SimPointer(tester, PointerDeviceKind.stylus).drag(scribblePath(word.bounds));
      final doc = s.docOf(0);
      expect(doc.strokes.length, p.doc.strokes.length - word.strokeIds.length);
      for (final id in word.strokeIds) {
        expect(doc.strokeById(id), isNull);
      }
      expect(find.text('Apagado com o rabisco'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('nb-undo')));
      await tester.pump();
      expect(s.docOf(0).strokes, hasLength(p.doc.strokes.length));
    });

    testWidgets('∧ entre duas palavras abre espaço (as palavras seguintes andam para a direita)', (tester) async {
      final p = written('o gato quase pegou');
      final s = FakeSession(docs: [p.doc]);
      await pumpWith(tester, s, const NotebookIntelligence(gestures: true));
      final line = segmentLines(p.doc).single;
      final x = (line.words[1].bounds.right + line.words[2].bounds.left) / 2;
      final yb = lineBaselineAt(line, x) + 2;
      const xh = 16.0;
      await SimPointer(tester, PointerDeviceKind.stylus).drag([
        for (var i = 0; i <= 8; i++) Offset.lerp(Offset(x - xh / 2, yb), Offset(x, yb - xh), i / 8)!,
        for (var i = 1; i <= 8; i++) Offset.lerp(Offset(x, yb - xh), Offset(x + xh / 2, yb), i / 8)!,
      ]);
      final after = s.docOf(0);
      expect(after.strokes, hasLength(p.doc.strokes.length), reason: 'o ∧ não vira tinta');
      double leftOf(PageDoc d) => segmentLines(d).single.words.last.bounds.left;
      expect(leftOf(after), greaterThan(leftOf(p.doc) + 20));
      expect(find.text('Espaço aberto'), findsOneWidget);
    });

    testWidgets('com os gestos desligados o rabisco vira tinta', (tester) async {
      final p = written('o gato quase pegou');
      final s = FakeSession(docs: [p.doc]);
      await pumpWith(tester, s, NotebookIntelligence.off);
      final word = segmentLines(p.doc).single.words[1];
      await SimPointer(tester, PointerDeviceKind.stylus).drag(scribblePath(word.bounds));
      expect(s.docOf(0).strokes, hasLength(p.doc.strokes.length + 1));
      expect(find.text('Apagado com o rabisco'), findsNothing);
    });
  });

  group('corretor ortográfico', () {
    late StreamController<({String pageId, PageTranscript transcript})> transcripts;
    setUp(() => transcripts = StreamController.broadcast());
    tearDown(() => transcripts.close());

    Future<({FakeSession s, PageDoc doc, List<String> ignored})> setup(
      WidgetTester tester, {
      bool spellCheck = true,
    }) async {
      final p = written('o gatto quase');
      final s = FakeSession(docs: [p.doc]);
      final ignored = <String>[];
      await pumpWith(
        tester,
        s,
        NotebookIntelligence(
          recognizer: p.rec,
          spellChecker: FakeSpell({'gatto': ['gato', 'gatos']}),
          spellCheck: spellCheck,
          transcripts: transcripts.stream,
          onIgnoreWord: ignored.add,
        ),
      );
      final t = await transcribe(p.doc, p.rec);
      transcripts.add((pageId: s.idOf(0), transcript: t));
      await tester.pumpAndSettle();
      return (s: s, doc: p.doc, ignored: ignored);
    }

    testWidgets('sublinha a palavra errada; tocar com o laço e escolher a sugestão troca a escrita', (tester) async {
      final r = await setup(tester);
      expect(find.byKey(const ValueKey('nb-spell-0')), findsOneWidget);
      final word = segmentLines(r.doc).single.words[1];

      await tester.tap(find.byKey(const ValueKey('nb-tool-lasso')));
      await tester.pump();
      final pen = SimPointer(tester, PointerDeviceKind.stylus);
      await pen.down(word.bounds.center);
      await pen.up();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('nb-spell-sheet')), findsOneWidget);
      expect(find.text('gatos'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('nb-spell-sug-0')));
      await tester.pumpAndSettle();
      final doc = r.s.docOf(0);
      final t = doc.texts.single;
      expect(t.text, 'gato');
      expect(t.font, kHandwritingFont);
      for (final id in word.strokeIds) {
        expect(doc.strokeById(id), isNull);
      }
      expect(find.byKey(const ValueKey('nb-spell-0')), findsNothing);
    });

    testWidgets('com a caneta, só o toque no sublinhado abre as sugestões (o pingo em cima da palavra é tinta)', (tester) async {
      final r = await setup(tester);
      final word = segmentLines(r.doc).single.words[1];
      final dot = SimPointer(tester, PointerDeviceKind.stylus);
      await dot.down(Offset(word.bounds.center.dx, word.bounds.top + 2));
      await dot.up();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('nb-spell-sheet')), findsNothing);
      expect(r.s.docOf(0).strokes, hasLength(r.doc.strokes.length + 1));

      final tap = SimPointer(tester, PointerDeviceKind.stylus);
      await tap.down(Offset(word.bounds.center.dx, word.bounds.bottom + 5));
      await tap.up();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('nb-spell-sheet')), findsOneWidget);
      expect(r.s.docOf(0).strokes, hasLength(r.doc.strokes.length + 1), reason: 'o toque no sublinhado não vira tinta');
    });

    testWidgets('Ignorar tira o sublinhado e guarda a palavra no dicionário pessoal', (tester) async {
      final r = await setup(tester);
      final word = segmentLines(r.doc).single.words[1];
      await tester.tap(find.byKey(const ValueKey('nb-tool-lasso')));
      await tester.pump();
      final pen = SimPointer(tester, PointerDeviceKind.stylus);
      await pen.down(word.bounds.center);
      await pen.up();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nb-spell-ignore')));
      await tester.pumpAndSettle();
      expect(r.ignored, ['gatto']);
      expect(find.byKey(const ValueKey('nb-spell-0')), findsNothing);
      expect(r.s.updates, isEmpty);
    });

    testWidgets('corretor desligado: nada sublinhado e o toque do laço segue normal', (tester) async {
      final r = await setup(tester, spellCheck: false);
      expect(find.byKey(const ValueKey('nb-spell-0')), findsNothing);
      final word = segmentLines(r.doc).single.words[1];
      await tester.tap(find.byKey(const ValueKey('nb-tool-lasso')));
      await tester.pump();
      final pen = SimPointer(tester, PointerDeviceKind.stylus);
      await pen.down(word.bounds.center);
      await pen.up();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('nb-spell-sheet')), findsNothing);
    });

    testWidgets('a palavra apagada depois da transcrição perde o sublinhado', (tester) async {
      final r = await setup(tester);
      final word = segmentLines(r.doc).single.words[1];
      r.s.remoteDoc(0, r.doc.without(word.strokeIds));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('nb-spell-0')), findsNothing);
    });
  });

  test('NotebookIntelligence.off desliga tudo', () {
    const off = NotebookIntelligence.off;
    expect(off.gestures, isFalse);
    expect(off.spellCheck, isFalse);
    expect(off.recognizer, isA<NoopInkRecognizer>());
    expect(off.recognizer.supported, isFalse);
  });
}
