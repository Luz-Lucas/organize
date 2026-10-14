import 'dart:math' as math;
import 'dart:ui' hide TextBox;

import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/core/notebook_core.dart';
import 'package:organizacional/notebook/intelligence/gestures.dart';
import 'package:organizacional/notebook/intelligence/ink_types.dart';
import 'package:organizacional/notebook/intelligence/segmentation.dart';

import 'handwriting.dart';

/// Palavras pt-BR que NUNCA podem virar gesto (m, w, u, n, l, i, v, acento...).
const negativeWords = [
  'minimum', 'uva', 'vivo', 'nunca', 'lillian', 'você', 'um', 'mil', 'Lucas',
  'wow', 'mamãe', 'vovô', 'ninguém', 'viu', 'unir', 'muito', 'uniu', 'invisível',
  'além', 'avô', 'mês', 'três', 'lá', 'já', 'nós', 'ilumina', 'imensa', 'mínimo',
  'água', 'maçã', 'quinze', 'jantar', 'tarde', 'pequeno', 'gigante', 'chove',
  'cuidado', 'envolvimento', 'unimos', 'vamos', 'hoje', 'fácil',
];

Set<String> idSet(Iterable<Stroke> s) => {for (final x in s) x.id};

/// Gesto em [doc] para [s] com as linhas calculadas do documento SEM [s]
/// (como a tela faz ao soltar o traço) e COM [s] (outro jeito de chamar).
(InkGesture?, InkGesture?) detectBoth(Stroke s, PageDoc docBefore) {
  final lines = segmentLines(docBefore);
  final a = detectGesture(s, docBefore, lines);
  final after = docBefore.withStroke(s);
  final b = detectGesture(s, after, segmentLines(after));
  return (a, b);
}

/// Traço contínuo em zigue-zague horizontal sobre [rect], com [passes] varreduras.
Stroke scribble(String id, Rect rect, {int passes = 6, double slopeTan = 0, int seed = 1, double noise = 0.6}) {
  final r = math.Random(seed);
  final pts = <Offset>[];
  for (var k = 0; k <= passes; k++) {
    final fromLeft = k.isEven;
    final x0 = fromLeft ? rect.left : rect.right;
    final x1 = fromLeft ? rect.right : rect.left;
    final y0 = rect.top + (k % 2 == 0 ? 0.15 : 0.85) * rect.height;
    final y1 = rect.top + (k % 2 == 0 ? 0.85 : 0.15) * rect.height;
    for (var i = 0; i < 8; i++) {
      final t = i / 8;
      pts.add(Offset(x0 + (x1 - x0) * t + (r.nextDouble() - 0.5) * noise, y0 + (y1 - y0) * t + (r.nextDouble() - 0.5) * noise));
    }
  }
  return Stroke(
    id: id,
    tool: PenTool.pen,
    argb: 0xFF101010,
    width: 2.2,
    points: [for (final p in pts) InkPoint(p.dx, p.dy + slopeTan * (p.dx - rect.left), 0.5)],
  );
}

/// Contexto: uma linha de texto e acesso à geometria das palavras.
class Ctx {
  Ctx(String text, {Offset start = const Offset(80, 400), Hand hand = const Hand(seed: 5), IdGen? gen}) {
    written = writeLine(text, start: start, ids: gen ?? IdGen(), hand: hand);
    doc = PageDoc.empty.withStrokes(written.strokes);
    lines = segmentLines(doc);
    xh = hand.xh;
  }
  late final Written written;
  late final PageDoc doc;
  late final List<InkLine> lines;
  late final double xh;
  InkLine get line => lines.single;
  InkWord word(int i) => line.words[i];
  double base(double x) => lineBaselineAt(line, x);

  /// Centro da lacuna entre a palavra i e a i+1.
  double gapCenter(int i) => (word(i).bounds.right + word(i + 1).bounds.left) / 2;
  double gapWidth(int i) => word(i + 1).bounds.left - word(i).bounds.right;
}

