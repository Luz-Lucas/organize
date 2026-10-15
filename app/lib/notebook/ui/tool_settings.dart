import 'package:flutter/material.dart' hide TextBox;

import '../../ui/org_theme.dart';
import '../core/notebook_core.dart';

/// O que a caneta/dedo faz ao tocar a página.
enum ToolKind { draw, eraser, lasso, text }

/// Borracha por traço inteiro ou parcial (parte o traço em pedaços).
enum EraserMode { stroke, partial }

/// Espessuras base (unidades de página) das 5 opções da barra.
const List<double> kPenWidths = [1.5, 3.0, 5.0, 8.0, 14.0];

/// Raio da borracha (unidades de página) no tamanho padrão.
const double kEraserRadius = 12.0;

/// Raios da borracha (unidades de página) dos tamanhos da barra.
const List<double> kEraserRadii = [6.0, kEraserRadius, 24.0, 48.0];

/// Nome de cada tamanho de borracha (mesma ordem de [kEraserRadii]).
const List<String> kEraserSizeLabels = ['Pequena', 'Média', 'Grande', 'Enorme'];

/// Tamanho padrão da borracha (índice em [kEraserRadii]).
const int kDefaultEraserSize = 1;

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
    this.eraserSize = kDefaultEraserSize,
    this.fingerDraws = false,
  });

  final ToolKind kind;
  final PenTool pen;

  /// Cor escolhida (`null` = a cor `ink` do tema atual).
  final int? argb;
  final int widthIndex;
  final EraserMode eraserMode;

  /// Tamanho da borracha: índice em [kEraserRadii].
  final int eraserSize;
  final bool fingerDraws;

  double get baseWidth => kPenWidths[widthIndex];

  /// Raio da borracha (unidades de página) no tamanho escolhido.
  double get eraserRadius => kEraserRadii[eraserSize.clamp(0, kEraserRadii.length - 1)];

  ToolSettings copyWith({
    ToolKind? kind,
    PenTool? pen,
    int? argb,
    int? widthIndex,
    EraserMode? eraserMode,
    int? eraserSize,
    bool? fingerDraws,
    bool clearArgb = false,
  }) => ToolSettings(
    kind: kind ?? this.kind,
    pen: pen ?? this.pen,
    argb: clearArgb ? null : (argb ?? this.argb),
    widthIndex: widthIndex ?? this.widthIndex,
    eraserMode: eraserMode ?? this.eraserMode,
    eraserSize: eraserSize ?? this.eraserSize,
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
