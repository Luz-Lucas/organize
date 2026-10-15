import 'dart:async';
import 'dart:ui' show Offset, Rect, Size;

import 'package:organizacional/notebook/core/notebook_core.dart';
import 'package:organizacional/notebook/intelligence/ink_types.dart';
import 'package:organizacional/notebook/intelligence/recognizer.dart';

import '../core/test_support.dart';

/// Reconhecedor de teste: o texto vem de um mapa "ids dos traços (ordenados, com ',')
/// → candidatos" ou de [resolve].
class FakeInkRecognizer extends InkRecognizer {
  FakeInkRecognizer({this.table = const {}, this.ready = true, this.resolve});

  final Map<String, List<String>> table;
  final List<String> Function(List<Stroke> strokes)? resolve;
  bool ready;
  bool throwOnRecognize = false;
  bool throwOnReady = false;

  /// Cada chamada de [recognize]: ids, área e contexto.
  final calls = <({List<String> ids, Size? area, String preContext})>[];

  /// Quando não nulo, [recognize] espera por ele (para testar corridas).
  Completer<void>? gate;

  int downloads = 0;
  int deletes = 0;
  StreamController<double>? downloadCtl;

  @override
  Future<bool> isModelReady() async {
    if (throwOnReady) throw StateError('canal indisponível');
    return ready;
  }

  @override
  Stream<double> downloadModel() {
    downloads++;
    final c = downloadCtl = StreamController<double>();
    return c.stream;
  }

  @override
  Future<void> deleteModel() async {
    deletes++;
    ready = false;
  }

  @override
  Future<List<String>> recognize(List<Stroke> strokes, {Size? writingArea, String preContext = ''}) async {
    final ids = [for (final s in strokes) s.id];
    calls.add((ids: ids, area: writingArea, preContext: preContext));
    if (gate != null) await gate!.future;
    if (throwOnRecognize) throw StateError('falha simulada');
    if (resolve != null) return resolve!(strokes);
    return table[(ids.toList()..sort()).join(',')] ?? const [];
  }
}

/// Documento com um traço curtinho por id.
PageDoc docWithStrokes(List<String> ids, {double dx = 10}) => PageDoc(
      strokes: [
        for (var i = 0; i < ids.length; i++)
          lineStroke(ids[i], Offset(10.0 + i * dx, 100), Offset(10.0 + i * dx + 5, 100)),
      ],
    );

/// Linha com uma palavra por grupo de ids (limites fictícios mas coerentes).
InkLine inkLine(List<List<String>> words, {double top = 90}) {
  final all = [for (final w in words) ...w];
  return InkLine(
    strokeIds: all,
    bounds: Rect.fromLTWH(10, top, 200, 30),
    baselineY: top + 25,
    angle: 0,
    words: [
      for (var i = 0; i < words.length; i++)
        InkWord(strokeIds: words[i], bounds: Rect.fromLTWH(10.0 + i * 60, top, 50, 30)),
    ],
  );
}