void main() {
  group('gestos: ∧ abre espaço (InsertSpace)', () {
    Stroke caret(Ctx c, double x, {double dyBase = 0.1, double w = 1.0, double h = 1.0, int seed = 3, double apexShift = 0}) {
      final yb = c.base(x) + dyBase * c.xh;
      return polyStroke('caret', [
        Offset(x - w * c.xh / 2, yb),
        Offset(x + apexShift * c.xh, yb - h * c.xh),
        Offset(x + w * c.xh / 2, yb),
      ], seed: seed);
    }

    test('∧ na lacuna entre duas palavras, na baseline', () {
      final c = Ctx('o gato quase pegou');
      final g = detectGesture(caret(c, c.gapCenter(1)), c.doc, c.lines);
      expect(g, isA<InsertSpace>());
      final ins = g! as InsertSpace;
      expect(ins.at.dx, closeTo(c.gapCenter(1), c.xh * 0.6));
      expect(ins.at.dy, closeTo(c.base(c.gapCenter(1)), c.xh));
      expect(ins.width, inInclusiveRange(70, 260));
    });

    test('vale ∧ logo abaixo da linha, desenhado da direita para a esquerda e levemente torto', () {
      final c = Ctx('o gato quase pegou');
      for (var seed = 1; seed <= 6; seed++) {
        final x = c.gapCenter(1);
        final yb = c.base(x) + 0.7 * c.xh;
        final s = polyStroke('caret', [
          Offset(x + 0.55 * c.xh, yb + 0.1 * c.xh),
          Offset(x + 0.1 * c.xh, yb - 1.1 * c.xh),
          Offset(x - 0.5 * c.xh, yb),
        ], seed: seed);
        expect(detectGesture(s, c.doc, c.lines), isA<InsertSpace>(), reason: 'seed $seed');
      }
    });

    test('em linha inclinada (8°) a lacuna continua valendo', () {
      final c = Ctx('o gato quase pegou', hand: const Hand(seed: 5, slopeDeg: 8));
      final x = c.gapCenter(2);
      final yb = c.base(x) + 0.2 * c.xh;
      final s = polyStroke('caret', [
        Offset(x - 0.5 * c.xh, yb), Offset(x, yb - 1.0 * c.xh), Offset(x + 0.5 * c.xh, yb),
      ]);
      expect(detectGesture(s, c.doc, c.lines), isA<InsertSpace>());
    });

    test('acento circunflexo sobre uma letra NÃO é gesto (está dentro da palavra e no alto)', () {
      final c = Ctx('você nunca');
      // "você" sem o acento
      final w = c.written;
      final accent = w.strokes.firstWhere((s) => s.bounds.top < w.strokes.first.bounds.top - 5 && s.bounds.height < 14 && s.bounds.left < c.word(0).bounds.right);
      final without = PageDoc.empty.withStrokes(w.strokes.where((s) => s.id != accent.id));
      final r = detectBoth(accent, without);
      expect(r.$1, isNull);
      expect(r.$2, isNull);
    });

    test('∧ no alto da lacuna (altura de acento) não é gesto', () {
      final c = Ctx('o gato quase pegou');
      final x = c.gapCenter(1);
      final yb = c.base(x) - 1.5 * c.xh; // flutuando acima das letras
      final s = polyStroke('caret', [Offset(x - 8, yb), Offset(x, yb - 12), Offset(x + 8, yb)]);
      expect(detectGesture(s, c.doc, c.lines), isNull);
    });

    test('∧ dentro de uma palavra, antes da primeira ou depois da última: nada', () {
      final c = Ctx('o gato quase pegou');
      final inside = caret(c, c.word(1).bounds.center.dx);
      expect(detectGesture(inside, c.doc, c.lines), isNull);
      final before = caret(c, c.word(0).bounds.left - 0.9 * c.xh);
      expect(detectGesture(before, c.doc, c.lines), isNull);
      final after = caret(c, c.word(3).bounds.right + 0.9 * c.xh);
      expect(detectGesture(after, c.doc, c.lines), isNull);
    });

    test('tamanho fora do razoável (A maiúsculo, risquinho) não é gesto', () {
      final c = Ctx('o gato quase pegou');
      final x = c.gapCenter(1);
      expect(detectGesture(caret(c, x, h: 2.2, w: 1.3), c.doc, c.lines), isNull, reason: 'grande (como a letra A)');
      expect(detectGesture(caret(c, x, h: 0.15, w: 0.3), c.doc, c.lines), isNull, reason: 'minúsculo');
    });

    test('ângulo do vértice fora de 30–120° não é gesto', () {
      final c = Ctx('o gato quase pegou');
      final x = c.gapCenter(1);
      // muito aberto (quase uma reta horizontal com leve elevação)
      expect(detectGesture(caret(c, x, w: 2.0, h: 0.3), c.doc, c.lines), isNull);
      // muito fechado (dois traços colados: vertical e volta)
      expect(detectGesture(caret(c, x, w: 0.12, h: 1.1), c.doc, c.lines), isNull);
    });

    test('arco redondo (∩) e onda não são ∧ (precisa de dois segmentos retos)', () {
      final c = Ctx('o gato quase pegou');
      final x = c.gapCenter(1);
      final yb = c.base(x) + 0.1 * c.xh;
      final arch = Stroke(
        id: 'arch',
        tool: PenTool.pen,
        argb: 0xFF000000,
        width: 2.2,
        points: [
          for (var i = 0; i <= 24; i++)
            InkPoint(x - 0.55 * c.xh * math.cos(i / 24 * math.pi), yb - 1.0 * c.xh * math.sin(i / 24 * math.pi), 0.5),
        ],
      );
      expect(detectGesture(arch, c.doc, c.lines), isNull);
    });
  });

  group('gestos: rabisco apaga (ScratchOut)', () {
    test('rabisco em zigue-zague cobrindo uma palavra apaga os traços dela', () {
      final c = Ctx('o gato quase pegou');
      final w = c.word(2);
      final s = scribble('sc', w.bounds.inflate(2).intersect(Rect.fromLTRB(w.bounds.left - 2, w.bounds.top, w.bounds.right + 2, w.bounds.bottom)));
      final g = detectGesture(s, c.doc, c.lines);
      expect(g, isA<ScratchOut>());
      expect((g! as ScratchOut).targetIds, w.strokeIds.toSet());
    });

    test('cobre ≥ 60 % da palavra: vale; 40 %: não', () {
      final c = Ctx('o gato quase pegou');
      final w = c.word(1);
      Rect part(double f) => Rect.fromLTRB(w.bounds.left, w.bounds.top, w.bounds.left + w.bounds.width * f, w.bounds.bottom);
      expect(detectGesture(scribble('s70', part(0.75)), c.doc, c.lines), isA<ScratchOut>());
      expect(detectGesture(scribble('s40', part(0.4)), c.doc, c.lines), isNull);
    });

    test('rabisco longo cobrindo duas palavras apaga as duas', () {
      final c = Ctx('o gato quase pegou');
      final a = c.word(1), b = c.word(2);
      final s = scribble('sc', Rect.fromLTRB(a.bounds.left - 3, a.bounds.top, b.bounds.right + 3, a.bounds.bottom), passes: 8);
      final g = detectGesture(s, c.doc, c.lines);
      expect(g, isA<ScratchOut>());
      expect((g! as ScratchOut).targetIds, {...a.strokeIds, ...b.strokeIds});
    });

    test('acompanha linha inclinada', () {
      final c = Ctx('o gato quase pegou', hand: const Hand(seed: 5, slopeDeg: 8));
      final w = c.word(2);
      final s = scribble('sc', Rect.fromLTRB(w.bounds.left - 2, w.bounds.top, w.bounds.right + 2, w.bounds.bottom));
      final g = detectGesture(s, c.doc, c.lines);
      expect(g, isA<ScratchOut>());
    });

    test('poucas inversões (3 ou menos) não é rabisco', () {
      final c = Ctx('o gato quase pegou');
      final w = c.word(2);
      final r = Rect.fromLTRB(w.bounds.left - 2, w.bounds.top, w.bounds.right + 2, w.bounds.bottom);
      expect(detectGesture(scribble('s3', r, passes: 3), c.doc, c.lines), isNull);
      expect(detectGesture(scribble('s4', r, passes: 4), c.doc, c.lines), isA<ScratchOut>());
    });

    test('rabisco longe do texto, em espaço vazio, ou sobre desenho: nada', () {
      final c = Ctx('o gato quase pegou');
      expect(detectGesture(scribble('sc', const Rect.fromLTWH(300, 800, 100, 30)), c.doc, c.lines), isNull);
      // abaixo da linha, sem tocar nas palavras
      final w = c.word(2);
      expect(
        detectGesture(scribble('sc', Rect.fromLTRB(w.bounds.left, w.bounds.bottom + 40, w.bounds.right, w.bounds.bottom + 70)), c.doc, c.lines),
        isNull,
      );
    });

    test('rabisco enorme (muito maior que a palavra) é desenho, não gesto', () {
      final c = Ctx('o gato quase pegou');
      final w = c.word(2);
      final s = scribble('sc', Rect.fromLTRB(w.bounds.left - 2, w.bounds.top - 120, w.bounds.right + 2, w.bounds.bottom + 120));
      expect(detectGesture(s, c.doc, c.lines), isNull);
    });

    test('palavra cursiva num traço só (m, n, u em zigue-zague contínuo) não é rabisco', () {
      final c = Ctx('o gato quase pegou', start: const Offset(80, 400));
      for (final humps in [4, 6, 8, 10]) {
        final s = cursiveWordStroke('cur', start: Offset(c.word(3).bounds.right + 1.1 * c.xh, 400), humps: humps, seed: humps);
        expect(detectGesture(s, c.doc, c.lines), isNull, reason: '$humps cavas');
      }
    });
  });

  group('gestos: traço vertical separa (SplitWord)', () {
    Stroke vline(Ctx c, double x, {double up = 2.3, double down = 0.9, double tilt = 0, int seed = 3, double? yBase}) {
      final yb = yBase ?? c.base(x);
      return polyStroke('vl', [
        Offset(x - tilt * c.xh / 2, yb - up * c.xh),
        Offset(x + tilt * c.xh / 2, yb + down * c.xh),
      ], perSeg: 14, seed: seed);
    }

    test('traço vertical atravessando uma palavra do alto ao baixo da linha', () {
      final c = Ctx('o gato quase pegou');
      final w = c.word(2);
      final x = w.bounds.left + w.bounds.width * 0.5;
      final g = detectGesture(vline(c, x), c.doc, c.lines);
      expect(g, isA<SplitWord>());
      final sp = g! as SplitWord;
      expect(sp.x, closeTo(x, 1.5));
      expect(sp.strokeOrWordIds, wordKey(w.strokeIds));
    });

    test('desenhado de baixo para cima e levemente inclinado (≤ 8°)', () {
      final c = Ctx('o gato quase pegou');
      final w = c.word(2);
      final x = w.bounds.left + w.bounds.width * 0.4;
      final yb = c.base(x);
      final s = polyStroke('vl', [Offset(x + 2, yb + 0.9 * c.xh), Offset(x - 2, yb - 2.3 * c.xh)], perSeg: 14);
      expect(detectGesture(s, c.doc, c.lines), isA<SplitWord>());
    });

    test('só do tamanho de uma letra (não passa da altura-x e da baseline): não é gesto', () {
      final c = Ctx('o gato quase pegou');
      final w = c.word(2);
      final x = w.bounds.left + w.bounds.width * 0.5;
      expect(detectGesture(vline(c, x, up: 1.0, down: 0.0), c.doc, c.lines), isNull);
      expect(detectGesture(vline(c, x, up: 2.0, down: 0.0), c.doc, c.lines), isNull, reason: 'como um l');
      expect(detectGesture(vline(c, x, up: 1.0, down: 1.0), c.doc, c.lines), isNull, reason: 'como um p');
    });

    test('inclinado demais, curvo, ou fora de qualquer palavra: não é gesto', () {
      final c = Ctx('o gato quase pegou');
      final w = c.word(2);
      final x = w.bounds.left + w.bounds.width * 0.5;
      expect(detectGesture(vline(c, x, tilt: 0.9), c.doc, c.lines), isNull);
      final curve = Stroke(
        id: 'cv',
        tool: PenTool.pen,
        argb: 0xFF000000,
        width: 2.2,
        points: [
          for (var i = 0; i <= 20; i++)
            InkPoint(x + 5 * c.xh / 16 * math.sin(i / 20 * math.pi * 2), c.base(x) - 1.4 * c.xh + i / 20 * 2.1 * c.xh, 0.5),
        ],
      );
      expect(detectGesture(curve, c.doc, c.lines), isNull);
      // entre palavras, longe de todas
      expect(detectGesture(vline(c, c.gapCenter(1)), c.doc, c.lines), isNull);
      // no extremo da palavra (a menos de 0,3 altura-x da borda)
      expect(detectGesture(vline(c, w.bounds.right - 0.1 * c.xh), c.doc, c.lines), isNull);
      expect(detectGesture(vline(c, w.bounds.left + 0.1 * c.xh), c.doc, c.lines), isNull);
    });

    test('altura demais (mais de 4 alturas-x) é desenho', () {
      final c = Ctx('o gato quase pegou');
      final w = c.word(2);
      final x = w.bounds.left + w.bounds.width * 0.5;
      expect(detectGesture(vline(c, x, up: 4, down: 3), c.doc, c.lines), isNull);
    });
  });

  group('gestos: arco ∪ junta (JoinWords)', () {
    Stroke cup(Ctx c, int gapIdx, {double depth = 0.8, double overshoot = 0.6, double dyBase = 0.3, int seed = 3, bool reverse = false}) {
      final x0 = c.word(gapIdx).bounds.right - overshoot * c.xh;
      final x1 = c.word(gapIdx + 1).bounds.left + overshoot * c.xh;
      final xm = (x0 + x1) / 2;
      final yb = c.base(xm) + dyBase * c.xh;
      final r = math.Random(seed);
      final pts = [
        for (var i = 0; i <= 20; i++)
          InkPoint(
            x0 + (x1 - x0) * i / 20 + (r.nextDouble() - 0.5) * 0.4,
            yb + depth * c.xh * math.sin(i / 20 * math.pi) + (r.nextDouble() - 0.5) * 0.4,
            0.5,
          ),
      ];
      return Stroke(id: 'cup', tool: PenTool.pen, argb: 0xFF000000, width: 2.2, points: reverse ? pts.reversed.toList() : pts);
    }

    test('arco sob o vão entre duas palavras junta as duas', () {
      final c = Ctx('o gato quase pegou');
      final g = detectGesture(cup(c, 1), c.doc, c.lines);
      expect(g, isA<JoinWords>());
      expect((g! as JoinWords).ids, {...c.word(1).strokeIds, ...c.word(2).strokeIds});
    });

    test('funciona da direita para a esquerda, mais fundo e em linha inclinada', () {
      final c = Ctx('o gato quase pegou', hand: const Hand(seed: 5, slopeDeg: -6));
      expect(detectGesture(cup(c, 2, reverse: true), c.doc, c.lines), isA<JoinWords>());
      expect(detectGesture(cup(c, 0, depth: 1.2), c.doc, c.lines), isA<JoinWords>());
    });

    test('um "u" ou "v" dentro da linha (na altura-x) não é arco de junção', () {
      final c = Ctx('o gato quase pegou');
      final x = c.gapCenter(1);
      final yb = c.base(x);
      final u = polyStroke('u', [Offset(x - 8, yb - c.xh), Offset(x - 8, yb - 0.3 * c.xh), Offset(x, yb), Offset(x + 8, yb - 0.3 * c.xh), Offset(x + 8, yb - c.xh)], perSeg: 8);
      expect(detectGesture(u, c.doc, c.lines), isNull);
    });

    test('arco sob uma palavra só, ou no fim da linha, ou raso/estreito demais: nada', () {
      final c = Ctx('o gato quase pegou');
      final w = c.word(2);
      // ∪ embaixo do meio de uma palavra
      final x0 = w.bounds.left + 0.2 * w.bounds.width, x1 = w.bounds.right - 0.2 * w.bounds.width;
      final yb = c.base(w.bounds.center.dx) + 0.4 * c.xh;
      final under = Stroke(id: 'u', tool: PenTool.pen, argb: 0xFF000000, width: 2.2, points: [
        for (var i = 0; i <= 20; i++) InkPoint(x0 + (x1 - x0) * i / 20, yb + 0.8 * c.xh * math.sin(i / 20 * math.pi), 0.5),
      ]);
      expect(detectGesture(under, c.doc, c.lines), isNull);
      // depois da última palavra
      final end = c.word(3).bounds.right;
      final s2 = Stroke(id: 'e', tool: PenTool.pen, argb: 0xFF000000, width: 2.2, points: [
        for (var i = 0; i <= 20; i++) InkPoint(end + 5 + 25 * i / 20, c.base(end) + 4 + 12 * math.sin(i / 20 * math.pi), 0.5),
      ]);
      expect(detectGesture(s2, c.doc, c.lines), isNull);
      // raso (0,1 altura-x)
      expect(detectGesture(cup(c, 1, depth: 0.08), c.doc, c.lines), isNull);
    });

    test('arco que passa muito além das palavras (sublinhado curvo) não é gesto', () {
      final c = Ctx('o gato quase pegou');
      final x0 = c.word(0).bounds.left, x1 = c.word(3).bounds.right;
      final yb = c.base((x0 + x1) / 2) + 0.4 * c.xh;
      final big = Stroke(id: 'big', tool: PenTool.pen, argb: 0xFF000000, width: 2.2, points: [
        for (var i = 0; i <= 30; i++) InkPoint(x0 + (x1 - x0) * i / 30, yb + 0.8 * c.xh * math.sin(i / 30 * math.pi), 0.5),
      ]);
      expect(detectGesture(big, c.doc, c.lines), isNull);
    });
  });

  group('gestos: ESCRITA NORMAL nunca vira gesto (casos negativos)', () {
    test('palavras pt-BR isoladas, traço a traço na ordem da escrita', () {
      var tested = 0;
      for (final word in negativeWords) {
        for (final deg in [0.0, 5.0, -6.0, 9.0]) {
          for (final delay in [false, true]) {
            for (var seed = 1; seed <= 4; seed++) {
              final w = writeLine(word, start: const Offset(120, 400), ids: IdGen(),
                  hand: Hand(seed: seed * 13 + word.length, slopeDeg: deg, delayExtras: delay, xh: 12.0 + 3 * seed));
              var doc = PageDoc.empty;
              for (final s in w.strokes) {
                final r = detectBoth(s, doc);
                expect(r.$1, isNull, reason: '"$word" deg=$deg delay=$delay seed=$seed traço ${s.id} (antes) → ${r.$1}');
                expect(r.$2, isNull, reason: '"$word" deg=$deg delay=$delay seed=$seed traço ${s.id} (depois) → ${r.$2}');
                tested++;
                doc = doc.withStroke(s);
              }
            }
          }
        }
      }
      // ignore: avoid_print
      print('gestos negativos: $tested traços de ${negativeWords.length} palavras, nenhum virou gesto');
      expect(tested, greaterThan(2000));
    });

    test('as palavras juntas numa frase, escrevendo traço a traço', () {
      var tested = 0;
      final sentence = negativeWords.take(12).join(' ');
      for (final deg in [0.0, 4.0, -7.0]) {
        for (final delay in [false, true]) {
          for (var seed = 1; seed <= 3; seed++) {
            final w = writeLine(sentence, start: const Offset(30, 400), ids: IdGen(),
                hand: Hand(seed: seed * 17, slopeDeg: deg, delayExtras: delay, wordGap: 0.9 + 0.2 * seed));
            var doc = PageDoc.empty;
            for (final s in w.strokes) {
              final r = detectBoth(s, doc);
              expect(r.$1, isNull, reason: 'frase deg=$deg delay=$delay seed=$seed traço ${s.id} → ${r.$1}');
              expect(r.$2, isNull, reason: 'frase (depois) deg=$deg delay=$delay seed=$seed traço ${s.id} → ${r.$2}');
              tested++;
              doc = doc.withStroke(s);
            }
          }
        }
      }
      expect(tested, greaterThan(1000));
    });

    test('com linhas de texto acima e abaixo (contexto de página)', () {
      final gen = IdGen();
      final above = writeLine('um mil vivo uva minimum nunca lillian', start: const Offset(80, 360), ids: gen, hand: const Hand(seed: 91));
      final below = writeLine('você Lucas mês três lá já nós água', start: const Offset(80, 440), ids: gen, hand: const Hand(seed: 92));
      var base = PageDoc.empty.withStrokes([...above.strokes, ...below.strokes]);
      for (final word in ['minimum', 'uva', 'vivo', 'nunca', 'lillian', 'você', 'um', 'mil', 'Lucas']) {
        final mid = writeLine('o $word', start: const Offset(80, 400), ids: IdGen('m'), hand: Hand(seed: word.length * 7));
        var doc = base;
        for (final s in mid.strokes) {
          final r = detectBoth(s, doc);
          expect(r.$1, isNull, reason: 'contexto "$word" traço ${s.id} → ${r.$1}');
          expect(r.$2, isNull, reason: 'contexto (depois) "$word" traço ${s.id} → ${r.$2}');
          doc = doc.withStroke(s);
        }
      }
    });

    test('"minimum" cursivo num traço só, depois de outras palavras', () {
      final w = writeLine('um mil vivo', start: const Offset(80, 400), ids: IdGen(), hand: const Hand(seed: 3));
      final doc = PageDoc.empty.withStrokes(w.strokes);
      for (var humps = 5; humps <= 12; humps++) {
        final s = cursiveWordStroke('zz$humps', start: Offset(w.endX + 20, 400), humps: humps, seed: humps);
        final r = detectBoth(s, doc);
        expect(r.$1, isNull, reason: '$humps cavas');
        expect(r.$2, isNull, reason: '$humps cavas (depois)');
      }
    });

    test('gestos só em caneta/lápis: marca-texto e ponto isolado nunca', () {
      final c = Ctx('o gato quase pegou');
      final w = c.word(2);
      final hl = scribble('h', w.bounds.inflate(2)).copyWith(tool: PenTool.highlighter);
      expect(detectGesture(hl, c.doc, c.lines), isNull);
      final dot = Stroke(id: 'dot', tool: PenTool.pen, argb: 0xFF000000, width: 2, points: [const InkPoint(c0, 400, 0.5)]);
      expect(detectGesture(dot, c.doc, c.lines), isNull);
      expect(detectGesture(dot, PageDoc.empty, const []), isNull);
    });
  });

  group('applyGesture', () {
    test('ScratchOut apaga com tombstones só os traços alvo', () {
      final c = Ctx('o gato quase pegou');
      final ids = c.word(2).strokeIds.toSet();
      final out = applyGesture(c.doc, ScratchOut(ids), NewIds().call);
      expect(out.strokes.length, c.doc.strokes.length - ids.length);
      expect(out.deleted, ids);
      for (final id in ids) {
        expect(out.contains(id), isFalse);
      }
      // ids desconhecidos são ignorados
      final unchanged = applyGesture(c.doc, const ScratchOut({'nao-existe'}), NewIds().call);
      expect(unchanged, same(c.doc));
      expect(unchanged.deleted, isEmpty);
    });

    group('InsertSpace', () {
      test('empurra as palavras da direita para a direita, e só elas', () {
        final c = Ctx('o gato quase pegou');
        final at = Offset(c.gapCenter(1), c.base(c.gapCenter(1)));
        final gen = NewIds();
        final out = applyGesture(c.doc, InsertSpace(at, 100), gen.call);
        final lines = segmentLines(out);
        expect(lines, hasLength(1));
        final before = c.line.words, after = lines.single.words;
        expect(after, hasLength(before.length));
        for (var i = 0; i < 2; i++) {
          expect(after[i].bounds.left, closeTo(before[i].bounds.left, 0.2), reason: 'palavra $i fica');
        }
        for (var i = 2; i < 4; i++) {
          expect(after[i].bounds.left - before[i].bounds.left, closeTo(100, 0.5), reason: 'palavra $i anda 100');
        }
        // ids: novos só nos traços que andaram, antigos com tombstone
        final moved = [...before[2].strokeIds, ...before[3].strokeIds];
        expect(gen.count, moved.length);
        expect(out.deleted, moved.toSet());
        expect(out.strokes.length, c.doc.strokes.length);
        expect(out.strokes.where((s) => s.id.startsWith('z')).length, moved.length);
      });

      test('em linha inclinada as palavras andam ao longo da linha (continua uma linha só)', () {
        final c = Ctx('o gato quase pegou agora', hand: const Hand(seed: 5, slopeDeg: 8));
        final x = c.gapCenter(1);
        final out = applyGesture(c.doc, InsertSpace(Offset(x, c.base(x)), 90), NewIds().call);
        final lines = segmentLines(out);
        expect(lines, hasLength(1));
        expect(lines.single.angle * 180 / math.pi, closeTo(8, 1.5));
        expect(lines.single.words, hasLength(5));
      });

      test('não empurra para fora da página: usa o que cabe', () {
        final c = Ctx('o gato quase pegou agora mesmo', start: const Offset(30, 400));
        final x = c.gapCenter(0);
        final out = applyGesture(c.doc, InsertSpace(Offset(x, c.base(x)), 400), NewIds().call);
        final right = out.strokes.map((s) => s.bounds.right).reduce(math.max);
        expect(right, lessThanOrEqualTo(pageWidth));
        expect(right, greaterThan(c.line.bounds.right));
      });

      test('sem palavras à direita ou fora de qualquer linha: documento intacto', () {
        final c = Ctx('o gato quase pegou');
        final end = c.word(3).bounds.right + 30;
        expect(applyGesture(c.doc, InsertSpace(Offset(end, 400), 100), NewIds().call), same(c.doc));
        expect(applyGesture(c.doc, const InsertSpace(Offset(500, 900), 100), NewIds().call), same(c.doc));
      });

      test('outras linhas não mudam', () {
        final p = writePage(['o gato quase pegou', 'você nunca viu lillian', 'um mil vivo uva'], pitch: 60);
        final lines = segmentLines(p.doc);
        final l = lines[1];
        final x = (l.words[0].bounds.right + l.words[1].bounds.left) / 2;
        final out = applyGesture(p.doc, InsertSpace(Offset(x, lineBaselineAt(l, x)), 80), NewIds().call);
        for (final k in [0, 2]) {
          for (final s in p.lines[k].strokes) {
            expect(identical(out.strokeById(s.id), p.doc.strokeById(s.id)), isTrue);
          }
        }
        expect(segmentLines(out), hasLength(3));
      });
    });

    group('JoinWords', () {
      test('fecha a lacuna (as duas viram uma palavra) e puxa as seguintes', () {
        final c = Ctx('o gato quase pegou');
        final ids = {...c.word(1).strokeIds, ...c.word(2).strokeIds};
        final gen = NewIds();
        final out = applyGesture(c.doc, JoinWords(ids), gen.call);
        final lines = segmentLines(out);
        expect(lines, hasLength(1));
        final w = lines.single.words;
        expect(w, hasLength(3), reason: 'o | gatoquase | pegou');
        expect(w[1].strokeIds.length, ids.length);
        // as anteriores ficam; as seguintes andam o mesmo tanto
        final moved = c.gapWidth(1) - 0.2 * c.xh;
        expect(w[0].bounds.left, closeTo(c.word(0).bounds.left, 0.2));
        expect(w[1].bounds.left, closeTo(c.word(1).bounds.left, 0.2));
        expect(c.word(3).bounds.left - w[2].bounds.left, closeTo(moved, 1.0));
        expect(out.deleted.isNotEmpty, isTrue);
        expect(out.strokes.length, c.doc.strokes.length);
      });

      test('ids que não formam duas palavras vizinhas: documento intacto', () {
        final c = Ctx('o gato quase pegou');
        expect(applyGesture(c.doc, JoinWords({...c.word(1).strokeIds}), NewIds().call), same(c.doc));
        expect(applyGesture(c.doc, const JoinWords({'x', 'y'}), NewIds().call), same(c.doc));
        expect(applyGesture(c.doc, JoinWords({...c.word(0).strokeIds, ...c.word(2).strokeIds}), NewIds().call), same(c.doc));
      });

      test('lacuna já pequena não muda nada', () {
        final w = writeLine('gato quase', start: const Offset(80, 400), ids: IdGen(), hand: const Hand(wordGap: 0.75, seed: 9));
        final doc = PageDoc.empty.withStrokes(w.strokes);
        final lines = segmentLines(doc);
        if (lines.single.words.length == 2) {
          final ids = idSet(w.strokes);
          final out = applyGesture(doc, JoinWords(ids), NewIds().call);
          final after = segmentLines(out).single;
          expect(after.words.length, 1);
        }
      });
    });

    group('SplitWord', () {
      test('abre uma lacuna no meio da palavra (palavra de vários traços)', () {
        final c = Ctx('o gato quase pegou');
        final w = c.word(2);
        final x = w.bounds.left + w.bounds.width * 0.5;
        final gen = NewIds();
        final out = applyGesture(c.doc, SplitWord(wordKey(w.strokeIds), x), gen.call);
        final lines = segmentLines(out);
        expect(lines, hasLength(1));
        expect(lines.single.words.length, c.line.words.length + 1, reason: 'a palavra virou duas');
        // a lacuna nova é bem maior que a entre letras
        final nw = lines.single.words;
        final newGap = nw[3].bounds.left - nw[2].bounds.right;
        expect(newGap, greaterThan(0.6 * c.xh));
        // as palavras antes ficam e a última anda
        expect(nw[0].bounds.left, closeTo(c.word(0).bounds.left, 0.2));
        expect(nw.last.bounds.left, greaterThan(c.word(3).bounds.left));
        expect(out.deleted.isNotEmpty, isTrue);
      });

      test('traço cursivo que atravessa o ponto de corte é partido em dois', () {
        final stroke = cursiveWordStroke('cw', start: const Offset(100, 400), humps: 8, xh: 16);
        final other = writeLine('um mil', start: Offset(stroke.bounds.right + 30, 400), ids: IdGen('t'), hand: const Hand(seed: 3));
        final doc = PageDoc.empty.withStroke(stroke).withStrokes(other.strokes);
        final b = doc.strokeById('cw')!.bounds;
        final x = (b.left + b.right) / 2;
        final gen = NewIds();
        final out = applyGesture(doc, SplitWord('cw', x), gen.call);
        expect(out.contains('cw'), isFalse);
        expect(out.deleted, contains('cw'));
        final pieces = out.strokes.where((s) => s.id.startsWith('z')).toList();
        expect(pieces.length, greaterThanOrEqualTo(2));
        final lines = segmentLines(out);
        expect(lines.single.words.length, 4, reason: 'duas metades + "um" + "mil"');
      });

      test('determinístico e sem efeito se a palavra não existe', () {
        final c = Ctx('o gato quase pegou');
        final w = c.word(2);
        final x = w.bounds.left + w.bounds.width * 0.5;
        final a = applyGesture(c.doc, SplitWord(wordKey(w.strokeIds), x), NewIds().call);
        final b = applyGesture(c.doc, SplitWord(wordKey(w.strokeIds), x), NewIds().call);
        expect(a.strokes, b.strokes);
        expect(applyGesture(c.doc, SplitWord('nope', x), NewIds().call), same(c.doc));
      });
    });

    test('ida e volta: detectar e aplicar ∧ numa linha gera o espaço esperado', () {
      final c = Ctx('o gato quase pegou');
      final x = c.gapCenter(1);
      final yb = c.base(x) + 0.1 * c.xh;
      final s = polyStroke('caret', [Offset(x - 0.5 * c.xh, yb), Offset(x, yb - c.xh), Offset(x + 0.5 * c.xh, yb)]);
      final g = detectGesture(s, c.doc, c.lines)!;
      final out = applyGesture(c.doc, g, NewIds().call);
      final gap = segmentLines(out).single.words;
      expect(gap[2].bounds.left - gap[1].bounds.right, greaterThan(c.gapWidth(1) + 60));
    });
  });

  group('gestos: igualdade de valor', () {
    test('mesmos campos, mesmo gesto', () {
      expect(const ScratchOut({'a', 'b'}), const ScratchOut({'b', 'a'}));
      expect(const InsertSpace(Offset(1, 2), 3), const InsertSpace(Offset(1, 2), 3));
      expect(const SplitWord('a,b', 4), const SplitWord('a,b', 4));
      expect(const JoinWords({'a', 'b'}), const JoinWords({'b', 'a'}));
      expect(const SplitWord('a,b', 4), isNot(const SplitWord('a,b', 5)));
    });
  });
}

const c0 = 100.0;
