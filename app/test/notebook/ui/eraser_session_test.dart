import 'dart:ui' as ui;
import 'dart:ui' hide TextBox;

import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/core/notebook_core.dart';
import 'package:organizacional/notebook/ui/eraser_session.dart';
import 'package:organizacional/notebook/ui/ink_painting.dart';
import 'package:organizacional/notebook/ui/stroke_grid.dart';
import 'package:organizacional/notebook/ui/tool_settings.dart';

/// [cols] x [rows] traços curtos e horizontais (24 pontos) espalhados na página.
PageDoc denseDoc(int cols, int rows) {
  final strokes = <Stroke>[];
  var n = 0;
  final dx = (pageWidth - 40) / cols, dy = (pageHeight - 40) / rows;
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < cols; c++) {
      final x = 20 + c * dx, y = 20 + r * dy;
      strokes.add(
        Stroke(
          id: 's${(n++).toString().padLeft(5, '0')}',
          tool: PenTool.pen,
          argb: 0xFFFFFFFF,
          width: 3,
          points: [for (var k = 0; k < 24; k++) InkPoint(x + k * (dx * 0.6 / 23), y, 0.5)],
        ),
      );
    }
  }
  return PageDoc.empty.withStrokes(strokes);
}

void main() {
  group('StrokeGrid', () {
    test('devolve só os traços cujo bounds encosta na zona, sem repetir, na ordem do documento', () {
      final doc = denseDoc(40, 50);
      final grid = StrokeGrid.build(doc.strokes);
      const zone = Rect.fromLTWH(200, 300, 90, 60);
      final got = grid.query(zone).toList();
      final want = [for (final s in doc.strokes) if (s.bounds.overlaps(zone)) s];
      expect(got.map((s) => s.id).toSet(), want.map((s) => s.id).toSet());
      expect(got.map((s) => s.id).toList(), got.map((s) => s.id).toSet().toList(), reason: 'sem repetidos');
      final order = [for (final s in got) doc.strokes.indexOf(s)];
      expect(order, [...order]..sort(), reason: 'ordem do documento');
      expect(got.length, lessThan(doc.strokes.length ~/ 10), reason: 'o índice evita varrer tudo');
    });

    test('zona fora da página e traço maior que a página não quebram', () {
      final big = Stroke(
        id: 'big',
        tool: PenTool.pen,
        argb: 0xFFFFFFFF,
        width: 4,
        points: const [InkPoint(-50, -50, 0.5), InkPoint(2000, 3000, 0.5)],
      );
      final grid = StrokeGrid.build([big]);
      expect(grid.query(const Rect.fromLTWH(-500, -500, 10, 10)), isEmpty);
      expect(grid.query(const Rect.fromLTWH(500, 700, 5, 5)).map((s) => s.id), ['big'].where((_) => big.bounds.overlaps(const Rect.fromLTWH(500, 700, 5, 5))));
      expect(grid.query(const Rect.fromLTWH(1990, 2990, 20, 20)).map((s) => s.id), ['big']);
    });
  });

  group('EraseSession (borracha por traço)', () {
    test('quadros juntam os eventos: vários add + um flush apaga o mesmo que um por evento', () {
      final doc = denseDoc(40, 50);
      final path = [for (var i = 0; i < 60; i++) Offset(100 + i * 6.0, 500 + (i % 7) * 2.0)];

      // referência: um hitStrokes por segmento sobre o documento inteiro.
      final naive = <String>{};
      for (var i = 0; i < path.length; i++) {
        naive.addAll(hitStrokes(doc, path[i], kEraserRadius, from: i == 0 ? null : path[i - 1]));
      }
      expect(naive, isNotEmpty);

      final s = EraseSession(base: doc, mode: EraserMode.stroke);
      for (final p in path) {
        s.add(p);
      }
      expect(s.hasPending, isTrue);
      expect(s.flush(), isTrue);
      expect(s.hasPending, isFalse);
      expect(s.removed, naive);
      expect(s.result().strokes.map((e) => e.id), isNot(contains(naive.first)));
      expect(s.result().deleted, naive);
    });

    test('lotes em quadros diferentes dão o mesmo resultado que um lote só', () {
      final doc = denseDoc(40, 50);
      final path = [for (var i = 0; i < 80; i++) Offset(80 + i * 7.0, 400 + (i % 5) * 3.0)];
      final one = EraseSession(base: doc, mode: EraserMode.stroke)..addAll(path);
      one.flush();
      final many = EraseSession(base: doc, mode: EraserMode.stroke);
      for (var i = 0; i < path.length; i += 4) {
        many.addAll(path.skip(i).take(4));
        many.flush();
      }
      expect(many.removed, one.removed);
    });

    test('só olha os candidatos da vizinhança (índice espacial)', () {
      final doc = denseDoc(70, 72); // 5.040 traços
      final s = EraseSession(base: doc, mode: EraserMode.stroke);
      s.addAll([for (var i = 0; i < 30; i++) Offset(300 + i * 3.0, 600)]);
      s.flush();
      expect(doc.strokes.length, greaterThan(5000));
      expect(s.candidatesTested, lessThan(400), reason: 'sem o índice seriam ${doc.strokes.length} por lote');
    });

    test('sem contato nada muda: flush devolve false e result é o próprio documento', () {
      final doc = denseDoc(10, 10);
      final s = EraseSession(base: doc, mode: EraserMode.stroke)..add(const Offset(-100, -100));
      expect(s.flush(), isFalse);
      expect(s.changed, isFalse);
      expect(s.result(), same(doc));
    });
  });

  group('EraseSession (borracha parcial)', () {
    test('parte o traço: o original some, os pedaços ficam longe do caminho e o resto é intocado', () {
      final doc = denseDoc(40, 50);
      final s = EraseSession(base: doc, mode: EraserMode.partial);
      final path = [for (var i = 0; i < 20; i++) Offset(120 + i * 5.0, 500)];
      s.addAll(path);
      expect(s.flush(), isTrue);
      final r = s.result();
      expect(r.deleted, isNotEmpty);
      final byId = {for (final e in doc.strokes) e.id: e};
      for (final id in r.deleted) {
        expect(byId.containsKey(id), isTrue);
      }
      // intocados mantêm a instância
      for (final e in doc.strokes) {
        if (!r.deleted.contains(e.id)) expect(identical(r.strokeById(e.id), e), isTrue);
      }
      // pedaços novos não encostam na borracha
      for (final e in r.strokes.where((e) => !byId.containsKey(e.id))) {
        for (final p in e.points) {
          var best = double.infinity;
          for (var i = 0; i + 1 < path.length; i++) {
            final d = _dist(p.offset, path[i], path[i + 1]);
            if (d < best) best = d;
          }
          expect(best, greaterThanOrEqualTo(kEraserRadius + e.width / 2 - 0.2));
        }
      }
    });

    test('apagar um pedaço criado no mesmo gesto deixa tombstone e não o devolve', () {
      final doc = PageDoc.empty.withStroke(
        Stroke(
          id: 'a',
          tool: PenTool.pen,
          argb: 0xFFFFFFFF,
          width: 3,
          points: [for (var i = 0; i < 40; i++) InkPoint(100 + i * 10.0, 300, 0.5)],
        ),
      );
      final s = EraseSession(base: doc, mode: EraserMode.partial);
      s.add(const Offset(250, 300));
      s.flush();
      final firstPieces = s.created.map((e) => e.id).toSet();
      expect(firstPieces, hasLength(2));
      // volta e apaga o pedaço da esquerda inteiro
      s.addAll([for (var x = 100.0; x <= 240; x += 10) Offset(x, 300)]);
      s.flush();
      final r = s.result();
      expect(r.deleted, containsAll(['a']));
      expect(r.strokes.every((e) => e.id != 'a'), isTrue);
      expect(r.strokes.length, lessThanOrEqualTo(2));
      for (final id in s.removed) {
        expect(r.strokes.any((e) => e.id == id), isFalse);
      }
    });

    test('revision só sobe quando a visão muda', () {
      final doc = denseDoc(20, 20);
      final s = EraseSession(base: doc, mode: EraserMode.partial);
      final r0 = s.revision;
      s.add(const Offset(-50, -50));
      s.flush();
      expect(s.revision, r0);
      s.addAll([for (var i = 0; i < 10; i++) Offset(100 + i * 5.0, 100)]);
      s.flush();
      expect(s.revision, greaterThanOrEqualTo(r0));
    });
  });

  group('Picture com a borracha em andamento', () {
    test('esconder traços e acrescentar pedaços regrava sem recalcular contornos dos que já existem', () {
      final doc = denseDoc(20, 20);
      final cache = PageInkCache();
      cache.pictureFor(doc, const {}, 0, const {});
      final computed = cache.outlinesComputed;
      final piece = Stroke(id: 'p1', tool: PenTool.pen, argb: 0xFFFFFFFF, width: 3, points: const [InkPoint(10, 10, .5), InkPoint(40, 10, .5)]);
      final hidden = <String>{doc.strokes.first.id};
      cache.pictureFor(doc, hidden, 0, const {}, extra: [piece], revision: 1);
      expect(cache.rebuilds, 2);
      expect(cache.outlinesComputed, computed + 1, reason: 'só o pedaço novo');
      // mesmo conjunto mutável, mesma revision: não regrava
      cache.pictureFor(doc, hidden, 0, const {}, extra: [piece], revision: 1);
      expect(cache.rebuilds, 2);
      hidden.add(doc.strokes[1].id);
      cache.pictureFor(doc, hidden, 0, const {}, extra: [piece], revision: 2);
      expect(cache.rebuilds, 3);
      expect(cache.outlinesComputed, computed + 1);
      cache.dispose();
    });
  });

  group('desempenho: 5.000 traços, 480 eventos de borracha (2 s de S Pen a 240 Hz)', () {
    // Serpentina que atravessa a página.
    final events = <Offset>[
      for (var i = 0; i < 480; i++)
        Offset(40 + (i % 120) * 7.5, 60 + (i ~/ 120) * 300.0 + ((i % 120) % 2) * 6),
    ];

    int oldFlow(PageDoc start, EraserMode mode) {
      // Fluxo anterior, reproduzido fielmente: a cada evento recalcula sobre o
      // documento inteiro (e o reconstrói); a cada quadro (4 eventos) regrava o
      // Picture da página inteira com os contornos já em cache.
      final paths = <String, Path>{};
      ui.Picture? pic;
      void rerecord(PageDoc d) {
        pic?.dispose();
        final rec = ui.PictureRecorder();
        paintDoc(
          Canvas(rec, const Rect.fromLTWH(0, 0, pageWidth, pageHeight)),
          d,
          pathFor: (s) => paths.putIfAbsent(s.id, () => strokeOutlinePath(s.points, s.tool, s.width)),
        );
        pic = rec.endRecording();
      }

      var doc = start;
      rerecord(doc);
      final sw = Stopwatch()..start();
      Offset? last;
      var n = 0;
      var dirty = false;
      for (final p in events) {
        PageDoc next = doc;
        if (mode == EraserMode.partial) {
          next = erasePartial(doc, [last ?? p, p], kEraserRadius, newInkId);
        } else {
          final ids = hitStrokes(doc, p, kEraserRadius, from: last);
          if (ids.isNotEmpty) next = doc.without(ids);
        }
        if (!identical(next, doc)) {
          doc = next;
          dirty = true;
        }
        last = p;
        if (++n % 4 == 0 && dirty) {
          rerecord(doc);
          dirty = false;
        }
      }
      sw.stop();
      pic?.dispose();
      return sw.elapsedMilliseconds;
    }

    int newFlow(PageDoc start, EraserMode mode) {
      final cache = PageInkCache();
      cache.pictureFor(start, const {}, 0, const {});
      final sw = Stopwatch()..start();
      final s = EraseSession(base: start, mode: mode); // inclui montar o índice
      for (var i = 0; i < events.length; i += 4) {
        // 4 eventos por quadro de 16 ms
        s.addAll(events.skip(i).take(4));
        if (s.flush()) {
          cache.pictureFor(start, s.removed, 0, const {}, extra: s.created, revision: s.revision);
        }
      }
      final end = s.result();
      sw.stop();
      expect(end, isNotNull);
      cache.dispose();
      return sw.elapsedMilliseconds;
    }

    for (final mode in EraserMode.values) {
      test('modo ${mode.name}: antes x depois', () {
        final doc = denseDoc(70, 72);
        expect(doc.strokes.length, greaterThan(5000));
        final before = oldFlow(doc, mode);
        final after = newFlow(doc, mode);
        // ignore: avoid_print
        print('PERF borracha ${mode.name} (5.040 traços, 480 eventos): antes=${before}ms depois=${after}ms '
            'ganho=${(before / (after < 1 ? 1 : after)).toStringAsFixed(1)}x');
        expect(after, lessThan(before ~/ 2), reason: 'antes=$before ms depois=$after ms');
      });
    }
  });
}

double _dist(Offset p, Offset a, Offset b) {
  final dx = b.dx - a.dx, dy = b.dy - a.dy;
  final l2 = dx * dx + dy * dy;
  var t = l2 == 0 ? 0.0 : (((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / l2).clamp(0.0, 1.0);
  final cx = a.dx + t * dx - p.dx, cy = a.dy + t * dy - p.dy;
  return (cx * cx + cy * cy) == 0 ? 0 : (Offset(cx, cy)).distance;
}
