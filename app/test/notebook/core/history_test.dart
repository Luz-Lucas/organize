import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/core/notebook_core.dart';

import 'test_support.dart';

String Function() counter([String prefix = 'r']) {
  var i = 0;
  return () => '$prefix${(i++).toString().padLeft(4, '0')}';
}

Stroke seg(String id, double x) =>
    lineStroke(id, Offset(x, 0), Offset(x, 50), n: 3);

/// Conteúdo visível, ignorando ids (que mudam ao reviver).
List<List<InkPoint>> visible(PageDoc d) => [
  for (final s in d.strokes) s.points,
];

void main() {
  group('History básico', () {
    test('vazio: nada a desfazer/refazer', () {
      const h = History();
      expect(h.canUndo, isFalse);
      expect(h.canRedo, isFalse);
      expect(h.undo(PageDoc.empty), isNull);
      expect(h.redo(PageDoc.empty), isNull);
      expect(h.limit, 100);
    });

    test('desfaz e refaz o desenho de um traço', () {
      final d0 = PageDoc.empty;
      final d1 = d0.withStroke(seg('s001', 10));
      var h = const History().record(d0, d1);
      expect(h.canUndo, isTrue);
      expect(h.canRedo, isFalse);

      final u = h.undo(d1)!;
      expect(u.doc.strokes, isEmpty);
      expect(u.history.canUndo, isFalse);
      expect(u.history.canRedo, isTrue);

      final r = u.history.redo(u.doc, newId: counter())!;
      expect(visible(r.doc), visible(d1));
      expect(r.history.canUndo, isTrue);
      expect(r.history.canRedo, isFalse);
    });

    test('é imutável: o History antigo continua válido', () {
      final d1 = PageDoc.empty.withStroke(seg('s001', 10));
      final h0 = const History();
      final h1 = h0.record(PageDoc.empty, d1);
      expect(h0.canUndo, isFalse);
      expect(h1.canUndo, isTrue);
      h1.undo(d1);
      expect(h1.canUndo, isTrue);
    });

    test('registrar sem mudança não cria passo', () {
      final d = PageDoc.empty.withStroke(seg('s001', 10));
      expect(const History().record(d, d).canUndo, isFalse);
    });

    test('nova edição limpa o refazer', () {
      final d1 = PageDoc.empty.withStroke(seg('s001', 10));
      final d2 = d1.withStroke(seg('s002', 20));
      var h = const History().record(PageDoc.empty, d1).record(d1, d2);
      final u = h.undo(d2)!;
      expect(u.history.canRedo, isTrue);
      final d3 = u.doc.withStroke(seg('s003', 30));
      final h2 = u.history.record(u.doc, d3);
      expect(h2.canRedo, isFalse);
    });

    test('vários desfazer e refazer em sequência', () {
      var doc = PageDoc.empty;
      var h = const History();
      for (var i = 1; i <= 5; i++) {
        final next = doc.withStroke(seg('s00$i', i * 10.0));
        h = h.record(doc, next);
        doc = next;
      }
      final ids = counter();
      for (var i = 4; i >= 0; i--) {
        final u = h.undo(doc, newId: ids)!;
        h = u.history;
        doc = u.doc;
        expect(doc.strokes.length, i);
      }
      expect(h.undo(doc), isNull);
      for (var i = 1; i <= 5; i++) {
        final r = h.redo(doc, newId: ids)!;
        h = r.history;
        doc = r.doc;
        expect(doc.strokes.length, i);
      }
      expect(h.redo(doc), isNull);
    });

    test('limite de 100 passos (os mais antigos caem)', () {
      var doc = PageDoc.empty;
      var h = const History();
      for (var i = 0; i < 150; i++) {
        final next = doc.withStroke(
          seg('s${i.toString().padLeft(4, '0')}', 1.0 * i),
        );
        h = h.record(doc, next);
        doc = next;
      }
      expect(h.undoCount, 100);
      final ids = counter();
      var n = 0;
      while (h.canUndo) {
        final u = h.undo(doc, newId: ids)!;
        h = u.history;
        doc = u.doc;
        n++;
      }
      expect(n, 100);
      expect(doc.strokes.length, 50, reason: 'os 50 mais antigos ficam');
    });

    test('limite personalizado', () {
      var doc = PageDoc.empty;
      var h = const History(limit: 3);
      for (var i = 0; i < 10; i++) {
        final next = doc.withStroke(seg('s$i', 1.0 * i));
        h = h.record(doc, next);
        doc = next;
      }
      expect(h.undoCount, 3);
    });
  });

  group('History com apagar e transformar', () {
    test('desfazer a borracha traz o traço de volta (com id novo)', () {
      final d1 = PageDoc.empty.withStroke(seg('s001', 10));
      final d2 = d1.without({'s001'});
      final h = const History().record(d1, d2);
      final u = h.undo(d2, newId: counter())!;
      expect(u.doc.strokes.length, 1);
      expect(u.doc.strokes.single.id, 'r0000');
      expect(u.doc.strokes.single.points, d1.strokes.single.points);
      expect(u.idMap, {'s001': 'r0000'});
      expect(u.doc.deleted, contains('s001'));
      // refazer apaga de novo a cópia revivida
      final r = u.history.redo(u.doc)!;
      expect(r.doc.strokes, isEmpty);
    });

    test('desfazer/refazer uma borracha parcial', () {
      final d1 = PageDoc.empty.withStroke(
        lineStroke('s001', Offset.zero, const Offset(100, 0), width: 0),
      );
      final d2 = erasePartial(d1, [const Offset(50, 0)], 5, counter('n'));
      expect(d2.strokes.length, 2);
      final h = const History().record(d1, d2);
      final u = h.undo(d2, newId: counter('u'))!;
      expect(u.doc.strokes.length, 1);
      expect(u.doc.strokes.single.points.length, 11);
      final r = u.history.redo(u.doc, newId: counter('v'))!;
      expect(r.doc.strokes.length, 2);
      expect(visible(r.doc), visible(d2));
    });

    test('desfazer transformar volta posição e tamanho', () {
      final d1 = PageDoc.empty
          .withStroke(seg('s001', 10))
          .withText(mkText('t001'));
      final d2 = transformItems(
        d1,
        {'s001', 't001'},
        Matrix2x3.translation(100, 100),
        newId: counter('n'),
      );
      final h = const History().record(d1, d2);
      final u = h.undo(d2, newId: counter('u'))!;
      expect(visible(u.doc), visible(d1));
      expect(u.doc.texts.single.x, d1.texts.single.x);
      expect(u.doc.texts.single.text, 'olá');
    });
  });

  group('History e sincronização', () {
    test(
      'desfazer depois de salvar não é desfeito pelo merge com o servidor',
      () {
        // aparelho A desenha e apaga; o servidor já viu o apagar.
        final d1 = PageDoc.empty.withStroke(seg('s001', 10));
        final d2 = d1.without({'s001'});
        final servidor = d2; // salvo
        final h = const History().record(d1, d2);
        final u = h.undo(d2)!; // A desfaz
        final merged = servidor.merge(u.doc);
        expect(merged.strokes.length, 1, reason: 'o traço revivido sobrevive');
        expect(merged.strokes.single.points, d1.strokes.single.points);
      },
    );

    test('desfazer não apaga traços que chegaram de outro aparelho', () {
      // A desenha Y; B enviou X (chega por merge); A desfaz -> só Y some.
      final d0 = PageDoc.empty;
      final dY = d0.withStroke(seg('s002', 20));
      final h = const History().record(d0, dY);
      final comRemoto = dY.merge(PageDoc.empty.withStroke(seg('s001', 10)));
      final u = h.undo(comRemoto)!;
      expect(u.doc.strokes.map((s) => s.id), ['s001']);
    });

    test('passo que não tem mais efeito (já apagado por outro) é pulado', () {
      final d0 = PageDoc.empty;
      final d1 = d0.withStroke(seg('s001', 10));
      final d2 = d1.withStroke(seg('s002', 20));
      final h = const History().record(d0, d1).record(d1, d2);
      // outro aparelho já apagou o s002; o desfazer pula para desfazer s001
      final atual = d2.without({'s002'});
      final u = h.undo(atual)!;
      expect(u.doc.strokes, isEmpty);
      expect(u.history.canUndo, isFalse);
    });

    test('só passos sem efeito: undo devolve null', () {
      final d1 = PageDoc.empty.withStroke(seg('s001', 10));
      final h = const History().record(PageDoc.empty, d1);
      expect(h.undo(d1.without({'s001'})), isNull);
    });
  });
}
