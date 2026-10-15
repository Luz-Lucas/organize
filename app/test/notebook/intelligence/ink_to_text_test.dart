import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/core/notebook_core.dart';
import 'package:organizacional/notebook/intelligence/gestures.dart';
import 'package:organizacional/notebook/intelligence/ink_to_text.dart';
import 'package:organizacional/notebook/intelligence/segmentation.dart';
import 'package:organizacional/notebook/intelligence/spell_checker.dart';
import 'package:organizacional/notebook/intelligence/transcript.dart';

import 'fake_recognizer.dart';
import 'handwriting.dart';

/// Escreve [lines] (uma por linha) e devolve o documento e um reconhecedor que
/// "lê" exatamente as palavras escritas cujos traços foram pedidos.
({PageDoc doc, List<Written> written, FakeInkRecognizer rec}) page(
  List<String> lines, {
  int argb = 0xFF101010,
  Set<String> unreadable = const {},
}) {
  final gen = IdGen();
  var doc = PageDoc.empty;
  final written = <Written>[];
  for (var i = 0; i < lines.length; i++) {
    final w = writeLine(lines[i], start: Offset(80, 300.0 + i * 70), ids: gen, hand: Hand(seed: 7 + i), argb: argb);
    written.add(w);
    doc = doc.withStrokes(w.strokes);
  }
  final words = <(List<String>, String)>[
    for (var i = 0; i < lines.length; i++)
      for (final (k, text) in lines[i].split(' ').indexed) (written[i].wordIds[k], text),
  ];
  final rec = FakeInkRecognizer(resolve: (strokes) {
    final ids = {for (final s in strokes) s.id};
    final parts = [
      for (final (wid, text) in words)
        if (wid.every(ids.contains) && !unreadable.contains(text)) text,
    ];
    return parts.isEmpty ? const [] : [parts.join(' ')];
  });
  return (doc: doc, written: written, rec: rec);
}

class _Spell extends SpellChecker {
  _Spell(this.wrong);
  final Map<String, List<String>> wrong;
  final asked = <String>[];

  @override
  Future<List<String>?> suggestions(String word) async {
    asked.add(word);
    return wrong[word];
  }
}

