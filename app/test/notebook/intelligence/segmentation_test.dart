import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/core/notebook_core.dart';
import 'package:organizacional/notebook/intelligence/ink_types.dart';
import 'package:organizacional/notebook/intelligence/segmentation.dart';

import '../core/test_support.dart';
import 'handwriting.dart';

/// Texto com muitas ascendentes/descendentes e acentos (pior caso para linhas).
const _sample = [
  'o gato quase pegou o pequeno gigante',
  'você nunca viu lillian jogar quando chove',
  'Lucas estuda matemática para a prova',
  'jantar tarde pode ser pior que perder',
  'um mil vivo uva minimum feliz quando faz',
];

/// Verifica que cada linha escrita virou uma InkLine com as mesmas palavras.
void expectSegmented(
  List<InkLine> got,
  List<Written> want, {
  String reason = '',
}) {
  expect(got.length, want.length, reason: 'linhas $reason');
  for (var i = 0; i < want.length; i++) {
    final w = want[i];
    final gs = got[i].strokeIds.toSet(), ws = w.strokes.map((s) => s.id).toSet();
    if (!(gs.length == ws.length && gs.containsAll(ws))) {
      fail('linha $i $reason: faltam ${ws.difference(gs)}, sobram ${gs.difference(ws)}; '
          'bounds ${got[i].bounds}; esperado ${w.strokes.first.bounds.top}..');
    }
    expect(got[i].words.length, w.wordIds.length, reason: 'palavras da linha $i $reason');
    for (var k = 0; k < w.wordIds.length; k++) {
      expect(
        got[i].words[k].strokeIds.toSet(),
        w.wordIds[k].toSet(),
        reason: 'palavra $k da linha $i $reason',
      );
    }
  }
}

