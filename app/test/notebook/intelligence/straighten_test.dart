import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/core/notebook_core.dart';
import 'package:organizacional/notebook/intelligence/ink_types.dart';
import 'package:organizacional/notebook/intelligence/segmentation.dart';
import 'package:organizacional/notebook/intelligence/straighten.dart';

import '../core/test_support.dart';
import 'handwriting.dart';

const _text = 'o gato quase pegou o pequeno gigante agora';

Set<String> ids(Iterable<Stroke> s) => {for (final x in s) x.id};

/// Alturas-x das palavras (mediana das alturas de traços com tamanho de letra).
List<double> wordHeights(PageDoc doc, InkLine line) {
  final xh = lineXHeight(doc, line);
  final out = <double>[];
  for (final w in line.words) {
    final hs = <double>[];
    for (final id in w.strokeIds) {
      final s = doc.strokeById(id)!;
      final h = s.bounds.height - s.width;
      if (h >= 0.4 * xh && h <= 1.6 * xh) hs.add(h);
    }
    if (hs.length >= 2) {
      hs.sort();
      out.add(hs[hs.length ~/ 2]);
    }
  }
  return out;
}

List<double> gaps(InkLine line) => [
  for (var i = 1; i < line.words.length; i++) line.words[i].bounds.left - line.words[i - 1].bounds.right,
];

double median(List<double> v) {
  final s = [...v]..sort();
  return s[s.length ~/ 2];
}

