import 'package:flutter/material.dart' hide TextBox;

import '../../ui/org_theme.dart';
import '../core/notebook_core.dart';

/// O que a caneta/dedo faz ao tocar a página.
enum ToolKind { draw, eraser, lasso, text }

/// Borracha por traço inteiro ou parcial (parte o traço em pedaços).
enum EraserMode { stroke, partial }

/// Espessuras base (unidades de página) das 5 opções da barra.
const List<double> kPenWidths = [1.5, 3.0, 5.0, 8.0, 14.0];

/// Raio da borracha em unidades de página.
const double kEraserRadius = 12.0;

/// Multiplicador de espessura por caneta (marca-texto é larga).
double penWidthFactor(PenTool t) => t == PenTool.highlighter ? 4.0 : 1.0;

/// Alfa aplicado à cor de cada caneta (marca-texto é translúcido).
int penAlpha(PenTool t) => switch (t) {
  PenTool.highlighter => 0x66,
  PenTool.pencil => 0xE0,
  _ => 0xFF,
};

/// Seleção do usuário na barra: ferramenta, caneta, cor, espessura…
@immutable
class ToolSettings {
  const ToolSettings({
    this.kind = ToolKind.draw,
    this.pen = PenTool.fountain,
    this.argb,
    this.widthIndex = 1,
    this.eraserMode = EraserMode.stroke,
    this.fingerDraws = false,
  });

  final ToolKind kind;
  final PenTool pen;

  /// Cor escolhida (`null` = a cor `ink` do tema atual).
  final int? argb;
  final int widthIndex;
  final EraserMode eraserMode;
  final bool fingerDraws;

  double get baseWidth => kPenWidths[widthIndex];

  ToolSettings copyWith({
    ToolKind? kind,
    PenTool? pen,
    int? argb,
    int? widthIndex,
    EraserMode? eraserMode,
    bool? fingerDraws,
  }) => ToolSettings(
    kind: kind ?? this.kind,
    pen: pen ?? this.pen,
    argb: argb ?? this.argb,
    widthIndex: widthIndex ?? this.widthIndex,
    eraserMode: eraserMode ?? this.eraserMode,
    fingerDraws: fingerDraws ?? this.fingerDraws,
  );
}

/// As 10 cores da barra: tokens do tema atual + neutros semânticos.
List<Color> notebookPalette(OrgThemeSpec org) => <Color>[
  org.ink,
  org.inkMuted,
  org.accent,
  org.accentText,
  org.accentDeep,
  org.secondary,
  const Color(0xFFF2726B),
  const Color(0xFFFBBF24),
  const Color(0xFF4ADE80),
  const Color(0xFF60A5FA),
];

/// Aplica o alfa da caneta à cor (sem tocar no RGB).
int withPenAlpha(int argb, PenTool pen) =>
    (argb & 0x00FFFFFF) | (penAlpha(pen) << 24);
