import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide TextBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/core/notebook_core.dart';
import 'package:organizacional/notebook/ui/ink_painting.dart';

PageDoc docOf(int n, {int highlightEvery = 0}) => PageDoc.empty.withStrokes([
  for (var i = 0; i < n; i++)
    Stroke(
      id: 's${i.toString().padLeft(5, '0')}',
      tool: highlightEvery > 0 && i % highlightEvery == 0 ? PenTool.highlighter : PenTool.pen,
      argb: highlightEvery > 0 && i % highlightEvery == 0 ? 0x66FBBF24 : (0xFF000000 | (i * 7919 & 0xFFFFFF)),
      width: highlightEvery > 0 && i % highlightEvery == 0 ? 20 : 3,
      points: [for (var k = 0; k < 12; k++) InkPoint(20 + (i % 40) * 22.0 + k * 3, 30 + (i ~/ 40) * 9.0 + (k % 3), 0.5)],
    ),
]);

Future<Uint8List> render(ui.Picture p) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.drawRect(const Rect.fromLTWH(0, 0, 1000, 1414), Paint()..color = const Color(0xFF202020));
  c.drawPicture(p);
  final img = await rec.endRecording().toImage(500, 707);
  final bytes = (await img.toByteData())!;
  return bytes.buffer.asUint8List();
}

void main() {
  group('Picture por blocos de traços', () {
    test('esconder um traço regrava só o bloco que o contém', () {
      final doc = docOf(2000);
      final cache = PageInkCache();
      cache.pictureFor(doc, const {}, 0, const {});
      final base = cache.chunksRecorded;
      expect(base, greaterThan(4), reason: '2.000 traços em vários blocos');
      final hidden = <String>{doc.strokes[700].id};
      cache.pictureFor(doc, hidden, 0, const {}, revision: 1);
      expect(cache.chunksRecorded - base, 1);
      hidden.add(doc.strokes[1900].id);
      cache.pictureFor(doc, hidden, 0, const {}, revision: 2);
      expect(cache.chunksRecorded - base, 2);
      cache.dispose();
    });

    test('traço novo no fim regrava só o último bloco', () {
      final doc = docOf(2000);
      final cache = PageInkCache();
      cache.pictureFor(doc, const {}, 0, const {});
      final base = cache.chunksRecorded;
      final next = doc.withStroke(
        Stroke(id: 'zzzzzz', tool: PenTool.pen, argb: 0xFFFFFFFF, width: 3, points: const [InkPoint(5, 5, .5), InkPoint(80, 90, .5)]),
      );
      cache.pictureFor(next, const {}, 0, const {});
      expect(cache.chunksRecorded - base, 1);
      cache.dispose();
    });

    test('pedaços extras (borracha parcial) só regravam o bloco dos extras', () {
      final doc = docOf(2000);
      final cache = PageInkCache();
      cache.pictureFor(doc, const {}, 0, const {});
      final base = cache.chunksRecorded;
      final piece = Stroke(id: 'p1', tool: PenTool.pen, argb: 0xFFFFFFFF, width: 3, points: const [InkPoint(5, 5, .5), InkPoint(80, 90, .5)]);
      cache.pictureFor(doc, const {}, 0, const {}, extra: [piece], revision: 1);
      expect(cache.chunksRecorded - base, 1);
      cache.dispose();
    });

    testWidgets('a imagem final é igual à gravação direta (ordem: marca-texto, tinta, pedaços; escondidos somem)', (tester) async {
      await tester.runAsync(() async {
        final doc = docOf(700, highlightEvery: 9);
        final hidden = <String>{doc.strokes[3].id, doc.strokes[260].id, doc.strokes[509].id, doc.strokes[9].id};
        final piece = Stroke(id: 'pz', tool: PenTool.pen, argb: 0xFFFF0000, width: 8, points: const [InkPoint(30, 40, .5), InkPoint(600, 80, .5)]);

        final cache = PageInkCache();
        final chunked = await render(cache.pictureFor(doc, hidden, 0, const {}, extra: [piece], revision: 1));

        final rec = ui.PictureRecorder();
        paintDoc(Canvas(rec, const Rect.fromLTWH(0, 0, 1000, 1414)), doc, hidden: hidden, extraStrokes: [piece]);
        final direct = await render(rec.endRecording());

        expect(chunked.length, direct.length);
        var diff = 0;
        for (var i = 0; i < chunked.length; i++) {
          if (chunked[i] != direct[i]) diff++;
        }
        expect(diff, 0, reason: 'pixels diferentes: $diff');
        cache.dispose();
      });
    });
  });
}