void main() {
  group('segmentLines: básico', () {
    test('documento vazio não tem linhas', () {
      expect(segmentLines(PageDoc.empty), isEmpty);
    });

    test('uma palavra vira uma linha com uma palavra', () {
      final w = writeLine('minimum', start: const Offset(100, 200), ids: IdGen());
      final lines = segmentLines(PageDoc.empty.withStrokes(w.strokes));
      expect(lines, hasLength(1));
      expect(lines.single.words, hasLength(1));
      expect(lines.single.words.single.strokeIds.toSet(), w.strokes.map((s) => s.id).toSet());
      expect(lines.single.words.single.text, isNull);
      expect(lines.single.words.single.candidates, isEmpty);
    });

    test('chave da palavra = ids ordenados e unidos por vírgula', () {
      final w = writeLine('um mil', start: const Offset(100, 200), ids: IdGen());
      final lines = segmentLines(PageDoc.empty.withStrokes(w.strokes));
      for (final word in lines.single.words) {
        expect(word.key, (word.strokeIds.toList()..sort()).join(','));
      }
    });

    test('lacuna entre palavras: 0,45× altura-x continua palavra; 0,9× separa', () {
      Stroke box(String id, double l, double r) => lineStroke(id, Offset(l, 200), Offset(r, 200 - 16), n: 6);
      // três "letras" de 16 de altura; lacuna variável entre a 2ª e a 3ª
      PageDoc build(double gap) => PageDoc.empty.withStrokes([
        box('a1', 100, 112),
        box('a2', 118, 130),
        box('a3', 130 + gap, 142 + gap),
      ]);
      expect(segmentLines(build(0.45 * 16)).single.words, hasLength(1));
      expect(segmentLines(build(0.9 * 16)).single.words, hasLength(2));
    });

    test('pontos de i, barras de t, acentos e ponto final ficam na palavra', () {
      final w = writeLine('você, tia.', start: const Offset(100, 300), ids: IdGen());
      final lines = segmentLines(PageDoc.empty.withStrokes(w.strokes));
      expect(lines, hasLength(1));
      expectSegmented(lines, [w]);
    });

    test('i-dot e barras escritos só no fim da palavra (atrasados) também agrupam', () {
      final w = writeLine('minimum tita', start: const Offset(100, 300), ids: IdGen(),
          hand: const Hand(delayExtras: true));
      expectSegmented(segmentLines(PageDoc.empty.withStrokes(w.strokes)), [w]);
    });

    test('baseline e ângulo: linha reta e linhas inclinadas de ±3 a ±10°', () {
      for (final deg in [0.0, 3.0, 6.0, 10.0, -3.0, -7.0, -10.0]) {
        final w = writeLine('o gato quase pegou o pequeno gigante agora', start: const Offset(80, 400), ids: IdGen(),
            hand: Hand(slopeDeg: deg, seed: 5));
        final line = segmentLines(PageDoc.empty.withStrokes(w.strokes)).single;
        expect(line.angle * 180 / math.pi, closeTo(deg, 1.0), reason: 'ângulo $deg°');
        // baseline no início da linha: ~400 (a letra tem bounds.left ≈ 80)
        expect(line.baselineY, closeTo(400 + math.tan(deg * math.pi / 180) * (line.bounds.left - 80), 2.5),
            reason: 'baselineY $deg°');
      }
    });

    test('linha com pouco texto não inventa inclinação', () {
      final w = writeLine('um', start: const Offset(80, 400), ids: IdGen());
      final line = segmentLines(PageDoc.empty.withStrokes(w.strokes)).single;
      expect(line.angle.abs() * 180 / math.pi, lessThan(2.0));
    });

    test('bounds da linha e da palavra contêm seus traços', () {
      final w = writeLine('você nunca', start: const Offset(80, 400), ids: IdGen());
      final doc = PageDoc.empty.withStrokes(w.strokes);
      final line = segmentLines(doc).single;
      for (final word in line.words) {
        for (final id in word.strokeIds) {
          final b = doc.strokeById(id)!.bounds;
          expect(word.bounds.inflate(0.01).contains(b.topLeft), isTrue);
          expect(word.bounds.inflate(0.01).contains(b.bottomRight), isTrue);
          expect(line.bounds.inflate(0.01).contains(b.center), isTrue);
        }
      }
    });
  });

  group('segmentLines: várias linhas, vários estilos', () {
    test('5 linhas com ascendentes, descendentes e acentos, em várias seeds e inclinações', () {
      for (final deg in [0.0, 3.0, 4.0, 6.0, 8.0, 10.0, -3.0, -5.0, -7.0, -10.0]) {
        for (var seed = 1; seed <= 12; seed++) {
          final p = writePage(_sample, hand: Hand(slopeDeg: deg, seed: seed * 7), pitch: 44);
          expectSegmented(segmentLines(p.doc), p.lines, reason: '(deg=$deg seed=$seed)');
        }
      }
    });

    test('espaçamento apertado de linhas (1,9× altura-x… pitch 32 com xh 16)', () {
      for (var seed = 1; seed <= 12; seed++) {
        final p = writePage(_sample, hand: Hand(slopeDeg: seed.isEven ? 3 : -4, seed: seed), pitch: 36);
        expectSegmented(segmentLines(p.doc), p.lines, reason: '(seed=$seed)');
      }
    });

    test('tamanhos de letra diferentes entre linhas', () {
      final sizes = [12.0, 16.0, 22.0, 28.0, 18.0];
      final hands = [for (var i = 0; i < 5; i++) Hand(xh: sizes[i], seed: 20 + i, slopeDeg: 2.0 * i - 3)];
      // pitch proporcional ao maior tamanho vizinho
      final gen = IdGen();
      var doc = PageDoc.empty;
      final lines = <Written>[];
      var y = 100.0;
      for (var i = 0; i < 5; i++) {
        y += sizes[i] * 2.7;
        final w = writeLine(_sample[i], start: Offset(80, y), ids: gen, hand: hands[i]);
        lines.add(w);
        doc = doc.withStrokes(w.strokes);
      }
      expectSegmented(segmentLines(doc), lines);
    });

    test('linhas saem de cima para baixo', () {
      final p = writePage(_sample, hand: const Hand(seed: 3));
      final lines = segmentLines(p.doc);
      for (var i = 1; i < lines.length; i++) {
        expect(lines[i].baselineY, greaterThan(lines[i - 1].baselineY));
      }
      for (final l in lines) {
        for (var k = 1; k < l.words.length; k++) {
          expect(l.words[k].bounds.left, greaterThan(l.words[k - 1].bounds.left));
        }
      }
    });

    test('duas linhas separadas por um parágrafo em branco continuam duas', () {
      final p = writePage(['primeira linha de texto', '', 'depois do espaço'].where((l) => l.isNotEmpty).toList(),
          pitch: 90, hand: const Hand(seed: 4));
      expectSegmented(segmentLines(p.doc), p.lines);
    });
  });

  group('segmentLines: páginas aleatórias e limites', () {
    test('300 páginas aleatórias realistas saem com todas as linhas e palavras certas', () {
      var strokes = 0;
      for (var seed = 1; seed <= 300; seed++) {
        final p = randomPage(seed);
        expectSegmented(segmentLines(p.doc), p.lines, reason: '(página $seed: ${p.desc.join(" | ")})');
        strokes += p.doc.strokes.length;
      }
      // ignore: avoid_print
      print('segmentação: 300 páginas aleatórias ($strokes traços) sem nenhum erro');
    });

    test('letras espaçadas (0,27×) e palavras próximas (1,0×) ainda se separam', () {
      for (var seed = 1; seed <= 12; seed++) {
        final gen = IdGen();
        var doc = PageDoc.empty;
        final lines = <Written>[];
        for (var i = 0; i < 3; i++) {
          final w = writeLine('o gato quase pegou', start: Offset(80, 200.0 + 40 * i), ids: gen,
              hand: Hand(seed: seed * 5 + i, letterGap: 0.27, wordGap: 1.0));
          lines.add(w);
          doc = doc.withStrokes(w.strokes);
        }
        expectSegmented(segmentLines(doc), lines, reason: '(seed $seed)');
      }
    });

    test('título grande (xh 34) acima do texto (xh 16) e depois outro texto', () {
      final gen = IdGen();
      final a = writeLine('Meu caderno', start: const Offset(80, 150), ids: gen, hand: const Hand(xh: 34, seed: 3));
      final b = writeLine('o gato quase pegou o pequeno', start: const Offset(80, 230), ids: gen, hand: const Hand(seed: 4, slopeDeg: 3));
      final c = writeLine('você nunca viu lillian jogar', start: const Offset(80, 275), ids: gen, hand: const Hand(seed: 5, slopeDeg: 3));
      final doc = PageDoc.empty.withStrokes([...a.strokes, ...b.strokes, ...c.strokes]);
      expectSegmented(segmentLines(doc), [a, b, c]);
    });

    test('palavras de um traço só (cursiva) formam linha, e o marca-texto por baixo não atrapalha', () {
      final strokes = <Stroke>[];
      var x = 80.0;
      for (var i = 0; i < 6; i++) {
        final s = cursiveWordStroke('c${i.toString().padLeft(3, "0")}', start: Offset(x, 300 + i * 1.5), humps: 4 + i % 3, seed: i);
        strokes.add(s);
        x = s.bounds.right + 22;
      }
      final hl = lineStroke('h1', const Offset(70, 296), Offset(x, 298), width: 20, tool: PenTool.highlighter);
      final lines = segmentLines(PageDoc.empty.withStrokes([...strokes, hl]));
      expect(lines, hasLength(1));
      expect(lines.single.words, hasLength(6));
    });

    test('ponto de i longe da palavra (a 4 alturas-x) fica sem dono, sem derrubar nada', () {
      final w = writeLine('o gato quase pegou', start: const Offset(80, 300), ids: IdGen(), hand: const Hand(seed: 5));
      final stray = mkStroke('s9', [const Offset(500, 160), const Offset(500.4, 160.3), const Offset(500.1, 160.6)]);
      final lines = segmentLines(PageDoc.empty.withStrokes([...w.strokes, stray]));
      expectSegmented(lines, [w]);
    });
  });

  group('segmentLines: o que é ignorado', () {
    test('marca-texto não entra em nenhuma linha', () {
      final w = writeLine('o gato quase pegou', start: const Offset(80, 300), ids: IdGen());
      final hl = lineStroke('h1', const Offset(70, 292), const Offset(400, 292), width: 18, tool: PenTool.highlighter);
      final doc = PageDoc.empty.withStrokes([...w.strokes, hl]);
      final lines = segmentLines(doc);
      expectSegmented(lines, [w]);
      expect(lines.expand((l) => l.strokeIds), isNot(contains('h1')));
    });

    test('palma (mancha enorme) e desenhos grandes não viram linha nem entram nas linhas', () {
      final w = writeLine('o gato quase pegou', start: const Offset(80, 300), ids: IdGen());
      final palm = mkStroke('palma', [
        for (var i = 0; i < 40; i++) Offset(90 + 4.0 * i, 250 + 30 * math.sin(i / 3)),
        for (var i = 0; i < 40; i++) Offset(250 - 4.0 * i, 330 + 20 * math.cos(i / 4)),
      ], width: 40);
      final circle = mkStroke('circulo', [
        for (var i = 0; i <= 60; i++) Offset(600 + 130 * math.cos(i / 60 * 2 * math.pi), 300 + 130 * math.sin(i / 60 * 2 * math.pi)),
      ]);
      final doc = PageDoc.empty.withStrokes([...w.strokes, palm, circle]);
      final lines = segmentLines(doc);
      expectSegmented(lines, [w]);
    });

    test('sublinhado longo e fino não vira palavra nem estica a linha', () {
      final w = writeLine('o gato quase pegou', start: const Offset(80, 300), ids: IdGen());
      final underline = lineStroke('u1', const Offset(70, 312), Offset(w.endX + 30, 313), n: 40);
      final doc = PageDoc.empty.withStrokes([...w.strokes, underline]);
      expectSegmented(segmentLines(doc), [w]);
    });

    test('only restringe aos traços pedidos', () {
      final p = writePage(_sample, hand: const Hand(seed: 9));
      final only = p.lines[1].strokes.map((s) => s.id).toSet();
      final lines = segmentLines(p.doc, only: only);
      expectSegmented(lines, [p.lines[1]]);
      // only com ids de duas linhas separadas
      final two = {...only, ...p.lines[3].strokes.map((s) => s.id)};
      expectSegmented(segmentLines(p.doc, only: two), [p.lines[1], p.lines[3]]);
      // only vazio ou desconhecido
      expect(segmentLines(p.doc, only: {}), isEmpty);
      expect(segmentLines(p.doc, only: {'nao-existe'}), isEmpty);
    });

    test('textos e imagens não atrapalham', () {
      final w = writeLine('o gato quase pegou', start: const Offset(80, 300), ids: IdGen());
      final doc = PageDoc.empty
          .withStrokes(w.strokes)
          .withText(const TextBox(id: 't1', x: 80, y: 290, w: 300, text: 'texto', size: 20, argb: 0xFF000000))
          .withImage(const ImageBox(id: 'i1', x: 0, y: 0, w: 500, h: 500, path: 'p.png'));
      expectSegmented(segmentLines(doc), [w]);
    });

    test('um ponto sozinho (pingo isolado) não quebra', () {
      final doc = PageDoc.empty.withStroke(mkStroke('d1', [const Offset(300, 300), const Offset(300.2, 300.1)]));
      expect(() => segmentLines(doc), returnsNormally);
    });
  });

  group('segmentLines: determinismo e estabilidade', () {
    test('mesma entrada, mesma saída (e independe da ordem de inserção)', () {
      final p = writePage(_sample, hand: const Hand(seed: 11, slopeDeg: 5));
      String sig(List<InkLine> ls) => ls
          .map((l) => '${l.strokeIds.join(",")}|${l.baselineY}|${l.angle}|${l.bounds}|'
              '${l.words.map((w) => "${w.strokeIds.join(",")}@${w.bounds}").join(";")}')
          .join('\n');
      final a = sig(segmentLines(p.doc));
      expect(sig(segmentLines(p.doc)) == a, isTrue, reason: 'segunda chamada difere');
      final shuffled = [...p.doc.strokes]..shuffle(math.Random(7));
      expect(sig(segmentLines(PageDoc(strokes: shuffled))) == a, isTrue, reason: 'ordem de inserção muda o resultado');
    });

    test('acrescentar uma linha embaixo não muda as de cima', () {
      final p = writePage(_sample.take(4).toList(), hand: const Hand(seed: 12, slopeDeg: 4));
      final before = segmentLines(p.doc);
      final extra = writeLine('mais uma linha agora', start: Offset(80, 120 + 4 * 40.0), ids: IdGen('t'),
          hand: const Hand(seed: 99, slopeDeg: 4));
      final after = segmentLines(p.doc.withStrokes(extra.strokes));
      expect(after.length, before.length + 1);
      for (var i = 0; i < before.length; i++) {
        expect(after[i].words.map((w) => w.key).toList(), before[i].words.map((w) => w.key).toList());
        expect(after[i].baselineY, closeTo(before[i].baselineY, 0.5));
      }
    });

    test('escrever mais uma palavra no fim da linha preserva as palavras anteriores', () {
      final gen = IdGen();
      final w1 = writeLine('o gato quase', start: const Offset(80, 300), ids: gen, hand: const Hand(seed: 3));
      final before = segmentLines(PageDoc.empty.withStrokes(w1.strokes)).single;
      final w2 = writeLine('pegou', start: Offset(w1.endX + 20, 300), ids: gen, hand: const Hand(seed: 4));
      final after = segmentLines(PageDoc.empty.withStrokes([...w1.strokes, ...w2.strokes])).single;
      expect(after.words.length, before.words.length + 1);
      for (var i = 0; i < before.words.length; i++) {
        expect(after.words[i].key, before.words[i].key);
      }
    });
  });

  group('segmentLines: desempenho', () {
    // ~2.000 traços de escrita (≈ 46 linhas de ≈ 45 traços)
    PageDoc big() {
      final gen = IdGen();
      var doc = PageDoc.empty;
      const text = 'o gato quase pegou o pequeno gigante e você nunca viu lillian jogar';
      var n = 0;
      for (var i = 0; n < 2000; i++) {
        final w = writeLine(text, start: Offset(40, 60 + (i % 34) * 40.0), ids: gen, hand: Hand(seed: i, slopeDeg: (i % 5) - 2.0));
        final take = w.strokes.take(math.min(w.strokes.length, 2000 - n)).toList();
        doc = doc.withStrokes(take);
        n += take.length;
      }
      return doc;
    }

    PageDoc scattered() {
      final r = math.Random(1);
      return PageDoc.empty.withStrokes([
        for (var i = 0; i < 2000; i++)
          () {
            final cx = r.nextDouble() * 900, cy = r.nextDouble() * 1300;
            return mkStroke('r${i.toString().padLeft(5, "0")}', [
              for (var k = 0; k < 20; k++) Offset(cx + r.nextDouble() * 30, cy + r.nextDouble() * 30),
            ]);
          }(),
      ]);
    }

    /// (parede ms, CPU ms da thread). Sob carga da máquina a parede mente; a CPU
    /// da thread não (lê /proc/thread-self/schedstat; sem Linux, repete a parede).
    (double, double) time(void Function() f) {
      double cpu() {
        try {
          return int.parse(File('/proc/thread-self/schedstat').readAsStringSync().split(' ').first) / 1e6;
        } catch (_) {
          return double.nan;
        }
      }

      final c0 = cpu();
      final sw = Stopwatch()..start();
      f();
      sw.stop();
      final c1 = cpu();
      final wall = sw.elapsedMicroseconds / 1000;
      return (wall, c1.isNaN ? wall : c1 - c0);
    }

    test('2.000 traços de escrita em menos de 50 ms', () {
      final doc = big();
      expect(doc.strokes.length, 2000);
      late List<InkLine> lines;
      final cold = time(() => lines = segmentLines(doc));
      final warm = [for (var i = 0; i < 9; i++) time(() => segmentLines(doc))]..sort((a, b) => a.$2.compareTo(b.$2));
      // ignore: avoid_print
      print('PERF segmentLines 2000 traços: ${lines.length} linhas; 1ª chamada ${cold.$1.toStringAsFixed(1)} ms parede / '
          '${cold.$2.toStringAsFixed(1)} ms CPU; seguintes: mínima ${warm.first.$2.toStringAsFixed(1)} / mediana '
          '${warm[4].$2.toStringAsFixed(1)} ms CPU');
      // (o computador de desenvolvimento costuma estar carregado: vale o melhor de 10)
      expect(math.min(cold.$2, warm.first.$2), lessThan(50));
    });

    test('2.000 traços espalhados ao acaso (sem texto) também em menos de 50 ms', () {
      final doc = scattered();
      final cold = time(() => segmentLines(doc));
      final warm = [for (var i = 0; i < 9; i++) time(() => segmentLines(doc))]..sort((a, b) => a.$2.compareTo(b.$2));
      // ignore: avoid_print
      print('PERF segmentLines 2000 traços aleatórios: 1ª chamada ${cold.$1.toStringAsFixed(1)} ms parede / '
          '${cold.$2.toStringAsFixed(1)} ms CPU; seguintes: mínima ${warm.first.$2.toStringAsFixed(1)} / mediana '
          '${warm[4].$2.toStringAsFixed(1)} ms CPU');
      expect(math.min(cold.$2, warm.first.$2), lessThan(50));
    });
  });
}
