import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/core/notebook_core.dart';

import 'test_support.dart';

/// Medidas do núcleo com 2.000 traços x 100 pontos (imprime os tempos; os
/// limites são folgados para não dar falso negativo em máquina lenta).
void main() {
  late PageDoc a, b;
  late String encoded;

  setUpAll(() {
    final r = Random(11);
    final common = [
      for (var i = 0; i < 1000; i++) handwritingStroke(newInkId(), r),
    ];
    final onlyA = [
      for (var i = 0; i < 1000; i++) handwritingStroke(newInkId(), r),
    ];
    final onlyB = [
      for (var i = 0; i < 1000; i++) handwritingStroke(newInkId(), r),
    ];
    // a e b compartilham 1000 traços e cada um tem 1000 próprios: união de
    // 3000, com 2000 em cada lado (visão de dois aparelhos).
    a = PageDoc.empty.withStrokes([...common, ...onlyA]);
    b = PageDoc.empty.withStrokes([...common, ...onlyB]);
  });

  int ms(void Function() f) {
    final sw = Stopwatch()..start();
    f();
    return sw.elapsedMilliseconds;
  }

  test('encode / decode / merge de 2.000 traços x 100 pontos', () {
    late PageDoc back;
    final tEnc = ms(() => encoded = encodePage(a));
    final tDec = ms(() => back = decodePage(encoded));
    late PageDoc merged;
    final tMerge = ms(() => merged = a.merge(b));
    // ignore: avoid_print
    print(
      'PERF encode=${tEnc}ms decode=${tDec}ms merge=${tMerge}ms '
      'tamanho=${encoded.length}B pontos=${a.strokes.length * 100}',
    );
    expect(back, a);
    expect(merged.strokes.length, 3000);
    expect(tEnc, lessThan(5000));
    expect(tDec, lessThan(5000));
    expect(tMerge, lessThan(2000));
  });

  test('operações de edição em página com 2.000 traços', () {
    final tAdd = ms(() {
      var d = a;
      for (var i = 0; i < 50; i++) {
        d = d.withStroke(handwritingStroke(newInkId(), Random(i)));
      }
    });
    final tHit = ms(() {
      for (var i = 0; i < 100; i++) {
        hitStrokes(
          a,
          Offset(100.0 + i * 8, 700),
          10,
          from: Offset(92.0 + i * 8, 700),
        );
      }
    });
    final path = [for (var i = 0; i < 40; i++) Offset(100.0 + i * 20, 700)];
    final tErase = ms(() => erasePartial(a, path, 12, newInkId));
    final tHistory = ms(() {
      final d2 = a.withStroke(handwritingStroke(newInkId(), Random(1)));
      final h = const History().record(a, d2);
      h.undo(d2);
    });
    // ignore: avoid_print
    print(
      'PERF 50x withStroke=${tAdd}ms 100x hitStrokes=${tHit}ms '
      'erasePartial(40 pts)=${tErase}ms record+undo=${tHistory}ms',
    );
    expect(tAdd, lessThan(2000));
    expect(tHit, lessThan(1000));
    expect(tErase, lessThan(1000));
    expect(tHistory, lessThan(1000));
  });
}
