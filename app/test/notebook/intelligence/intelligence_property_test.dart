// Testes de propriedade da geometria da escrita sobre páginas aleatórias
// (determinísticas por semente): endireitar preserva a estrutura, os gestos
// são reconhecidos onde devem e nunca na escrita normal.
import 'dart:math' as math;
import 'dart:ui' hide TextBox;

import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/core/notebook_core.dart';
import 'package:organizacional/notebook/intelligence/gestures.dart';
import 'package:organizacional/notebook/intelligence/segmentation.dart';
import 'package:organizacional/notebook/intelligence/straighten.dart';

import 'handwriting.dart';

Stroke scribbleOver(String id, Rect rect, {int passes = 6, int seed = 1}) {
  final r = math.Random(seed);
  final pts = <Offset>[];
  for (var k = 0; k <= passes; k++) {
    final fromLeft = k.isEven;
    final x0 = fromLeft ? rect.left : rect.right, x1 = fromLeft ? rect.right : rect.left;
    final y0 = rect.top + (k.isEven ? 0.15 : 0.85) * rect.height;
    final y1 = rect.top + (k.isEven ? 0.85 : 0.15) * rect.height;
    for (var i = 0; i < 8; i++) {
      final t = i / 8;
      pts.add(Offset(x0 + (x1 - x0) * t + (r.nextDouble() - 0.5) * 0.6, y0 + (y1 - y0) * t + (r.nextDouble() - 0.5) * 0.6));
    }
  }
  return Stroke(id: id, tool: PenTool.pen, argb: 0xFF101010, width: 2.2, points: [for (final p in pts) InkPoint(p.dx, p.dy, 0.5)]);
}

