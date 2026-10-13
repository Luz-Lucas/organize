// Quanto da codificação da página sobra na thread principal (a que desenha os
// quadros) depois de acrescentar um traço: montar o JSON a partir dos fragmentos
// em cache e despachar a compressão para outro isolate.
//
// Rodar: flutter test test/notebook/perf/encode_handoff_perf_test.dart
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/core/notebook_core.dart';

import '../core/test_support.dart';

void main() {
  for (final n in [50, 500, 2000]) {
    test('thread principal ao recodificar uma página de $n traços depois de 1 traço novo', () async {
      final r = Random(5);
      var doc = PageDoc.empty.withStrokes([for (var i = 0; i < n; i++) handwritingStroke(newInkId(), r)]);
      // aquece o JIT e os fragmentos
      await encodePageAsync(doc);
      doc = doc.withStroke(handwritingStroke(newInkId(), r));
      await encodePageAsync(doc);

      final sw = Stopwatch();
      final warm = <double>[];
      for (var i = 0; i < 8; i++) {
        doc = doc.withStroke(handwritingStroke(newInkId(), r));
        sw
          ..reset()
          ..start();
        final f = encodePageAsync(doc); // o que roda na thread principal até devolver o Future
        warm.add(sw.elapsedMicroseconds / 1000);
        await f;
      }
      warm.sort();

      // referência: tudo na thread principal (como era)
      final fresh = decodePage(encodePage(doc)); // traços sem fragmentos em cache
      sw
        ..reset()
        ..start();
      encodePage(fresh);
      final cold = sw.elapsedMicroseconds / 1000;

      final median = warm[warm.length ~/ 2];
      // ignore: avoid_print
      print(
        'PERF $n traços: thread principal por recodificação (mediana de 8)=${median.toStringAsFixed(2)}ms '
        'máx=${warm.last.toStringAsFixed(2)}ms | codificação completa sem cache (antes)=${cold.toStringAsFixed(1)}ms '
        '| isolates=${PageCodecStats.isolateRuns}',
      );
      expect(median, lessThan(cold / 2), reason: 'o cache de fragmentos + isolate tem que custar bem menos que codificar tudo');
    });
  }
}
