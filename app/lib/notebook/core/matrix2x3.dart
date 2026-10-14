import 'dart:math' as math;
import 'dart:ui' hide TextBox;

import 'package:flutter/foundation.dart' show immutable;

/// Transformação afim 2D: `x' = a·x + c·y + tx`, `y' = b·x + d·y + ty`.
@immutable
class Matrix2x3 {
  const Matrix2x3(this.a, this.b, this.c, this.d, this.tx, this.ty);

  static const Matrix2x3 identity = Matrix2x3(1, 0, 0, 1, 0, 0);

  factory Matrix2x3.translation(double dx, double dy) =>
      Matrix2x3(1, 0, 0, 1, dx, dy);

  /// Escala [sx] × [sy] (padrão: [sx]) em torno de [anchor] (que não se move).
  factory Matrix2x3.scaling(
    double sx, {
    double? sy,
    Offset anchor = Offset.zero,
  }) {
    final y = sy ?? sx;
    return Matrix2x3(
      sx,
      0,
      0,
      y,
      anchor.dx - sx * anchor.dx,
      anchor.dy - y * anchor.dy,
    );
  }

  /// Rotação de [radians] (sentido horário na tela, y para baixo) em torno de
  /// [anchor].
  factory Matrix2x3.rotation(double radians, {Offset anchor = Offset.zero}) {
    final cs = math.cos(radians), sn = math.sin(radians);
    return Matrix2x3(
      cs,
      sn,
      -sn,
      cs,
      anchor.dx - (cs * anchor.dx - sn * anchor.dy),
      anchor.dy - (sn * anchor.dx + cs * anchor.dy),
    );
  }

  final double a, b, c, d, tx, ty;

  Offset apply(Offset p) =>
      Offset(a * p.dx + c * p.dy + tx, b * p.dx + d * p.dy + ty);

  /// `this * other`: aplica [other] primeiro e depois `this`.
  Matrix2x3 operator *(Matrix2x3 o) => Matrix2x3(
    a * o.a + c * o.b,
    b * o.a + d * o.b,
    a * o.c + c * o.d,
    b * o.c + d * o.d,
    a * o.tx + c * o.ty + tx,
    b * o.tx + d * o.ty + ty,
  );

  /// Quanto o eixo x é esticado.
  double get xScale => math.sqrt(a * a + b * b);

  /// Quanto o eixo y é esticado.
  double get yScale => math.sqrt(c * c + d * d);

  /// Escala média (raiz do módulo do determinante): usada em espessuras.
  double get uniformScale => math.sqrt((a * d - b * c).abs());

  @override
  bool operator ==(Object other) =>
      other is Matrix2x3 &&
      other.a == a &&
      other.b == b &&
      other.c == c &&
      other.d == d &&
      other.tx == tx &&
      other.ty == ty;

  @override
  int get hashCode => Object.hash(a, b, c, d, tx, ty);

  @override
  String toString() => 'Matrix2x3($a, $b, $c, $d, $tx, $ty)';
}
