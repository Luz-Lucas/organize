import 'package:flutter/material.dart' hide TextBox;

import '../../ui/org_theme.dart';
import '../core/notebook_core.dart';
import 'tool_settings.dart';

/// Máximo de canetas favoritas e de cores favoritas na barra compacta.
const int kMaxFavoritePens = 8;
const int kMaxFavoriteColors = 8;

/// Uma caneta favorita: ferramenta + cor + espessura (como os "presets" do
/// Samsung Notes). [argb] nulo = a cor de tinta do tema atual.
@immutable
class FavoritePen {
  const FavoritePen({required this.tool, this.argb, this.widthIndex = 1});

  final PenTool tool;
  final int? argb;

  /// Índice em [kPenWidths].
  final int widthIndex;

  /// A caneta que [s] está usando agora.
  factory FavoritePen.fromSettings(ToolSettings s) =>
      FavoritePen(tool: s.pen, argb: s.argb, widthIndex: s.widthIndex);

  Color color(OrgThemeSpec org) => Color(argb ?? org.ink.toARGB32());

  /// Mesma caneta? Compara o RGB já resolvido (o alfa da caneta é à parte).
  bool sameAs(FavoritePen o, OrgThemeSpec org) =>
      tool == o.tool &&
      widthIndex == o.widthIndex &&
      (color(org).toARGB32() & 0xFFFFFF) == (o.color(org).toARGB32() & 0xFFFFFF);

  /// Aplica esta caneta às [s] (ferramenta de desenho).
  ToolSettings applyTo(ToolSettings s) => s.copyWith(
    kind: ToolKind.draw,
    pen: tool,
    widthIndex: widthIndex,
    argb: argb,
    clearArgb: argb == null,
  );

  Map<String, dynamic> toMap() => {'tool': tool.name, 'argb': argb, 'width': kPenWidths[widthIndex]};

  static FavoritePen? fromMap(Object? m) {
    if (m is! Map) return null;
    final tool = PenTool.values.where((t) => t.name == m['tool']).firstOrNull;
    if (tool == null) return null;
    final argb = m['argb'];
    final width = m['width'];
    return FavoritePen(
      tool: tool,
      argb: argb is int ? argb : null,
      widthIndex: width is num ? _nearestWidth(width.toDouble()) : 1,
    );
  }

  static int _nearestWidth(double w) {
    var best = 0;
    for (var i = 1; i < kPenWidths.length; i++) {
      if ((kPenWidths[i] - w).abs() < (kPenWidths[best] - w).abs()) best = i;
    }
    return best;
  }

  @override
  bool operator ==(Object other) =>
      other is FavoritePen && other.tool == tool && other.argb == argb && other.widthIndex == widthIndex;

  @override
  int get hashCode => Object.hash(tool, argb, widthIndex);
}

/// Preferências do Caderno que viajam entre aparelhos (`user_settings.notebook_prefs`):
/// canetas favoritas, cores favoritas, modo da barra e tamanho da borracha.
///
/// Formato: `{"v":1,"pens":[{"tool":"pen","argb":…,"width":…}],"colors":[argb…],"compact":true,"eraser":1}`.
/// Sem `pens`/`colors` valem os padrões (3 canetas; 5 cores do tema).
@immutable
class NotebookPrefs {
  const NotebookPrefs({required this.pens, this.colors, this.compact = true, this.eraserSize = kDefaultEraserSize});

  final List<FavoritePen> pens;

  /// `null` = as 5 primeiras cores do tema (ainda não personalizadas).
  final List<int>? colors;

  /// Barra compacta (só favoritos) ou a barra completa antiga.
  final bool compact;

  /// Último tamanho de borracha escolhido (índice em [kEraserRadii]).
  final int eraserSize;

  static const List<FavoritePen> defaultPens = [
    FavoritePen(tool: PenTool.pen, widthIndex: 1), // preta (tinta do tema)
    FavoritePen(tool: PenTool.pen, argb: 0xFF60A5FA, widthIndex: 1), // azul
    FavoritePen(tool: PenTool.highlighter, argb: 0xFFFBBF24, widthIndex: 1), // amarelo
  ];

  static const int _defaultColorCount = 5;

  factory NotebookPrefs.fromMap(Map<String, dynamic>? m) {
    final pensRaw = m?['pens'];
    final colorsRaw = m?['colors'];
    final compact = m?['compact'];
    final eraser = m?['eraser'];
    return NotebookPrefs(
      pens: pensRaw is List
          ? pensRaw.map(FavoritePen.fromMap).nonNulls.take(kMaxFavoritePens).toList()
          : defaultPens,
      colors: colorsRaw is List ? colorsRaw.whereType<int>().take(kMaxFavoriteColors).toList() : null,
      compact: compact is bool ? compact : true,
      eraserSize: eraser is int && eraser >= 0 && eraser < kEraserRadii.length ? eraser : kDefaultEraserSize,
    );
  }

  Map<String, dynamic> toMap() => {
    'v': 1,
    'pens': [for (final p in pens) p.toMap()],
    if (colors != null) 'colors': colors,
    'compact': compact,
    'eraser': eraserSize,
  };

  List<int> colorsFor(OrgThemeSpec org) =>
      colors ?? notebookPalette(org).take(_defaultColorCount).map((c) => c.toARGB32()).toList();

  bool get canAddPen => pens.length < kMaxFavoritePens;
  bool canAddColor(OrgThemeSpec org) => colorsFor(org).length < kMaxFavoriteColors;

  NotebookPrefs _with({List<FavoritePen>? pens, List<int>? colors, bool? compact, int? eraserSize}) => NotebookPrefs(
    pens: pens ?? this.pens,
    colors: colors ?? this.colors,
    compact: compact ?? this.compact,
    eraserSize: eraserSize ?? this.eraserSize,
  );

  NotebookPrefs withCompact(bool v) => _with(compact: v);

  NotebookPrefs withEraserSize(int i) => _with(eraserSize: i.clamp(0, kEraserRadii.length - 1));

  /// Acrescenta [p] no fim (ignora se já existe igual ou se chegou ao limite).
  NotebookPrefs addPen(FavoritePen p) => !canAddPen || pens.contains(p) ? this : _with(pens: [...pens, p]);

  NotebookPrefs removePenAt(int i) =>
      i < 0 || i >= pens.length ? this : _with(pens: [...pens]..removeAt(i));

  NotebookPrefs replacePenAt(int i, FavoritePen p) =>
      i < 0 || i >= pens.length ? this : _with(pens: [...pens]..[i] = p);

  /// Move a caneta [from] para a posição final [to] (convenção do
  /// `ReorderableListView.onReorderItem`).
  NotebookPrefs movePen(int from, int to) {
    if (from < 0 || from >= pens.length) return this;
    final next = [...pens];
    next.insert(to.clamp(0, next.length - 1), next.removeAt(from));
    return _with(pens: next);
  }

  NotebookPrefs addColor(int argb, OrgThemeSpec org) {
    final cur = colorsFor(org);
    final rgb = argb & 0xFFFFFF;
    if (cur.length >= kMaxFavoriteColors || cur.any((c) => (c & 0xFFFFFF) == rgb)) return this;
    return _with(colors: [...cur, argb]);
  }

  NotebookPrefs removeColorAt(int i, OrgThemeSpec org) {
    final cur = colorsFor(org);
    return i < 0 || i >= cur.length ? this : _with(colors: [...cur]..removeAt(i));
  }
}
