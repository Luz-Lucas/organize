import 'dart:math' as math;
import 'dart:ui' hide TextBox;

import 'package:flutter/foundation.dart' show immutable, listEquals;

/// Largura da página em unidades de página.
const double pageWidth = 1000.0;

/// Altura da página (proporção A4) em unidades de página.
const double pageHeight = 1414.0;

/// Distância entre as pautas (pautado), linhas (quadriculado) e pontos (pontilhado).
const double kRuleSpacing = 40.0;

/// y da primeira pauta do papel pautado (acima dela fica o cabeçalho, sem pauta).
const double kLinedTop = 120.0;

/// A última pauta fica pelo menos isto acima do pé da página.
const double kLinedBottomMargin = 30.0;

enum PenTool { fountain, pen, pencil, highlighter }

enum PageBackground { blank, lined, grid, dots }

// ---------------------------------------------------------------------------
// Quantização (a mesma da codificação: o que está na memória é o que é salvo).
// ---------------------------------------------------------------------------

double _q(double v, double scale) {
  if (!v.isFinite) {
    throw ArgumentError.value(v, 'valor', 'precisa ser um número finito');
  }
  return (v * scale).round() / scale;
}

/// Coordenadas e tamanhos de caixas: 0,1 unidade de página.
double quantizeCoord(double v) => _q(v, 10);

/// Pressão: 0–1 com 2 casas.
double quantizePressure(double p) => _q(p.clamp(0.0, 1.0), 100);

/// Espessura e tamanho de fonte: 2 casas.
double quantizeSize(double v) => _q(v, 100);

// ---------------------------------------------------------------------------

/// Um ponto da tinta em unidades de página; [p] é a pressão de 0 a 1.
@immutable
class InkPoint {
  const InkPoint(this.x, this.y, this.p);

  final double x;
  final double y;
  final double p;

  Offset get offset => Offset(x, y);

  InkPoint quantized() =>
      InkPoint(quantizeCoord(x), quantizeCoord(y), quantizePressure(p));

  @override
  bool operator ==(Object other) =>
      other is InkPoint && other.x == x && other.y == y && other.p == p;

  @override
  int get hashCode => Object.hash(x, y, p);

  @override
  String toString() => 'InkPoint($x, $y, $p)';
}

/// Um traço imutável. Para "editar", apague e crie outro com id novo.
@immutable
class Stroke {
  Stroke({
    required this.id,
    required this.tool,
    required this.argb,
    required this.width,
    required List<InkPoint> points,
  }) : points = List.unmodifiable(points) {
    if (points.isEmpty) {
      throw ArgumentError.value(points, 'points', 'traço sem pontos');
    }
  }

  final String id;
  final PenTool tool;

  /// Cor 0xAARRGGBB (a transparência do marca-texto fica no alfa).
  final int argb;

  /// Espessura base em unidades de página (antes da pressão).
  final double width;
  final List<InkPoint> points;

  /// Retângulo que contém todos os pontos, engordado em meia espessura
  /// (área visível aproximada). Calculado uma vez, sob demanda.
  late final Rect bounds = _computeBounds();

  Rect _computeBounds() {
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final p in points) {
      minX = math.min(minX, p.x);
      maxX = math.max(maxX, p.x);
      minY = math.min(minY, p.y);
      maxY = math.max(maxY, p.y);
    }
    final h = width / 2;
    return Rect.fromLTRB(minX - h, minY - h, maxX + h, maxY + h);
  }

  Stroke copyWith({
    String? id,
    PenTool? tool,
    int? argb,
    double? width,
    List<InkPoint>? points,
  }) => Stroke(
    id: id ?? this.id,
    tool: tool ?? this.tool,
    argb: argb ?? this.argb,
    width: width ?? this.width,
    points: points ?? this.points,
  );

  /// Cópia com a quantização da codificação (coordenadas 0,1; pressão 0,01).
  Stroke quantized() => Stroke(
    id: id,
    tool: tool,
    argb: argb,
    width: quantizeSize(width),
    points: [for (final p in points) p.quantized()],
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Stroke &&
          other.id == id &&
          other.tool == tool &&
          other.argb == argb &&
          other.width == width &&
          listEquals(other.points, points);

  @override
  int get hashCode => Object.hash(id, tool, argb, width, points.length);

  @override
  String toString() => 'Stroke($id, ${tool.name}, ${points.length} pts)';
}

