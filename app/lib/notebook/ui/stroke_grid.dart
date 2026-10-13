import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' hide TextBox;

import '../core/notebook_core.dart';

/// Índice espacial simples: grade fixa sobre a página; cada traço entra nas
/// células que o seu `bounds` cobre. Serve para a borracha olhar só os traços
/// da vizinhança em vez de percorrer a página inteira a cada evento.
///
/// Traços fora da página (ou maiores que ela) caem nas células da borda; o
/// resultado de [query] sempre é filtrado pelo `bounds` de verdade.
class StrokeGrid {
  StrokeGrid.empty();

  factory StrokeGrid.build(Iterable<Stroke> strokes) {
    final g = StrokeGrid.empty();
    for (final s in strokes) {
      g.add(s);
    }
    return g;
  }

  /// Lado de cada célula, em unidades de página.
  static const double cell = 64;
  static final int cols = (pageWidth / cell).ceil();
  static final int rows = (pageHeight / cell).ceil();

  final List<Stroke> _items = [];
  final List<List<int>?> _cells = List<List<int>?>.filled(cols * rows, null);
  Int32List _mark = Int32List(64);
  int _stamp = 0;

  int get length => _items.length;

  static int _cx(double x) => (x / cell).floor().clamp(0, cols - 1);
  static int _cy(double y) => (y / cell).floor().clamp(0, rows - 1);

  void add(Stroke s) {
    final i = _items.length;
    _items.add(s);
    final b = s.bounds;
    final x0 = _cx(b.left), x1 = _cx(b.right), y0 = _cy(b.top), y1 = _cy(b.bottom);
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        (_cells[y * cols + x] ??= <int>[]).add(i);
      }
    }
  }

  /// Traços cujo `bounds` encosta em [zone], sem repetidos, na ordem em que
  /// entraram no índice.
  List<Stroke> query(Rect zone) {
    if (_items.isEmpty) return const [];
    if (_mark.length < _items.length) {
      _mark = Int32List(math.max(_items.length, _mark.length * 2));
      _stamp = 0;
    }
    final stamp = ++_stamp;
    final hit = <int>[];
    final x0 = _cx(zone.left), x1 = _cx(zone.right), y0 = _cy(zone.top), y1 = _cy(zone.bottom);
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final c = _cells[y * cols + x];
        if (c == null) continue;
        for (final i in c) {
          if (_mark[i] == stamp) continue;
          _mark[i] = stamp;
          if (_items[i].bounds.overlaps(zone)) hit.add(i);
        }
      }
    }
    hit.sort();
    return [for (final i in hit) _items[i]];
  }
}