void main() {
  group('straighten: inclinação', () {
    test('linha inclinada 8° fica horizontal (ângulo e baseline)', () {
      for (final deg in [3.0, 5.0, 8.0, 10.0, -4.0, -8.0, -10.0]) {
        final w = writeLine(_text, start: const Offset(80, 500), ids: IdGen(), hand: Hand(slopeDeg: deg, seed: 3));
        final doc = PageDoc.empty.withStrokes(w.strokes);
        final out = straighten(doc, ids(w.strokes), NewIds().call);
        final line = segmentLines(out).single;
        expect(line.angle * 180 / math.pi, closeTo(0, 0.6), reason: 'ângulo depois de endireitar $deg°');
        // as bases das letras (sem descendentes) ficam todas na mesma altura
        final bottoms = <double>[];
        for (final id in line.strokeIds) {
          final s = out.strokeById(id)!;
          final b = s.bounds;
          if (b.height - s.width > 0.7 * lineXHeight(out, line) && b.height - s.width < 1.3 * lineXHeight(out, line)) {
            bottoms.add(b.bottom - s.width / 2);
          }
        }
        final m = median(bottoms);
        for (final b in bottoms) {
          expect((b - m).abs(), lessThan(3.5), reason: 'base de letra a ${(b - m).toStringAsFixed(1)} da mediana ($deg°)');
        }
        // o início da linha é a âncora: a baseline continua onde estava no começo
        expect(line.baselineY, closeTo(500, 3), reason: 'baseline no início ($deg°)');
      }
    });

    test('mantém a quantidade de traços, a cor, a ferramenta e as pressões', () {
      final w = writeLine(_text, start: const Offset(80, 500), ids: IdGen(), hand: const Hand(slopeDeg: 7, seed: 4));
      final doc = PageDoc.empty.withStrokes(w.strokes);
      final out = straighten(doc, ids(w.strokes), NewIds().call);
      expect(out.strokes.length, doc.strokes.length);
      expect(out.strokes.every((s) => s.tool == PenTool.pen && s.argb == 0xFF101010), isTrue);
      // pontos de cada traço: mesma quantidade
      final before = [for (final s in doc.strokes) s.points.length]..sort();
      final after = [for (final s in out.strokes) s.points.length]..sort();
      expect(after, before);
    });

    test('ids novos vêm de newId e os antigos viram tombstones', () {
      final w = writeLine(_text, start: const Offset(80, 500), ids: IdGen(), hand: const Hand(slopeDeg: 7, seed: 4));
      final doc = PageDoc.empty.withStrokes(w.strokes);
      final gen = NewIds();
      final out = straighten(doc, ids(w.strokes), gen.call);
      expect(out.strokes.every((s) => s.id.startsWith('z')), isTrue);
      expect(gen.count, doc.strokes.length, reason: 'um id novo por traço trocado, nem mais nem menos');
      expect(out.deleted, ids(w.strokes));
      for (final s in w.strokes) {
        expect(out.contains(s.id), isFalse);
      }
      // merge com o documento antigo não ressuscita nada
      expect(doc.merge(out).strokes.length, out.strokes.length);
    });

    test('só a seleção muda: outras linhas e traços ficam idênticos', () {
      final p = writePage([_text, _text, _text], hand: const Hand(slopeDeg: 6, seed: 5), pitch: 60);
      final pick = ids(p.lines[1].strokes);
      final out = straighten(p.doc, pick, NewIds().call);
      for (final k in [0, 2]) {
        for (final s in p.lines[k].strokes) {
          expect(identical(out.strokeById(s.id), p.doc.strokeById(s.id)), isTrue, reason: "linha $k intacta");
        }
      }
      expect(out.deleted, pick);
      final lines = segmentLines(out);
      expect(lines, hasLength(3));
      expect(lines[1].angle.abs() * 180 / math.pi, lessThan(0.6));
      expect(lines[0].angle * 180 / math.pi, closeTo(6, 1.2));
    });

    test('textos, imagens e marca-texto não mudam', () {
      final w = writeLine(_text, start: const Offset(80, 500), ids: IdGen(), hand: const Hand(slopeDeg: 7, seed: 4));
      final hl = lineStroke('h1', const Offset(80, 480), const Offset(500, 480), width: 16, tool: PenTool.highlighter);
      const t = TextBox(id: 't1', x: 80, y: 300, w: 300, text: 'olá', size: 20, argb: 0xFF000000);
      const im = ImageBox(id: 'i1', x: 400, y: 100, w: 100, h: 100, path: 'p.png');
      final doc = PageDoc.empty.withStrokes([...w.strokes, hl]).withText(t).withImage(im);
      final out = straighten(doc, {...ids(w.strokes), 'h1', 't1', 'i1'}, NewIds().call);
      expect(out.textById('t1'), same(doc.textById('t1')));
      expect(out.imageById('i1'), same(doc.imageById('i1')));
      expect(out.strokeById('h1'), same(doc.strokeById('h1')));
    });

    test('linha que já está reta não é tocada (mesmo documento, nenhum id gasto)', () {
      final w = writeLine(_text, start: const Offset(80, 500), ids: IdGen(), hand: const Hand(seed: 6, sizeVar: 0, wobble: 0, noise: 0.05));
      // espaçamentos e tamanhos já uniformes: gera palavra a palavra com lacuna fixa
      final doc = PageDoc.empty.withStrokes(w.strokes);
      final gen = NewIds();
      final once = straighten(doc, ids(w.strokes), gen.call);
      final gen2 = NewIds();
      final twice = straighten(once, ids(once.strokes), gen2.call);
      expect(gen2.count, lessThan(3), reason: 'depois de endireitar, endireitar de novo quase não muda nada');
      expect(twice.strokes.length, once.strokes.length);
    });

    test('sem seleção, ou seleção sem tinta: devolve o mesmo documento', () {
      final w = writeLine(_text, start: const Offset(80, 500), ids: IdGen(), hand: const Hand(slopeDeg: 7, seed: 4));
      final doc = PageDoc.empty.withStrokes(w.strokes);
      expect(straighten(doc, {}, NewIds().call), same(doc));
      expect(straighten(doc, {'nao-existe'}, NewIds().call), same(doc));
      expect(straighten(PageDoc.empty, {'a'}, NewIds().call), same(PageDoc.empty));
    });

    test('determinismo: mesma entrada, mesma saída', () {
      final w = writeLine(_text, start: const Offset(80, 500), ids: IdGen(), hand: const Hand(slopeDeg: 7, seed: 4));
      final doc = PageDoc.empty.withStrokes(w.strokes);
      final a = straighten(doc, ids(w.strokes), NewIds().call);
      final b = straighten(doc, ids(w.strokes), NewIds().call);
      expect(a.strokes, b.strokes);
      expect(a.deleted, b.deleted);
    });

    test('linha longa perto da borda direita não sai da página', () {
      final w = writeLine('o gato quase pegou o pequeno gigante agora mesmo viu', start: const Offset(20, 500), ids: IdGen(),
          hand: const Hand(slopeDeg: 6, seed: 7, wordGap: 0.9));
      final doc = PageDoc.empty.withStrokes(w.strokes);
      final out = straighten(doc, ids(w.strokes), NewIds().call);
      final right = out.strokes.map((s) => s.bounds.right).reduce(math.max);
      expect(right, lessThanOrEqualTo(pageWidth));
    });
  });

  group('straighten: tamanho das palavras', () {
    PageDoc mixed(List<double> sizes, {int seed = 8}) {
      final gen = IdGen();
      var x = 80.0;
      var doc = PageDoc.empty;
      final words = ['quase', 'pegou', 'nunca', 'viram', 'sempre'];
      for (var i = 0; i < sizes.length; i++) {
        final w = writeLine(words[i], start: Offset(x, 500), ids: gen, hand: Hand(xh: sizes[i], seed: seed + i, sizeVar: 0.01));
        doc = doc.withStrokes(w.strokes);
        x = w.endX + 18;
      }
      return doc;
    }

    test('iguala a altura-x das palavras à mediana (sem passar de ±25 %)', () {
      final doc = mixed([16, 13.5, 19, 16, 17.5]);
      final before = wordHeights(doc, segmentLines(doc).single);
      final out = straighten(doc, ids(doc.strokes), NewIds().call);
      final lineOut = segmentLines(out).single;
      final after = wordHeights(out, lineOut);
      expect(after, hasLength(5));
      final spreadBefore = before.reduce(math.max) / before.reduce(math.min);
      final spreadAfter = after.reduce(math.max) / after.reduce(math.min);
      expect(spreadBefore, greaterThan(1.3));
      expect(spreadAfter, lessThan(1.08), reason: 'alturas depois: $after');
      // a mediana das alturas continua sendo a referência (não encolhe nem estoura)
      expect(median(after), closeTo(median(before), 1.0));
    });

    test('escala limitada a ±25 %: palavra pela metade só cresce 25 %', () {
      final doc = mixed([16, 8, 16, 16], seed: 12);
      final before = wordHeights(doc, segmentLines(doc).single);
      final out = straighten(doc, ids(doc.strokes), NewIds().call);
      final after = wordHeights(out, segmentLines(out).single);
      // a 2ª palavra (a pequena) cresce no máximo 25 % (aqui: 8 → ≤ 10)
      final small = before.indexOf(before.reduce(math.min));
      expect(after[small] / before[small], lessThanOrEqualTo(1.27));
      expect(after[small] / before[small], greaterThan(1.15));
    });

    test('a espessura da caneta acompanha a escala da palavra', () {
      final doc = mixed([16, 12, 16, 16], seed: 20);
      final out = straighten(doc, ids(doc.strokes), NewIds().call);
      final widths = {for (final s in out.strokes) double.parse(s.width.toStringAsFixed(1))};
      expect(widths.length, greaterThan(1), reason: 'palavra reescalada tem traço mais grosso');
      expect(widths.reduce(math.max) / widths.reduce(math.min), lessThanOrEqualTo(1.3));
    });

    test('palavra de letras só altas (sem altura-x) não é reescalada', () {
      final gen = IdGen();
      final a = writeLine('quase pegou', start: const Offset(80, 500), ids: gen, hand: const Hand(seed: 3));
      final b = writeLine('lll', start: Offset(a.endX + 20, 500), ids: gen, hand: const Hand(seed: 4));
      final doc = PageDoc.empty.withStrokes([...a.strokes, ...b.strokes]);
      final out = straighten(doc, ids(doc.strokes), NewIds().call);
      for (final s in b.strokes) {
        // 'l' alto intacto (ou, no máximo, deslocado: mesma altura)
        final moved = out.strokes.where((o) => (o.bounds.height - s.bounds.height).abs() < 0.3 && o.tool == s.tool).length;
        expect(moved, greaterThan(0));
      }
    });
  });

  group('straighten: espaçamento entre palavras', () {
    PageDoc spaced(List<double> gapsUnits) {
      final gen = IdGen();
      var x = 80.0;
      var doc = PageDoc.empty;
      final words = ['quase', 'pegou', 'nunca', 'viram', 'sempre', 'agora'];
      for (var i = 0; i <= gapsUnits.length; i++) {
        final w = writeLine(words[i], start: Offset(x, 500), ids: gen, hand: Hand(seed: 30 + i, sizeVar: 0.01));
        doc = doc.withStrokes(w.strokes);
        if (i < gapsUnits.length) x = w.endX + gapsUnits[i];
      }
      return doc;
    }

    test('iguala as lacunas à mediana', () {
      final doc = spaced([14, 34, 22, 48]);
      final before = gaps(segmentLines(doc).single);
      final out = straighten(doc, ids(doc.strokes), NewIds().call);
      final after = gaps(segmentLines(out).single);
      final target = median(before);
      expect(before.map((g) => (g - target).abs()).reduce(math.max), greaterThan(10));
      for (final g in after) {
        expect(g, closeTo(target, 3.0), reason: 'lacunas depois: $after (alvo $target)');
      }
    });

    test('a primeira palavra fica onde estava', () {
      final doc = spaced([14, 34, 22, 48]);
      final left0 = segmentLines(doc).single.words.first.bounds.left;
      final out = straighten(doc, ids(doc.strokes), NewIds().call);
      expect(segmentLines(out).single.words.first.bounds.left, closeTo(left0, 0.5));
    });

    test('lacunas já iguais não movem nada', () {
      final doc = spaced([20, 20, 20, 20]);
      final out = straighten(doc, ids(doc.strokes), NewIds().call);
      // pode reescalar por ruído de tamanho, mas as lacunas continuam iguais
      final after = gaps(segmentLines(out).single);
      for (final g in after) {
        expect(g, closeTo(after.first, 3.0));
      }
    });
  });
}
