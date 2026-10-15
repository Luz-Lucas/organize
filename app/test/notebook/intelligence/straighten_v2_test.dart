import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/core/notebook_core.dart';
import 'package:organizacional/notebook/intelligence/ink_types.dart';
import 'package:organizacional/notebook/intelligence/segmentation.dart';
import 'package:organizacional/notebook/intelligence/straighten.dart';

import 'handwriting.dart';

Set<String> ids(Iterable<Stroke> s) => {for (final x in s) x.id};

final lined = ruleGuideFor(PageBackground.lined)!;

/// A baseline no meio da linha (onde se vê se ela está na pauta).
double baseOf(InkLine l) => lineBaselineAt(l, l.bounds.center.dx);

/// Escreve [text] com a baseline em [y] (x = [x]).
PageDoc line(String text, {double y = 400, double x = 80, Hand hand = const Hand(seed: 5), IdGen? gen}) =>
    PageDoc.empty.withStrokes(writeLine(text, start: Offset(x, y), ids: gen ?? IdGen(), hand: hand).strokes);

void main() {
  group('pautas da página', () {
    test('pautado: primeira pauta em 120, de 40 em 40, sem passar do pé da página', () {
      expect(lined.first, 120);
      expect(lined.spacing, 40);
      expect(lined.last, lessThanOrEqualTo(pageHeight - 30));
      expect(lined.last + lined.spacing, greaterThan(pageHeight - 30));
      expect(ruleGuideFor(PageBackground.grid)!.first, 40);
      expect(ruleGuideFor(PageBackground.blank), isNull);
      expect(lined.nearest(147), 1);
      expect(lined.nearest(60), isNull, reason: 'cabeçalho, acima das pautas');
    });

    test('a linha escrita entre pautas assenta na pauta mais próxima', () {
      final doc = line('o gato quase pegou', y: 147);
      final out = straighten(doc, ids(doc.strokes), NewIds().call, guide: lined);
      expect(baseOf(segmentLines(out).single), closeTo(160, 1.5));
    });

    test('duas linhas apertadas não caem na mesma pauta (de cima para baixo)', () {
      final gen = IdGen();
      // 306 e 330: as duas ficariam na pauta 320
      final doc = line('o gato quase', y: 306, gen: gen)
          .merge(line('pegou um rato', y: 330, gen: gen, hand: const Hand(seed: 9)));
      final out = straighten(doc, ids(doc.strokes), NewIds().call, guide: lined);
      final ls = segmentLines(out);
      expect(ls, hasLength(2));
      expect(baseOf(ls[0]), closeTo(320, 1.5));
      expect(baseOf(ls[1]), closeTo(360, 1.5));
    });

    test('escrita no cabeçalho (acima das pautas) não é puxada para a pauta', () {
      final doc = line('titulo da aula', y: 70);
      final out = straighten(doc, ids(doc.strokes), NewIds().call, guide: lined);
      expect(segmentLines(out).single.baselineY, closeTo(segmentLines(doc).single.baselineY, 1.5));
    });

    test('folha lisa: as linhas ficam na altura em que foram escritas', () {
      final doc = line('o gato quase pegou', y: 147);
      final out = straighten(doc, ids(doc.strokes), NewIds().call);
      expect(segmentLines(out).single.baselineY, closeTo(segmentLines(doc).single.baselineY, 1.5));
    });

    test('letra pequena demais para a pauta cresce; grande demais diminui (com limite)', () {
      final small = line('o gato quase', y: 400, hand: const Hand(seed: 5, xh: 7));
      final big = line('o gato quase', y: 400, hand: const Hand(seed: 5, xh: 32));
      double xh(PageDoc d) => lineXHeight(d, segmentLines(d).single);
      final s2 = straighten(small, ids(small.strokes), NewIds().call, guide: lined);
      final b2 = straighten(big, ids(big.strokes), NewIds().call, guide: lined);
      expect(xh(s2), greaterThan(xh(small) * 1.3));
      expect(xh(s2), lessThanOrEqualTo(xh(small) * 1.42));
      expect(xh(b2), closeTo(0.6 * 40, 2.5));
      // tamanho já bom para a pauta (≈ 16 em pautas de 40): não muda
      final ok = line('o gato quase', y: 400);
      final ok2 = straighten(ok, ids(ok.strokes), NewIds().call, guide: lined);
      expect(xh(ok2), closeTo(xh(ok), 0.8));
    });
  });

  group('legibilidade', () {
    test('letra inclinada (≈ 20°) fica em pé', () {
      final doc = line('o pequeno gigante tinha medo', hand: const Hand(seed: 3, slant: 0.36));
      final before = lineSlant(doc, segmentLines(doc).single)!;
      expect(before, greaterThan(0.25));
      final out = straighten(doc, ids(doc.strokes), NewIds().call);
      final after = lineSlant(out, segmentLines(out).single)!;
      expect(after.abs(), lessThan(0.1));
    });

    test('inclinação para a esquerda também é corrigida', () {
      final doc = line('o pequeno gigante tinha medo', hand: const Hand(seed: 3, slant: -0.3));
      final out = straighten(doc, ids(doc.strokes), NewIds().call);
      expect(lineSlant(out, segmentLines(out).single)!.abs(), lessThan(0.1));
    });

    test('itálico leve (≈ 5°) é da letra da pessoa: não mexe', () {
      final doc = line('o gato quase pegou', hand: const Hand(seed: 6, slant: 0.06, sizeVar: 0, wobble: 0, noise: 0.05));
      final before = lineSlant(doc, segmentLines(doc).single)!;
      expect(before, closeTo(0.06, 0.03));
      final out = straighten(doc, ids(doc.strokes), NewIds().call);
      expect(lineSlant(out, segmentLines(out).single)!, closeTo(before, 0.01));
    });

    test('palavra que "pulou" para baixo volta para a baseline', () {
      final gen = IdGen();
      final w = writeLine('o gato quase pegou', start: const Offset(80, 400), ids: gen, hand: const Hand(seed: 5, wobble: 0));
      var doc = PageDoc.empty.withStrokes(w.strokes);
      // desce a 3ª palavra 6 unidades (≈ 0,4 altura-x)
      final moved = w.wordIds[2].toSet();
      doc = PageDoc(strokes: [
        for (final s in doc.strokes)
          moved.contains(s.id)
              ? s.copyWith(points: [for (final p in s.points) InkPoint(p.x, p.y + 6, p.p)])
              : s,
      ]);
      final out = straighten(doc, ids(doc.strokes), NewIds().call);
      final l = segmentLines(out).single;
      double bottomOf(InkWord word) {
        final bs = [
          for (final id in word.strokeIds)
            if (out.strokeById(id)!.bounds.height < 1.6 * lineXHeight(out, l)) out.strokeById(id)!.bounds.bottom,
        ]..sort();
        return bs[bs.length ~/ 2];
      }

      expect((bottomOf(l.words[2]) - bottomOf(l.words[1])).abs(), lessThan(2.5));
    });

    test('linhas que começam quase no mesmo x ficam alinhadas; o recuo de parágrafo continua', () {
      final gen = IdGen();
      final doc = line('o gato quase', y: 300, x: 80, gen: gen)
          .merge(line('pegou um rato', y: 360, x: 93, gen: gen, hand: const Hand(seed: 9)))
          .merge(line('mas fugiu', y: 420, x: 150, gen: gen, hand: const Hand(seed: 11)));
      final out = straighten(doc, ids(doc.strokes), NewIds().call);
      final ls = segmentLines(out);
      expect(ls, hasLength(3));
      expect(ls[1].bounds.left, closeTo(ls[0].bounds.left, 1.5));
      expect(ls[2].bounds.left, greaterThan(ls[0].bounds.left + 40));
    });
  });
}