void main() {
  group('convertInkToText', () {
    test('cada linha vira uma caixa de texto no lugar, com a cor da escrita', () async {
      final p = page(['o gato quase', 'pegou um rato'], argb: 0xFF2244AA);
      final ids = {for (final s in p.doc.strokes) s.id};
      final r = await convertInkToText(p.doc, ids, p.rec, newId: NewIds().call);
      expect(r.converted, 2);
      expect(r.failed, 0);
      expect(r.doc.strokes, isEmpty);
      final texts = [...r.doc.texts]..sort((a, b) => a.y.compareTo(b.y));
      expect(texts.map((t) => t.text), ['o gato quase', 'pegou um rato']);
      expect(r.textIds, texts.map((t) => t.id).toSet());
      for (final t in texts) {
        expect(t.argb, 0xFF2244AA);
        expect(t.font, isNull);
        // Mais ou menos onde a linha estava, e larga o bastante para não quebrar.
        expect(t.x, closeTo(80, 15));
        expect(t.w, greaterThanOrEqualTo(t.text.length * t.size * 0.55));
      }
      expect(texts[0].y, lessThan(texts[1].y));
      final lines = segmentLines(p.doc);
      for (var i = 0; i < 2; i++) {
        expect(texts[i].y + texts[i].size * 0.95, closeTo(lineBaselineAt(lines[i], lines[i].bounds.left), 2));
      }
      // Os traços antigos viram tombstones (a exclusão se propaga no merge).
      expect(r.doc.deleted, containsAll(ids));
    });

    test('linha com palavra ilegível fica como escrita', () async {
      final p = page(['o gato quase', 'pegou um rato'], unreadable: {'rato'});
      final ids = {for (final s in p.doc.strokes) s.id};
      final r = await convertInkToText(p.doc, ids, p.rec, newId: NewIds().call);
      expect(r.converted, 1);
      expect(r.failed, 1);
      expect(r.doc.texts.single.text, 'o gato quase');
      final kept = {for (final s in r.doc.strokes) s.id};
      expect(kept, {for (final w in p.written[1].wordIds) ...w});
    });

    test('só a seleção é convertida; marca-texto e reconhecimento vazio não mexem em nada', () async {
      final p = page(['o gato quase', 'pegou um rato']);
      final first = {for (final w in p.written[0].wordIds) ...w};
      final r = await convertInkToText(p.doc, first, p.rec, newId: NewIds().call);
      expect(r.doc.texts.single.text, 'o gato quase');
      expect(r.doc.strokes.length, p.written[1].strokes.length);

      final none = await convertInkToText(p.doc, first, FakeInkRecognizer(), newId: NewIds().call);
      expect(identical(none.doc, p.doc), isTrue);
      expect(none.failed, 1);

      final hl = Stroke(
        id: 'hl',
        tool: PenTool.highlighter,
        argb: 0x80FFFF00,
        width: 20,
        points: const [InkPoint(10, 10, 0.5), InkPoint(200, 10, 0.5)],
      );
      final withHl = p.doc.withStroke(hl);
      final onlyHl = await convertInkToText(withHl, {'hl'}, p.rec);
      expect(identical(onlyHl.doc, withHl), isTrue);
    });
  });

  group('replaceWordWithText', () {
    test('troca só a palavra, em fonte manuscrita, na cor dela', () {
      final p = page(['o gatto quase'], argb: 0xFF883300);
      final line = segmentLines(p.doc).single;
      final word = line.words[1];
      final r = replaceWordWithText(p.doc, line, word, 'gato', newId: NewIds().call);
      final t = r.doc.texts.single;
      expect(t.id, r.textId);
      expect(t.text, 'gato');
      expect(t.font, kHandwritingFont);
      expect(t.argb, 0xFF883300);
      expect(t.x, closeTo(word.bounds.left, 0.1));
      final left = {for (final s in r.doc.strokes) s.id};
      expect(left.intersection(word.strokeIds.toSet()), isEmpty);
      expect(left, containsAll([...line.words[0].strokeIds, ...line.words[2].strokeIds]));
      // Altura parecida com a da escrita (nem minúscula nem gigante).
      final xh = lineXHeight(p.doc, line);
      expect(t.size, inInclusiveRange(xh * 1.5, xh * 3.5));
      // A linha de base do texto (≈ 0,95 do tamanho abaixo do topo) cai na da escrita.
      expect(t.y + t.size * 0.95, closeTo(lineBaselineAt(line, word.bounds.left), 2));
    });
  });

  group('gestureEdit', () {
    test('rabisco sobre uma palavra apaga a palavra e o traço do gesto não entra', () {
      final p = page(['o gato quase pegou']);
      final word = segmentLines(p.doc).single.words[1];
      final b = word.bounds;
      final pts = <InkPoint>[];
      for (var k = 0; k <= 6; k++) {
        final l2r = k.isEven;
        for (var i = 0; i < 8; i++) {
          final t = i / 8;
          final x = l2r ? b.left + b.width * t : b.right - b.width * t;
          final y = b.top + b.height * (k.isEven ? 0.15 + 0.7 * t : 0.85 - 0.7 * t);
          pts.add(InkPoint(x, y, 0.5));
        }
      }
      final scratch = Stroke(id: 'zz', tool: PenTool.pen, argb: 0xFF101010, width: 2.2, points: pts);
      final r = gestureEdit(p.doc, scratch, newId: NewIds().call);
      expect(r, isNotNull);
      expect(r!.gesture, isA<ScratchOut>());
      expect(r.doc.strokeById('zz'), isNull);
      final left = {for (final s in r.doc.strokes) s.id};
      expect(left.intersection(word.strokeIds.toSet()), isEmpty);
      expect(left.length, p.doc.strokes.length - word.strokeIds.length);
    });

    test('escrita normal, marca-texto e risquinho não são gesto', () {
      final p = page(['o gato quase pegou']);
      // Escrevendo a linha seguinte traço a traço: nenhum vira gesto.
      final more = writeLine('minimum uva', start: const Offset(80, 370), ids: IdGen('m'), hand: const Hand(seed: 3));
      var doc = p.doc;
      for (final s in more.strokes) {
        expect(gestureEdit(doc, s), isNull, reason: 'traço ${s.id} de "minimum uva"');
        doc = doc.withStroke(s);
      }
      final hl = Stroke(
        id: 'hl',
        tool: PenTool.highlighter,
        argb: 0x80FFFF00,
        width: 20,
        points: [for (var i = 0; i < 20; i++) InkPoint(80.0 + i * 10, 290 + 6 * math.sin(i.toDouble()), 0.5)],
      );
      expect(gestureEdit(p.doc, hl), isNull);
      expect(gestureEdit(PageDoc.empty, more.strokes.first), isNull);
    });
  });

  group('findSpellMarks', () {
    test('marca só as palavras que o corretor recusa, mantendo a pontuação nas sugestões', () async {
      final p = page(['o gatto, quase']);
      final t = await transcribe(p.doc, FakeInkRecognizer(resolve: (s) => ['o gatto, quase']));
      final spell = _Spell({'gatto': ['gato', 'gatos']});
      final marks = await findSpellMarks(p.doc, t, spell);
      expect(marks, hasLength(1));
      expect(marks.single.text, 'gatto,');
      expect(marks.single.suggestions, ['gato,', 'gatos,']);
      expect(spell.asked, isNot(contains('o')), reason: 'palavra de uma letra não é consultada');
    });

    test('dicionário pessoal, número e corretor com erro não marcam', () async {
      // A segunda palavra é "lida" como número.
      final p = page(['gatto um xpto']);
      final t = await transcribe(p.doc, FakeInkRecognizer(resolve: (s) => ['gatto 42 xpto']));
      final marks = await findSpellMarks(p.doc, t, _Spell({'gatto': ['gato'], 'xpto': []}), ignored: {'gatto'});
      expect(marks.map((m) => m.text), ['xpto']);
      expect(marks.single.suggestions, isEmpty);

      final boom = await findSpellMarks(p.doc, t, _Boom());
      expect(boom, isEmpty);
      expect(await findSpellMarks(p.doc, PageTranscript.empty, _Spell({'gatto': []})), isEmpty);
    });

    test('ignoreKey: minúsculas e sem pontuação', () {
      expect(ignoreKey('Gatto,'), 'gatto');
      expect(ignoreKey('(Lucas)'), 'lucas');
    });
  });
}

class _Boom extends SpellChecker {
  @override
  Future<List<String>?> suggestions(String word) async => throw StateError('canal');
}
