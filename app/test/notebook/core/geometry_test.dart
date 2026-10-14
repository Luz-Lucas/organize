import 'dart:math';
import 'dart:ui' hide TextBox;

import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/core/ink_math.dart';
import 'package:organizacional/notebook/core/notebook_core.dart';

import 'test_support.dart';

/// Gerador de ids determinístico para os testes.
String Function() counter([String prefix = 'n']) {
  var i = 0;
  return () => '$prefix${(i++).toString().padLeft(4, '0')}';
}

void main() {
  group('Matrix2x3', () {
    test('identidade, translação e escala com âncora', () {
      expect(Matrix2x3.identity.apply(const Offset(3, 4)), const Offset(3, 4));
      expect(
        Matrix2x3.translation(10, -5).apply(const Offset(1, 1)),
        const Offset(11, -4),
      );
      final m = Matrix2x3.scaling(2, anchor: const Offset(10, 10));
      expect(m.apply(const Offset(10, 10)), const Offset(10, 10));
      expect(m.apply(const Offset(15, 20)), const Offset(20, 30));
    });

    test('rotação de 90° em torno da origem e de um ponto', () {
      final r = Matrix2x3.rotation(pi / 2);
      final p = r.apply(const Offset(1, 0));
      expect(p.dx, closeTo(0, 1e-12));
      expect(p.dy, closeTo(1, 1e-12));
      final c = Matrix2x3.rotation(pi, anchor: const Offset(5, 5));
      final q = c.apply(const Offset(6, 5));
      expect(q.dx, closeTo(4, 1e-12));
      expect(q.dy, closeTo(5, 1e-12));
    });

    test('composição: a * b aplica b primeiro', () {
      final m = Matrix2x3.translation(10, 0) * Matrix2x3.scaling(2);
      expect(m.apply(const Offset(1, 1)), const Offset(12, 2));
    });

    test('fatores de escala', () {
      final m = Matrix2x3.scaling(3, sy: 4);
      expect(m.xScale, closeTo(3, 1e-12));
      expect(m.yScale, closeTo(4, 1e-12));
      expect(m.uniformScale, closeTo(sqrt(12), 1e-12));
    });
  });

  group('hitStrokes (borracha por traço)', () {
    final h = lineStroke(
      's001',
      const Offset(0, 100),
      const Offset(200, 100),
      n: 3,
      width: 2,
    ); // só 3 pontos: (0,100) (100,100) (200,100)
    final v = lineStroke(
      's002',
      const Offset(50, 0),
      const Offset(50, 300),
      n: 4,
      width: 2,
    );
    final dot = mkStroke('s003', [const Offset(500, 500)], width: 4);
    final doc = PageDoc.empty.withStrokes([h, v, dot]);

    test('acerta entre dois pontos (segmento), não só nos pontos', () {
      // (150, 100) está no meio de um segmento, longe dos pontos
      expect(hitStrokes(doc, const Offset(150, 104), 3), ['s001']);
    });

    test('considera a meia espessura do traço', () {
      // distância 4; raio 3 + meia espessura 1 = 4 -> acerta
      expect(hitStrokes(doc, const Offset(150, 104), 3), contains('s001'));
      expect(hitStrokes(doc, const Offset(150, 104.5), 3), isEmpty);
    });

    test('vários, na ordem do documento', () {
      expect(hitStrokes(doc, const Offset(50, 100), 5), ['s001', 's002']);
    });

    test('traço de um ponto', () {
      expect(hitStrokes(doc, const Offset(503, 500), 1), ['s003']);
      expect(hitStrokes(doc, const Offset(510, 500), 1), isEmpty);
    });

    test('longe de tudo', () {
      expect(hitStrokes(doc, const Offset(900, 900), 10), isEmpty);
    });

    test('from: varredura entre duas amostras da borracha', () {
      // o traço vertical está em x=50; a borracha pulou de x=0 a x=100
      expect(hitStrokes(doc, const Offset(100, 250), 2), isEmpty);
      expect(
        hitStrokes(doc, const Offset(100, 250), 2, from: const Offset(0, 250)),
        ['s002'],
      );
    });

    test('ignora textos e imagens; hitItems inclui', () {
      final d = doc
          .withText(mkText('t001', x: 700, y: 700))
          .withImage(mkImage('i001', x: 800, y: 800));
      expect(hitStrokes(d, const Offset(710, 705), 2), isEmpty);
      expect(hitItems(d, const Offset(710, 705), 2), ['t001']);
      expect(hitItems(d, const Offset(900, 900), 2), ['i001']);
      expect(hitItems(d, const Offset(795, 900), 6), ['i001']);
      expect(hitItems(d, const Offset(50, 100), 5), ['s001', 's002']);
    });
  });

  group('erasePartial', () {
    // reta de (0,0) a (100,0) com pontos a cada 10; largura 2 (meia = 1)
    Stroke row() => lineStroke(
      's001',
      Offset.zero,
      const Offset(100, 0),
      n: 11,
      width: 2,
      tool: PenTool.fountain,
    );

    test('divide em dois pedaços, com cortes exatos na borda da borracha', () {
      final doc = PageDoc.empty.withStroke(row());
      final out = erasePartial(doc, [const Offset(50, 0)], 5, counter());
      expect(out.strokes.length, 2);
      expect(out.deleted, {'s001'});
      final a = out.strokes[0], b = out.strokes[1];
      expect(a.id, 'n0000');
      expect(b.id, 'n0001');
      // raio efetivo = 5 + 1 (meia espessura) = 6 -> cortes em 44 e 56
      expect(a.points.map((p) => p.x), [0, 10, 20, 30, 40, 44]);
      expect(b.points.map((p) => p.x), [56, 60, 70, 80, 90, 100]);
      expect(a.tool, PenTool.fountain);
      expect(a.width, 2);
      expect(b.argb, 0xFF000000);
    });

    test('segmento longo cortado por borracha que o atravessa (interpola)', () {
      final doc = PageDoc.empty.withStroke(
        lineStroke('s001', Offset.zero, const Offset(100, 0), n: 2, width: 0),
      );
      final out = erasePartial(
        doc,
        [const Offset(50, -20), const Offset(50, 20)],
        3,
        counter(),
      );
      expect(out.strokes.length, 2);
      expect(out.strokes[0].points.map((p) => p.x), [0, 47]);
      expect(out.strokes[1].points.map((p) => p.x), [53, 100]);
    });

    test('interpola a pressão nos pontos de corte', () {
      final s = Stroke(
        id: 's001',
        tool: PenTool.pen,
        argb: 0xFF000000,
        width: 0,
        points: const [InkPoint(0, 0, 0.2), InkPoint(100, 0, 0.8)],
      );
      final out = erasePartial(
        PageDoc.empty.withStroke(s),
        [const Offset(50, 0)],
        10,
        counter(),
      );
      expect(out.strokes[0].points.last, const InkPoint(40, 0, 0.44));
      expect(out.strokes[1].points.first, const InkPoint(60, 0, 0.56));
    });

    test('borracha na ponta deixa um só pedaço', () {
      final doc = PageDoc.empty.withStroke(row());
      final out = erasePartial(doc, [const Offset(98, 0)], 5, counter());
      expect(out.strokes.length, 1);
      expect(out.strokes.single.points.last.x, 92);
      expect(out.strokes.single.points.first.x, 0);
    });

    test('apaga tudo quando a borracha cobre o traço inteiro', () {
      final doc = PageDoc.empty.withStroke(row());
      final path = [for (var x = -10.0; x <= 110; x += 5) Offset(x, 0)];
      final out = erasePartial(doc, path, 4, counter());
      expect(out.strokes, isEmpty);
      expect(out.deleted, {'s001'});
    });

    test('nunca cria pedaço de um ponto só (sobra minúscula é descartada)', () {
      // ponta esquerda sobra só 0,2 unidade (< mínimo): some em vez de virar bolinha
      final doc = PageDoc.empty.withStroke(
        lineStroke('s001', Offset.zero, const Offset(100, 0), width: 0),
      );
      final out = erasePartial(doc, [const Offset(30.2, 0)], 30, counter());
      expect(out.strokes.length, 1, reason: 'só o pedaço da direita');
      expect(out.strokes.single.points.first.x, 60.2);
      for (final s in out.strokes) {
        expect(s.points.length, greaterThanOrEqualTo(2));
      }
    });

    test('sobra curta mas visível fica como pedaço de 2 pontos', () {
      final doc = PageDoc.empty.withStroke(
        lineStroke('s001', Offset.zero, const Offset(100, 0), width: 0),
      );
      // corta [3, 13]: à esquerda sobram 3 unidades
      final out = erasePartial(doc, [const Offset(8, 0)], 5, counter());
      expect(out.strokes.length, 2);
      expect(out.strokes.first.points.map((p) => p.x), [0, 3]);
      expect(out.strokes.last.points.first.x, 13);
    });

    test('traço de um ponto: apagado inteiro ou intocado', () {
      final dot = mkStroke('s009', [const Offset(50, 50)], width: 4);
      final doc = PageDoc.empty.withStroke(dot);
      final hit = erasePartial(doc, [const Offset(52, 50)], 3, counter());
      expect(hit.strokes, isEmpty);
      expect(hit.deleted, {'s009'});
      final miss = erasePartial(doc, [const Offset(80, 50)], 3, counter());
      expect(miss, doc);
    });

    test('não toca traços fora do alcance (mesmo id, mesma instância)', () {
      final far = lineStroke(
        's002',
        const Offset(0, 500),
        const Offset(100, 500),
      );
      final doc = PageDoc.empty.withStroke(row()).withStroke(far);
      final out = erasePartial(doc, [const Offset(50, 0)], 5, counter());
      expect(out.strokeById('s002'), same(doc.strokeById('s002')));
      expect(out.deleted, {'s001'});
    });

    test('sem contato nenhum devolve o mesmo documento', () {
      final doc = PageDoc.empty.withStroke(row());
      expect(
        erasePartial(doc, [const Offset(50, 300)], 5, counter()),
        same(doc),
      );
      expect(erasePartial(doc, const [], 5, counter()), same(doc));
    });

    test('caminho com vários segmentos apaga em vários lugares', () {
      final doc = PageDoc.empty.withStroke(
        lineStroke('s001', Offset.zero, const Offset(100, 0), n: 11, width: 0),
      );
      final path = [const Offset(20, 0), const Offset(21, 0)]; // toque 1
      var out = erasePartial(doc, path, 3, counter());
      out = erasePartial(out, [const Offset(70, 0)], 3, counter('m'));
      expect(out.strokes.length, 3);
      expect(out.strokes.map((s) => s.points.first.x), [0, 24, 73]);
    });

    test('usa newId uma vez por pedaço criado', () {
      var calls = 0;
      final doc = PageDoc.empty.withStroke(row());
      final out = erasePartial(doc, [const Offset(50, 0)], 5, () {
        calls++;
        return 'x$calls';
      });
      expect(calls, 2);
      expect(out.strokes.map((s) => s.id), ['x1', 'x2']);
    });

    test('resultado quantizado e documento original intacto', () {
      final doc = PageDoc.empty.withStroke(row());
      final out = erasePartial(
        doc,
        [const Offset(50.123, 0.321)],
        5.5,
        counter(),
      );
      for (final s in out.strokes) {
        for (final p in s.points) {
          expect(p.x, quantizeCoord(p.x));
          expect(p.y, quantizeCoord(p.y));
        }
      }
      expect(doc.strokes.single.points.length, 11);
      expect(doc.deleted, isEmpty);
    });

    test(
      'propriedade: pedaços ficam fora da borracha, dentro do traço original',
      () {
        for (var seed = 0; seed < 150; seed++) {
          final r = Random(seed);
          final strokes = [
            for (var i = 0; i < 6; i++)
              handwritingStroke(
                's${i.toString().padLeft(3, '0')}',
                r,
                n: 2 + r.nextInt(80),
              ),
          ];
          // centra a borracha em cima do primeiro traço para garantir contato
          final p0 = strokes[0].points[strokes[0].points.length ~/ 2].offset;
          final path = [
            p0,
            for (var k = 0; k < r.nextInt(5); k++)
              p0 + Offset(r.nextDouble() * 80 - 40, r.nextDouble() * 80 - 40),
          ];
          final radius = 2 + r.nextDouble() * 12;
          final doc = PageDoc.empty.withStrokes(strokes);
          final out = erasePartial(doc, path, radius, counter());
          final tag = 'seed $seed';

          double dToPath(Offset a, Offset b) {
            var best = double.infinity;
            if (path.length == 1) return distPointSegment(path[0], a, b);
            for (var i = 0; i + 1 < path.length; i++) {
              best = min(best, distSegmentSegment(a, b, path[i], path[i + 1]));
            }
            return best;
          }

          final created = out.strokes
              .where((s) => s.id.startsWith('n'))
              .toList();
          final survivors = out.strokes
              .where((s) => !s.id.startsWith('n'))
              .toList();

          // 1. Intocados: toda a polilinha fora do alcance efetivo.
          for (final s in survivors) {
            expect(doc.strokeById(s.id), same(s), reason: tag);
            final eff = radius + s.width / 2;
            for (var i = 0; i + 1 < s.points.length; i++) {
              expect(
                dToPath(s.points[i].offset, s.points[i + 1].offset),
                greaterThan(eff - 1e-6),
                reason: '$tag intocado ${s.id}',
              );
            }
          }
          // 2. Pedaços: >= 2 pontos distintos, fora da borracha (folga da
          //    quantização) e todos sobre o traço original.
          for (final s in created) {
            expect(s.points.length, greaterThanOrEqualTo(2), reason: tag);
            final eff = radius + s.width / 2;
            for (var i = 0; i + 1 < s.points.length; i++) {
              expect(
                s.points[i].offset == s.points[i + 1].offset,
                isFalse,
                reason: '$tag pontos repetidos',
              );
              expect(
                dToPath(s.points[i].offset, s.points[i + 1].offset),
                greaterThan(eff - 0.2),
                reason: '$tag pedaço dentro da borracha',
              );
            }
            // pertence a algum traço apagado
            final src = doc.strokes.where((o) => out.deleted.contains(o.id));
            for (final p in s.points) {
              final onSome = src.any((o) {
                for (var i = 0; i + 1 < o.points.length; i++) {
                  if (distPointSegment(
                        p.offset,
                        o.points[i].offset,
                        o.points[i + 1].offset,
                      ) <
                      0.2) {
                    return true;
                  }
                }
                return o.points.length == 1 &&
                    (o.points.first.offset - p.offset).distance < 0.2;
              });
              expect(onSome, isTrue, reason: '$tag ponto fora do original');
            }
          }
          // 3. Contabilidade: cada traço original ou sobrevive ou foi apagado.
          for (final o in doc.strokes) {
            expect(
              out.strokeById(o.id) != null || out.deleted.contains(o.id),
              isTrue,
              reason: tag,
            );
          }
        }
      },
    );
  });

  group('lassoSelect', () {
    // polígono = quadrado (0,0)-(100,100)
    final sq = [
      const Offset(0, 0),
      const Offset(100, 0),
      const Offset(100, 100),
      const Offset(0, 100),
    ];

    Stroke xs(String id, List<double> xsList) =>
        mkStroke(id, [for (final x in xsList) Offset(x, 50)]);

    test('dentro, fora e metade', () {
      final doc = PageDoc.empty.withStrokes([
        xs('dentro', [10, 20, 30, 40]),
        xs('fora', [200, 210, 220, 230]),
        xs('metade', [50, 60, 150, 160]), // 2 de 4 = 50% -> entra
        xs('quase', [50, 150, 160, 170]), // 1 de 4 = 25% -> não
        xs('tres_oitavos', [10, 20, 30, 150, 160, 170, 180, 190]), // 37,5%
        xs('metade8', [10, 20, 30, 40, 150, 160, 170, 180]), // 50%
      ]);
      expect(lassoSelect(doc, sq), {'dentro', 'metade', 'metade8'});
    });

    test('traço de um ponto', () {
      final doc = PageDoc.empty.withStrokes([
        mkStroke('a', [const Offset(50, 50)]),
        mkStroke('b', [const Offset(500, 50)]),
      ]);
      expect(lassoSelect(doc, sq), {'a'});
    });

    test(
      'polígono aberto é fechado implicitamente; < 3 pontos não seleciona',
      () {
        final doc = PageDoc.empty.withStroke(
          xs('a', [60, 80]),
        ); // dentro do triângulo
        expect(lassoSelect(doc, sq.take(3).toList()), {'a'});
        expect(lassoSelect(doc, sq.take(2).toList()), isEmpty);
        expect(lassoSelect(doc, const []), isEmpty);
      },
    );

    test('polígono côncavo: o vão não conta', () {
      final u = [
        const Offset(0, 0),
        const Offset(300, 0),
        const Offset(300, 300),
        const Offset(200, 300),
        const Offset(200, 100),
        const Offset(100, 100),
        const Offset(100, 300),
        const Offset(0, 300),
      ];
      final doc = PageDoc.empty.withStrokes([
        mkStroke('vao', [for (var y = 150.0; y < 250; y += 10) Offset(150, y)]),
        mkStroke('braco', [
          for (var y = 150.0; y < 250; y += 10) Offset(50, y),
        ]),
      ]);
      expect(lassoSelect(doc, u), {'braco'});
    });

    test('textos e imagens: 50% da caixa (grade 3x3) dentro', () {
      final doc = PageDoc.empty
          .withText(
            const TextBox(
              id: 't_in',
              x: 10,
              y: 10,
              w: 50,
              text: 'olá',
              size: 18,
              argb: 1,
            ),
          )
          .withText(mkText('t_out', x: 400, y: 400))
          .withImage(
            const ImageBox(id: 'i_in', x: 10, y: 60, w: 40, h: 30, path: 'p'),
          )
          .withImage(
            const ImageBox(
              id: 'i_meio',
              x: 40,
              y: 10,
              w: 100,
              h: 30,
              path: 'p',
            ),
          )
          .withImage(
            const ImageBox(
              id: 'i_pouco',
              x: 70,
              y: 10,
              w: 90,
              h: 30,
              path: 'p',
            ),
          );
      expect(lassoSelect(doc, sq), {'t_in', 'i_in', 'i_meio'});
    });

    test('desempenho: 5.000 traços de 50 pontos em poucos ms', () {
      final r = Random(3);
      final doc = PageDoc.empty.withStrokes([
        for (var i = 0; i < 5000; i++) handwritingStroke(newInkId(), r, n: 50),
      ]);
      final sw = Stopwatch()..start();
      final sel = lassoSelect(doc, sq);
      sw.stop();
      expect(sel.length, lessThan(5000));
      expect(sw.elapsedMilliseconds, lessThan(200));
    });
  });

  group('transformItems', () {
    PageDoc base() => PageDoc.empty
        .withStroke(
          lineStroke('s001', Offset.zero, const Offset(10, 0), n: 3, width: 4),
        )
        .withStroke(
          lineStroke('s002', const Offset(500, 500), const Offset(510, 500)),
        )
        .withText(mkText('t001', x: 100, y: 200)) // w 200, size 18
        .withImage(mkImage('i001', x: 10, y: 20)); // w 300, h 200

    test('translada: novos ids, tombstones dos antigos, resto intacto', () {
      final doc = base();
      final out = transformItems(
        doc,
        {'s001', 't001', 'i001'},
        Matrix2x3.translation(30, 40),
        newId: counter(),
      );
      expect(out.deleted, {'s001', 't001', 'i001'});
      expect(out.strokeById('s001'), isNull);
      expect(out.strokeById('s002'), same(doc.strokeById('s002')));
      final s = out.strokes.firstWhere((s) => s.id.startsWith('n'));
      expect(s.points.map((p) => p.offset), [
        const Offset(30, 40),
        const Offset(35, 40),
        const Offset(40, 40),
      ]);
      expect(s.width, 4);
      expect(s.tool, PenTool.pen);
      final t = out.texts.single;
      expect([t.x, t.y, t.w, t.size, t.text], [130, 240, 200, 18, 'olá']);
      expect(t.id, isNot('t001'));
      final i = out.images.single;
      expect([i.x, i.y, i.w, i.h, i.path], [40, 60, 300, 200, 'u/n/i001.png']);
    });

    test('escala em torno de uma âncora: traço, espessura, texto e imagem', () {
      final doc = base();
      final m = Matrix2x3.scaling(2, anchor: const Offset(10, 20));
      final out = transformItems(
        doc,
        {'s001', 't001', 'i001'},
        m,
        newId: counter(),
      );
      final s = out.strokes.firstWhere((s) => s.id.startsWith('n'));
      expect(s.points.last.offset, const Offset(10, -20));
      expect(s.width, 8);
      final t = out.texts.single;
      expect([t.x, t.y, t.w, t.size], [190, 380, 400, 36]);
      final i = out.images.single;
      expect([i.x, i.y, i.w, i.h], [10, 20, 600, 400]);
    });

    test('rotação gira os pontos do traço', () {
      final doc = PageDoc.empty.withStroke(
        lineStroke('s001', Offset.zero, const Offset(10, 0), n: 2),
      );
      final out = transformItems(
        doc,
        {'s001'},
        Matrix2x3.rotation(pi / 2),
        newId: counter(),
      );
      final p = out.strokes.single.points.last;
      expect(p.x, closeTo(0, 0.05));
      expect(p.y, closeTo(10, 0.05));
    });

    test('resultado quantizado', () {
      final doc = base();
      final out = transformItems(
        doc,
        {'s001'},
        Matrix2x3.scaling(1 / 3),
        newId: counter(),
      );
      for (final p in out.strokes.firstWhere((s) => s.id == 'n0000').points) {
        expect(p.x, quantizeCoord(p.x));
      }
    });

    test('ids inexistentes ou vazio: nada muda', () {
      final doc = base();
      expect(transformItems(doc, {}, Matrix2x3.translation(1, 1)), same(doc));
      expect(
        transformItems(doc, {'nao-existe'}, Matrix2x3.translation(1, 1)),
        same(doc),
      );
    });

    test('mapped devolve o mapa id antigo -> id novo', () {
      final doc = base();
      final r = transformItemsMapped(
        doc,
        {'s001', 't001'},
        Matrix2x3.translation(1, 1),
        newId: counter(),
      );
      expect(r.idMap, {'s001': 'n0000', 't001': 'n0001'});
      expect(r.doc.contains('n0000'), isTrue);
      expect(r.doc.contains('n0001'), isTrue);
    });

    test('usa ids ordenáveis por padrão (newInkId) e vão para o topo', () {
      final doc = base();
      final out = transformItems(doc, {'s001'}, Matrix2x3.translation(1, 1));
      expect(out.strokes.last.id.compareTo('s002'), isNot(0));
      expect(out.strokes.length, 2);
      expect(out.strokes.last.points.first.offset, const Offset(1, 1));
    });

    test(
      'merge de duas edições do mesmo item não perde nem duplica o original',
      () {
        final doc = base();
        final a = transformItems(doc, {'s001'}, Matrix2x3.translation(10, 0));
        final b = transformItems(doc, {'s001'}, Matrix2x3.translation(0, 10));
        final m = a.merge(b);
        expect(m.strokeById('s001'), isNull);
        expect(m.strokes.length, 3, reason: 's002 + as duas versões editadas');
      },
    );
  });

  group('recolor', () {
    test('troca o RGB, mantém o alfa, novos ids; imagens ignoradas', () {
      final doc = PageDoc.empty
          .withStroke(
            mkStroke(
              's001',
              [Offset.zero, const Offset(5, 5)],
              argb: 0x80FFEB3B,
              tool: PenTool.highlighter,
            ),
          )
          .withText(mkText('t001'))
          .withImage(mkImage('i001'));
      final r = recolorMapped(
        doc,
        {'s001', 't001', 'i001'},
        0xFF2196F3,
        newId: counter(),
      );
      expect(r.idMap, {'s001': 'n0000', 't001': 'n0001'});
      expect(r.doc.strokes.single.argb, 0x802196F3);
      expect(r.doc.strokes.single.tool, PenTool.highlighter);
      expect(r.doc.texts.single.argb, 0xFF2196F3);
      expect(r.doc.images.single, doc.images.single);
      expect(r.doc.deleted, {'s001', 't001'});
    });

    test('mesma cor: nada muda (sem ids novos à toa)', () {
      final doc = PageDoc.empty.withStroke(
        mkStroke('s001', [Offset.zero, const Offset(5, 5)]),
      );
      expect(recolor(doc, {'s001'}, 0xFF000000), same(doc));
    });

    test('recolor devolve só o documento', () {
      final doc = PageDoc.empty.withStroke(
        mkStroke('s001', [Offset.zero, const Offset(5, 5)]),
      );
      final out = recolor(doc, {'s001'}, 0xFFFF0000, newId: counter());
      expect(out.strokes.single.argb, 0xFFFF0000);
    });
  });

  group('copiar e colar', () {
    test('extractItems pega só os itens pedidos, sem tombstones', () {
      final doc = PageDoc.empty
          .withStroke(lineStroke('s001', Offset.zero, const Offset(10, 0)))
          .withStroke(lineStroke('s002', Offset.zero, const Offset(20, 0)))
          .withText(mkText('t001'))
          .without({'velho'});
      final clip = extractItems(doc, {'s001', 't001', 'nada'});
      expect(clip.strokes.map((s) => s.id), ['s001']);
      expect(clip.texts.map((s) => s.id), ['t001']);
      expect(clip.deleted, isEmpty);
    });

    test('pasteDoc cria cópias com ids novos, deslocadas; origem intacta', () {
      final src = PageDoc.empty
          .withStroke(
            lineStroke('s001', Offset.zero, const Offset(10, 0), n: 2),
          )
          .withImage(mkImage('i001', x: 5, y: 5));
      final clip = extractItems(src, {'s001', 'i001'});
      final target = PageDoc.empty.withText(mkText('t900'));
      final r = pasteDocMapped(target, clip, dx: 20, dy: 30, newId: counter());
      expect(r.idMap, {'s001': 'n0000', 'i001': 'n0001'});
      expect(r.doc.texts.length, 1);
      expect(
        r.doc.strokeById('n0000')!.points.first.offset,
        const Offset(20, 30),
      );
      expect(r.doc.imageById('n0001')!.x, 25);
      expect(r.doc.deleted, isEmpty);
      expect(src.strokes.single.id, 's001');
    });

    test('colar duas vezes gera ids diferentes', () {
      final clip = PageDoc.empty.withStroke(
        lineStroke('s001', Offset.zero, const Offset(10, 0)),
      );
      var d = pasteDoc(PageDoc.empty, clip, dx: 10, dy: 10);
      d = pasteDoc(d, clip, dx: 10, dy: 10);
      expect(d.strokes.length, 2);
      expect(d.strokes[0].id, isNot(d.strokes[1].id));
    });
  });

  group('itemsBounds', () {
    test('união dos retângulos dos itens escolhidos', () {
      final doc = PageDoc.empty
          .withStroke(
            mkStroke('s001', [Offset.zero, const Offset(10, 10)], width: 2),
          )
          .withImage(
            const ImageBox(id: 'i001', x: 100, y: 100, w: 50, h: 20, path: 'p'),
          );
      expect(itemsBounds(doc, {'s001'}), const Rect.fromLTRB(-1, -1, 11, 11));
      expect(
        itemsBounds(doc, {'s001', 'i001'}),
        const Rect.fromLTRB(-1, -1, 150, 120),
      );
      expect(itemsBounds(doc, {'nada'}), isNull);
    });
  });
}