/// Valor de [TextBox.font] para a fonte manuscrita (Caveat, embutida no app).
const String kHandwritingFont = 'caveat';

/// Caixa de texto (nome igual ao do plano; colide com `TextBox` do dart:ui —
/// use `hide TextBox` ao importar `flutter/material.dart`, ou o alias
/// [InkText]).
@immutable
class TextBox {
  const TextBox({
    required this.id,
    required this.x,
    required this.y,
    required this.w,
    required this.text,
    required this.size,
    required this.argb,
    this.font,
  });

  final String id;
  final double x;
  final double y;
  final double w;
  final String text;
  final double size;
  final int argb;

  /// Fonte do texto: `null` = a padrão; [kHandwritingFont] = manuscrita (Caveat),
  /// usada quando o corretor troca uma palavra escrita à mão. Versões antigas do
  /// app ignoram o campo e mostram na fonte padrão.
  final String? font;

  /// Retângulo estimado (a altura é uma estimativa por contagem de linhas;
  /// a UI pode medir com `TextPainter` se precisar de exatidão).
  Rect get bounds => Rect.fromLTWH(x, y, w, estimatedHeight);

  double get estimatedHeight {
    var lines = 0;
    final charsPerLine = w <= 0 ? 1.0 : math.max(1.0, w / (size * 0.55));
    for (final para in text.split('\n')) {
      lines += math.max(1, (para.length / charsPerLine).ceil());
    }
    return lines * size * 1.3;
  }

  TextBox copyWith({
    String? id,
    double? x,
    double? y,
    double? w,
    String? text,
    double? size,
    int? argb,
    String? font,
  }) => TextBox(
    id: id ?? this.id,
    x: x ?? this.x,
    y: y ?? this.y,
    w: w ?? this.w,
    text: text ?? this.text,
    size: size ?? this.size,
    argb: argb ?? this.argb,
    font: font ?? this.font,
  );

  TextBox quantized() => copyWith(
    x: quantizeCoord(x),
    y: quantizeCoord(y),
    w: quantizeCoord(w),
    size: quantizeSize(size),
  );

  @override
  bool operator ==(Object other) =>
      other is TextBox &&
      other.id == id &&
      other.x == x &&
      other.y == y &&
      other.w == w &&
      other.text == text &&
      other.size == size &&
      other.argb == argb &&
      other.font == font;

  @override
  int get hashCode => Object.hash(id, x, y, w, text, size, argb, font);

  @override
  String toString() => 'TextBox($id, "$text")';
}

/// Alias de [TextBox] que não colide com o `TextBox` do dart:ui.
typedef InkText = TextBox;

/// Imagem posicionada; [path] é o caminho no Storage (`notebook-images`).
@immutable
class ImageBox {
  const ImageBox({
    required this.id,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.path,
    this.background = false,
  });

  final String id;
  final double x;
  final double y;
  final double w;
  final double h;
  final String path;

  /// Fundo da página (página de um PDF importado): fica sempre por baixo de tudo e
  /// não é selecionado pelo laço nem apagado pela borracha. Versões antigas do app
  /// ignoram o campo e o tratam como imagem comum.
  final bool background;

  Rect get bounds => Rect.fromLTWH(x, y, w, h);

  ImageBox copyWith({
    String? id,
    double? x,
    double? y,
    double? w,
    double? h,
    String? path,
    bool? background,
  }) => ImageBox(
    id: id ?? this.id,
    x: x ?? this.x,
    y: y ?? this.y,
    w: w ?? this.w,
    h: h ?? this.h,
    path: path ?? this.path,
    background: background ?? this.background,
  );

  ImageBox quantized() => copyWith(
    x: quantizeCoord(x),
    y: quantizeCoord(y),
    w: quantizeCoord(w),
    h: quantizeCoord(h),
  );

  @override
  bool operator ==(Object other) =>
      other is ImageBox &&
      other.id == id &&
      other.x == x &&
      other.y == y &&
      other.w == w &&
      other.h == h &&
      other.path == path &&
      other.background == background;

  @override
  int get hashCode => Object.hash(id, x, y, w, h, path, background);

  @override
  String toString() => 'ImageBox($id, $path)';
}