void main() {
  group('páginas aleatórias: endireitar', () {
    test('mantém linhas e palavras, deixa as baselines horizontais e as escalas dentro de ±25 %', () {
      var lineCount = 0;
      for (var seed = 1; seed <= 60; seed++) {
        final p = randomPage(seed);
        final before = segmentLines(p.doc);
        final gen = NewIds();
        final out = straighten(p.doc, {for (final s in p.doc.strokes) s.id}, gen.call);
        final after = segmentLines(out);
        final why = '(página $seed: ${p.desc.join(" | ")})';
        expect(out.strokes.length, p.doc.strokes.length, reason: why);
        expect(after.length, before.length, reason: 'linhas $why');
        for (var i = 0; i < before.length; i++) {
          expect(after[i].words.length, before[i].words.length, reason: 'palavras da linha $i $why');
          expect(after[i].angle.abs() * 180 / math.pi, lessThan(1.0), reason: 'ângulo da linha $i $why');
          lineCount++;
        }
        // nada sai da página para a direita por causa do espaçamento
        final rightBefore = p.doc.strokes.map((s) => s.bounds.right).reduce(math.max);
        final rightAfter = out.strokes.map((s) => s.bounds.right).reduce(math.max);
        expect(rightAfter, lessThanOrEqualTo(math.max(pageWidth, rightBefore) + 0.5), reason: 'borda direita $why');
        // ids: um novo por traço trocado, todos os trocados com tombstone
        expect(out.deleted.length, gen.count, reason: why);
        expect(out.strokes.where((s) => s.id.startsWith('z')).length, gen.count, reason: why);
        // espessuras: escala de palavra limitada a ±25 % (ou ±27 % com a quantização)
        final oldWidth = p.doc.strokes.first.width;
        for (final s in out.strokes) {
          expect(s.width / oldWidth, inInclusiveRange(0.74, 1.26), reason: 'espessura ${s.width} $why');
        }
      }
      expect(lineCount, greaterThan(150));
    });

    test('é determinístico e uma segunda passada quase não muda nada', () {
      var changedSecond = 0, total = 0;
      for (var seed = 1; seed <= 25; seed++) {
        final p = randomPage(seed);
        final all = {for (final s in p.doc.strokes) s.id};
        final a = straighten(p.doc, all, NewIds().call);
        final b = straighten(p.doc, all, NewIds().call);
        expect(a.strokes, b.strokes, reason: 'determinismo (página $seed)');
        final gen2 = NewIds('y');
        straighten(a, {for (final s in a.strokes) s.id}, gen2.call);
        changedSecond += gen2.count;
        total += a.strokes.length;
      }
      // ignore: avoid_print
      print('endireitar duas vezes: $changedSecond de $total traços mudaram na 2ª passada');
      expect(changedSecond / total, lessThan(0.15));
    });
  });

  group('páginas aleatórias: gestos', () {
    test('o que o usuário desenha de propósito é reconhecido (∧, vertical, ∪, rabisco)', () {
      var tried = 0;
      final failures = <String>[];
      for (var seed = 1; seed <= 80; seed++) {
        final p = randomPage(seed);
        final lines = segmentLines(p.doc);
        final r = math.Random(seed);
        final li = r.nextInt(lines.length);
        final line = lines[li];
        final xh = lineXHeight(p.doc, line);
        double base(double x) => lineBaselineAt(line, x);
        final why = 'página $seed linha $li';

        if (line.words.length >= 2) {
          final g = r.nextInt(line.words.length - 1);
          final gl = line.words[g].bounds.right, gr = line.words[g + 1].bounds.left;
          final x = (gl + gr) / 2 + (r.nextDouble() - 0.5) * 0.3 * (gr - gl);
          final yb = base(x) + r.nextDouble() * 0.5 * xh;
          final w = (0.8 + r.nextDouble() * 0.4) * xh, h = (0.7 + r.nextDouble() * 0.3) * xh;
          final caret = polyStroke('caret', [Offset(x - w / 2, yb), Offset(x, yb - h), Offset(x + w / 2, yb)], seed: seed);
          tried++;
          final got = detectGesture(caret, p.doc, lines);
          if (got is! InsertSpace) failures.add('$why ∧ gap $g → $got');

          final overshoot = 0.4 + r.nextDouble() * 0.3;
          final x0 = gl - overshoot * xh, x1 = gr + overshoot * xh;
          final yc = base((x0 + x1) / 2) + 0.15 * xh;
          final depth = (0.4 + r.nextDouble() * 0.3) * xh;
          final cup = Stroke(
            id: 'cup',
            tool: PenTool.pen,
            argb: 0xFF000000,
            width: 2.2,
            points: [for (var i = 0; i <= 20; i++) InkPoint(x0 + (x1 - x0) * i / 20, yc + depth * math.sin(i / 20 * math.pi), 0.5)],
          );
          tried++;
          final gotCup = detectGesture(cup, p.doc, lines);
          if (gotCup is! JoinWords ||
              !(gotCup.ids.length == line.words[g].strokeIds.length + line.words[g + 1].strokeIds.length)) {
            failures.add('$why ∪ gap $g → $gotCup');
          }
        }

        final wide = [for (final w in line.words) if (w.bounds.width >= 2.2 * xh) w];
        if (wide.isNotEmpty) {
          final w = wide[r.nextInt(wide.length)];
          final x = w.bounds.left + w.bounds.width * (0.3 + 0.4 * r.nextDouble());
          final vl = polyStroke('vl', [Offset(x, base(x) - 2.3 * xh), Offset(x + 1, base(x) + 0.9 * xh)], perSeg: 14, seed: seed);
          tried++;
          final got = detectGesture(vl, p.doc, lines);
          if (got is! SplitWord || got.strokeOrWordIds != w.key) failures.add('$why | vertical → $got');

          final sc = scribbleOver('sc', Rect.fromLTRB(w.bounds.left - 2, w.bounds.top, w.bounds.right + 2, w.bounds.bottom), seed: seed);
          tried++;
          final gotSc = detectGesture(sc, p.doc, lines);
          if (gotSc is! ScratchOut || gotSc.targetIds.length < w.strokeIds.length || !gotSc.targetIds.containsAll(w.strokeIds)) {
            failures.add('$why rabisco → $gotSc');
          }
        }
      }
      // ignore: avoid_print
      print('gestos feitos de propósito: ${tried - failures.length} reconhecidos de $tried');
      // (em texto apertado o gesto às vezes encosta na tinta da linha de baixo,
      // e aí é de propósito que não vira gesto)
      expect(failures.length, lessThanOrEqualTo((tried * 0.03).floor()), reason: failures.join('\n'));
    });

    test('escrever páginas inteiras traço a traço nunca dispara gesto', () {
      var strokes = 0;
      for (var seed = 1; seed <= 12; seed++) {
        final p = randomPage(seed * 7);
        var doc = PageDoc.empty;
        for (final w in p.lines) {
          for (final s in w.strokes) {
            final lines = segmentLines(doc);
            final a = detectGesture(s, doc, lines);
            expect(a, isNull, reason: 'página ${seed * 7} traço ${s.id} → $a (${p.desc.join(" | ")})');
            doc = doc.withStroke(s);
            // a mesma chamada com o traço já no documento
            final b = detectGesture(s, doc, segmentLines(doc));
            expect(b, isNull, reason: 'página ${seed * 7} traço ${s.id} (depois) → $b');
            strokes++;
          }
        }
      }
      // ignore: avoid_print
      print('escrita normal: $strokes traços de páginas aleatórias, nenhum virou gesto');
      expect(strokes, greaterThan(1000));
    });
  });
}
