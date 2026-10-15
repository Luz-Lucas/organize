import 'dart:ui' hide TextBox;

import '../core/notebook_core.dart';
import 'ink_painting.dart' show strokeOutlinePath;

/// Contorno incremental do traço ao vivo.
///
/// Recalcular o contorno de **todos** os pontos a cada evento custa O(n) por
/// evento (O(n²) no traço). Aqui os pontos antigos viram pedaços fixos
/// (calculados uma vez) e só a cauda — os últimos pontos — é recalculada.
/// Os pedaços se sobrepõem em [overlap] pontos, então a junção fica coberta.
/// O traço final salvo continua sendo calculado inteiro, só a prévia é feita
/// em pedaços.
class LiveStrokeOutline {
  /// Quando a cauda passa disso, o começo dela é fixado.
  static const int tailMax = 48;

  /// Pontos de cada pedaço fixado.
  static const int chunk = 32;

  /// Pontos repetidos entre um pedaço e o seguinte.
  static const int overlap = 6;

  final List<Path> _frozen = [];
  Path? _tail;
  List<InkPoint>? _src;
  PenTool? _tool;
  double? _width;
  int _tailStart = 0;
  int _count = 0;
  List<Path> _view = const [];

  /// Total de pontos entregues ao cálculo de contorno (diagnóstico/testes).
  int pointsOutlined = 0;

  void reset() {
    _frozen.clear();
    _tail = null;
    _src = null;
    _tailStart = 0;
    _count = 0;
    _view = const [];
  }

  /// Caminhos (pedaços fixos + cauda) do traço [pts], que só cresce no fim.
  List<Path> pathsFor(List<InkPoint> pts, PenTool tool, double width) {
    if (pts.isEmpty) {
      reset();
      return const [];
    }
    if (!identical(pts, _src) || tool != _tool || width != _width || pts.length < _count) {
      reset();
      _src = pts;
      _tool = tool;
      _width = width;
    }
    if (pts.length == _count && _tail != null) return _view;
    while (pts.length - _tailStart > tailMax) {
      final end = _tailStart + chunk;
      final piece = pts.sublist(_tailStart, end);
      pointsOutlined += piece.length;
      _frozen.add(strokeOutlinePath(piece, tool, width));
      _tailStart = end - overlap;
    }
    final tail = pts.sublist(_tailStart);
    pointsOutlined += tail.length;
    _tail = strokeOutlinePath(tail, tool, width, complete: false);
    _count = pts.length;
    _view = List.unmodifiable([..._frozen, _tail!]);
    return _view;
  }
}
