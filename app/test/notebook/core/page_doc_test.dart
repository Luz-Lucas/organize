import 'dart:math';
import 'dart:ui' hide TextBox;

import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/core/notebook_core.dart';

import 'test_support.dart';

void main() {
  group('constantes', () {
    test('página A4 em unidades de página', () {
      expect(pageWidth, 1000.0);
      expect(pageHeight, 1414.0);
    });
  });

  group('newInkId', () {
    test('é único e estritamente crescente (ordem de criação)', () {
      final ids = List.generate(20000, (_) => newInkId());
      expect(ids.toSet().length, ids.length);
      for (var i = 1; i < ids.length; i++) {
        expect(ids[i].compareTo(ids[i - 1]), greaterThan(0));
      }
    });
  });

  group('Stroke', () {
    test('bounds cobre os pontos mais meia espessura', () {
      final s = mkStroke('a', [
        const Offset(10, 20),
        const Offset(30, 5),
      ], width: 4);
      expect(s.bounds, const Rect.fromLTRB(8, 3, 32, 22));
    });

    test('lista de pontos é imutável e copiada', () {
      final src = [const InkPoint(1, 2, 0.5), const InkPoint(3, 4, 0.5)];
      final s = Stroke(
        id: 'a',
        tool: PenTool.pen,
        argb: 0xFF000000,
        width: 2,
        points: src,
      );
      src.add(const InkPoint(9, 9, 1));
      expect(s.points.length, 2);
      expect(
        () => s.points.add(const InkPoint(0, 0, 0)),
        throwsUnsupportedError,
      );
    });

    test('igualdade por valor', () {
      final a = lineStroke('a', Offset.zero, const Offset(10, 10));
      final b = lineStroke('a', Offset.zero, const Offset(10, 10));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(a.copyWith(width: 9)));
    });

    test('traço sem pontos é recusado', () {
      expect(
        () => Stroke(
          id: 'a',
          tool: PenTool.pen,
          argb: 0,
          width: 1,
          points: const [],
        ),
        throwsA(anything),
      );
    });
  });

  group('PageDoc básico', () {
    test('vazia', () {
      expect(PageDoc.empty.isEmpty, isTrue);
      expect(PageDoc.empty.strokes, isEmpty);
      expect(PageDoc.empty.deleted, isEmpty);
    });

    test('withStroke é imutável: o original não muda', () {
      final s = lineStroke('s1', Offset.zero, const Offset(10, 0));
      final d0 = PageDoc.empty;
      final d1 = d0.withStroke(s);
      expect(d0.strokes, isEmpty);
      expect(d1.strokes.single.id, 's1');
      expect(d1.isEmpty, isFalse);
      expect(() => d1.strokes.add(s), throwsUnsupportedError);
      expect(() => d1.deleted.add('x'), throwsUnsupportedError);
    });

    test('withStroke quantiza (0,1 coordenadas, 0,01 pressão)', () {
      final s = Stroke(
        id: 's1',
        tool: PenTool.pen,
        argb: 0xFF000000,
        width: 2.345,
        points: const [InkPoint(12.34, 56.789, 0.456)],
      );
      final p = PageDoc.empty.withStroke(s).strokes.single;
      expect(p.points.single, const InkPoint(12.3, 56.8, 0.46));
      expect(p.width, 2.35);
    });

    test('adicionar id já apagado (tombstone) é erro claro', () {
      final d = PageDoc.empty
          .withStroke(lineStroke('s1', Offset.zero, const Offset(1, 1)))
          .without({'s1'});
      expect(
        () => d.withStroke(lineStroke('s1', Offset.zero, const Offset(1, 1))),
        throwsArgumentError,
      );
    });

    test('mesmo id e mesmo conteúdo é no-op; conteúdo diferente é erro', () {
      final s = lineStroke('s1', Offset.zero, const Offset(10, 10));
      final d = PageDoc.empty.withStroke(s);
      expect(d.withStroke(s), d);
      expect(d.withStroke(s).strokes.length, 1);
      expect(
        () => d.withStroke(lineStroke('s1', Offset.zero, const Offset(5, 5))),
        throwsArgumentError,
      );
    });

    test('without remove de todas as listas e registra tombstones', () {
      final d = PageDoc.empty
          .withStroke(lineStroke('s1', Offset.zero, const Offset(1, 1)))
          .withText(mkText('t1'))
          .withImage(mkImage('i1'));
      final e = d.without({'s1', 't1', 'i1', 'fantasma'});
      expect(e.strokes, isEmpty);
      expect(e.texts, isEmpty);
      expect(e.images, isEmpty);
      expect(e.deleted, {'s1', 't1', 'i1', 'fantasma'});
      expect(d.strokes.length, 1, reason: 'original intacto');
    });

    test('contains / strokeById', () {
      final d = PageDoc.empty
          .withStroke(lineStroke('s1', Offset.zero, const Offset(1, 1)))
          .withText(mkText('t1'));
      expect(d.contains('s1'), isTrue);
      expect(d.contains('t1'), isTrue);
      expect(d.contains('zz'), isFalse);
      expect(d.strokeById('s1')!.id, 's1');
      expect(d.strokeById('t1'), isNull);
    });

    test('construtor normaliza: descarta itens tombstoned e duplicados', () {
      final s = lineStroke('s1', Offset.zero, const Offset(1, 1));
      final d = PageDoc(
        strokes: [s, s],
        deleted: {'s2'},
        texts: [mkText('s2')],
      );
      expect(d.strokes.length, 1);
      expect(d.texts, isEmpty);
    });
  });

  group('merge', () {
    final s1 = lineStroke('s001', Offset.zero, const Offset(10, 10));
    final s2 = lineStroke('s002', const Offset(5, 5), const Offset(20, 20));
    final s3 = lineStroke('s003', const Offset(7, 7), const Offset(30, 3));

    test('união por id', () {
      final a = PageDoc.empty.withStroke(s1).withStroke(s2);
      final b = PageDoc.empty.withStroke(s2).withStroke(s3);
      final m = a.merge(b);
      expect(m.strokes.map((s) => s.id), ['s001', 's002', 's003']);
    });

    test('tombstone vence nos dois sentidos', () {
      final a = PageDoc.empty.withStroke(s1).withStroke(s2);
      final b = a.without({'s001'});
      expect(a.merge(b).strokes.map((s) => s.id), ['s002']);
      expect(b.merge(a).strokes.map((s) => s.id), ['s002']);
      expect(a.merge(b).deleted, {'s001'});
    });

    test('não altera os operandos', () {
      final a = PageDoc.empty.withStroke(s1);
      final b = PageDoc.empty.withStroke(s2);
      a.merge(b);
      expect(a.strokes.length, 1);
      expect(b.strokes.length, 1);
    });

    test('mescla textos e imagens também', () {
      final a = PageDoc.empty.withText(mkText('t1')).withImage(mkImage('i1'));
      final b = PageDoc.empty.withText(mkText('t2')).withImage(mkImage('i2'));
      final m = a.merge(b);
      expect(m.texts.map((t) => t.id), ['t1', 't2']);
      expect(m.images.map((t) => t.id), ['i1', 'i2']);
    });

    test('mesmo id com conteúdo divergente: escolha determinística', () {
      final x = lineStroke('s9', Offset.zero, const Offset(10, 10));
      final y = lineStroke('s9', Offset.zero, const Offset(99, 99));
      final a = PageDoc(strokes: [x]);
      final b = PageDoc(strokes: [y]);
      expect(a.merge(b), b.merge(a));
      expect(a.merge(b).strokes.length, 1);
    });

    test('merge com vazio devolve conteúdo equivalente', () {
      final a = PageDoc.empty.withStroke(s1).withStroke(s2).without({'s001'});
      expect(a.merge(PageDoc.empty), a);
      expect(PageDoc.empty.merge(a), a);
    });
  });

  group('merge: propriedades (aleatório)', () {
    PageDoc randomEdits(PageDoc base, Random r, int ops) {
      var d = base;
      for (var i = 0; i < ops; i++) {
        final live = [
          ...d.strokes.map((s) => s.id),
          ...d.texts.map((s) => s.id),
          ...d.images.map((s) => s.id),
        ];
        switch (r.nextInt(5)) {
          case 0:
          case 1:
            d = d.withStroke(curveStroke(newInkId(), r, n: 3 + r.nextInt(6)));
          case 2:
            d = d.withText(mkText(newInkId(), x: r.nextDouble() * 500));
          case 3:
            d = d.withImage(mkImage(newInkId(), x: r.nextDouble() * 500));
          default:
            if (live.isNotEmpty) {
              d = d.without({live[r.nextInt(live.length)]});
            }
        }
      }
      return d;
    }

    test('comutativa, associativa e idempotente em 300 cenários', () {
      for (var seed = 0; seed < 300; seed++) {
        final r = Random(seed);
        final base = randomEdits(PageDoc.empty, r, r.nextInt(8));
        final a = randomEdits(base, r, r.nextInt(10));
        final b = randomEdits(base, r, r.nextInt(10));
        final c = randomEdits(base, r, r.nextInt(10));
        final tag = 'seed $seed';

        expect(a.merge(b), b.merge(a), reason: 'comutativa $tag');
        expect(a.merge(a), a.merge(PageDoc.empty), reason: 'idempotente $tag');
        expect(a.merge(b).merge(b), a.merge(b), reason: 'idempotente 2 $tag');
        expect(a.merge(b).merge(a), a.merge(b), reason: 'absorção $tag');
        expect(
          a.merge(b).merge(c),
          a.merge(b.merge(c)),
          reason: 'associativa $tag',
        );

        // Nenhum item vivo pode estar tombstoned.
        final m = a.merge(b);
        for (final s in m.strokes) {
          expect(m.deleted.contains(s.id), isFalse, reason: tag);
        }
        // Nada some sem tombstone: tudo que a ou b tinha vivo e não foi
        // apagado em nenhum dos dois continua no merge.
        for (final s in [...a.strokes, ...b.strokes]) {
          final apagado = a.deleted.contains(s.id) || b.deleted.contains(s.id);
          expect(m.strokeById(s.id) != null, !apagado, reason: tag);
        }
      }
    });
  });

  group('tombstones de um gesto (borracha parcial)', () {
    // A borracha parcial refaz o documento a cada movimento: cada passo apaga os
    // pedaços do passo anterior e cria outros. Só o traço original precisa de tombstone.
    PageDoc sweep(PageDoc before, int moves) {
      var doc = before;
      for (var i = 0; i < moves; i++) {
        final x = 20.0 + i * 12;
        doc = erasePartial(doc, [Offset(x, 80), Offset(x, 120)], 6, newInkId);
      }
      return doc;
    }

    test('sem poda, 30 movimentos acumulam dezenas de tombstones', () {
      final before = PageDoc.empty.withStroke(lineStroke('a', const Offset(0, 100), const Offset(400, 100), n: 200));
      final after = sweep(before, 30);
      expect(after.deleted.length, greaterThan(20));
    });

    test('withoutEphemeralTombstones guarda só o que existia antes do gesto', () {
      final before = PageDoc.empty.withStroke(lineStroke('a', const Offset(0, 100), const Offset(400, 100), n: 200));
      final after = sweep(before, 30);
      final pruned = after.withoutEphemeralTombstones(before);
      expect(pruned.deleted, {'a'});
      // O conteúdo vivo não muda.
      expect(pruned.strokes, after.strokes);
      // E o merge com quem ainda tem o traço original continua apagando-o.
      expect(before.merge(pruned).strokes.map((s) => s.id).toSet(), after.strokes.map((s) => s.id).toSet());
    });

    test('tombstones que já existiam antes continuam, inclusive de itens ausentes', () {
      final before = PageDoc.empty
          .withStroke(lineStroke('a', const Offset(0, 100), const Offset(400, 100)))
          .without(['velho', 'a']);
      final after = before.withStroke(lineStroke('b', const Offset(0, 5), const Offset(50, 5))).without(['b']);
      final pruned = after.withoutEphemeralTombstones(before);
      expect(pruned.deleted, {'velho', 'a'});
    });

    test('devolve o mesmo documento quando não há o que podar', () {
      final before = PageDoc.empty.withStroke(lineStroke('a', const Offset(0, 100), const Offset(400, 100)));
      final after = before.without(['a']);
      expect(identical(after.withoutEphemeralTombstones(before), after), isTrue);
    });
  });
}
