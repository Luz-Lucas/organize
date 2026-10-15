import 'package:flutter/material.dart' hide TextBox;

import '../../ui/org_theme.dart';
import '../core/notebook_core.dart';
import 'tool_settings.dart';

/// Peças compartilhadas pela barra, pelo menu "Ferramentas" e pelo ajuste rápido.

IconData penIcon(PenTool t) => switch (t) {
  PenTool.fountain => Icons.draw_outlined,
  PenTool.pen => Icons.edit_outlined,
  PenTool.pencil => Icons.create_outlined,
  PenTool.highlighter => Icons.border_color_outlined,
};

String penLabel(PenTool t) => switch (t) {
  PenTool.fountain => 'Tinteiro',
  PenTool.pen => 'Caneta',
  PenTool.pencil => 'Lápis',
  PenTool.highlighter => 'Marca-texto',
};

const List<String> kWidthLabels = ['fina', 'média fina', 'média', 'grossa', 'extragrossa'];

IconData backgroundIcon(PageBackground b) => switch (b) {
  PageBackground.blank => Icons.crop_portrait,
  PageBackground.lined => Icons.view_headline,
  PageBackground.grid => Icons.grid_4x4,
  PageBackground.dots => Icons.more_horiz,
};

String backgroundLabel(PageBackground b) => switch (b) {
  PageBackground.blank => 'Em branco',
  PageBackground.lined => 'Pautado',
  PageBackground.grid => 'Quadriculado',
  PageBackground.dots => 'Pontilhado',
};

/// Bolinha de cor (36×44 de área de toque).
class ColorDot extends StatelessWidget {
  const ColorDot({super.key, required this.color, required this.selected, required this.onTap, this.tooltip});

  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final dot = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 36,
        height: 44,
        alignment: Alignment.center,
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? context.org.accentText : context.org.line,
              width: selected ? 3 : 1,
            ),
          ),
        ),
      ),
    );
    return tooltip == null ? dot : Tooltip(message: tooltip!, child: dot);
  }
}

/// Bolinha de espessura (o diâmetro cresce com [index]).
class WidthDot extends StatelessWidget {
  const WidthDot({super.key, required this.index, required this.selected, required this.onTap});

  final int index;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = 6.0 + index * 3.0;
    return Tooltip(
      message: 'Espessura ${kWidthLabels[index]}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 36,
          height: 44,
          alignment: Alignment.center,
          child: Container(
            width: d,
            height: d,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? context.org.accentText : context.org.inkMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// Tamanho da borracha: um anel que cresce com [index] (em [kEraserRadii]).
class EraserSizeDot extends StatelessWidget {
  const EraserSizeDot({super.key, required this.index, required this.selected, required this.onTap});

  final int index;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = 8.0 + index * 6.0;
    final org = context.org;
    return Tooltip(
      message: 'Borracha ${kEraserSizeLabels[index].toLowerCase()}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 40,
          height: 44,
          alignment: Alignment.center,
          child: Container(
            width: d,
            height: d,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? org.accentSoft : null,
              border: Border.all(color: selected ? org.accentText : org.inkMuted, width: selected ? 2.5 : 1.5),
            ),
          ),
        ),
      ),
    );
  }
}

/// Os tamanhos da borracha, do menor ao maior.
List<Widget> eraserSizeDots(ToolSettings settings, ValueChanged<ToolSettings> onSettings) => [
  for (var i = 0; i < kEraserRadii.length; i++)
    EraserSizeDot(
      key: ValueKey('nb-eraser-size-$i'),
      index: i,
      selected: settings.eraserSize == i,
      onTap: () => onSettings(settings.copyWith(eraserSize: i)),
    ),
];

/// Botão de ícone da barra, com destaque quando selecionado.
Widget toolIconButton(
  BuildContext context, {
  required String key,
  required IconData icon,
  required String tip,
  required bool selected,
  required VoidCallback? onTap,
}) => IconButton(
  key: ValueKey(key),
  tooltip: tip,
  isSelected: selected,
  icon: Icon(icon, size: 22),
  selectedIcon: Icon(icon, size: 22, color: context.org.accentText),
  style: selected ? IconButton.styleFrom(backgroundColor: context.org.accentSoft) : null,
  onPressed: onTap,
);

/// Ícone da caneta na cor do favorito + traço indicando a espessura.
class PenGlyph extends StatelessWidget {
  const PenGlyph({super.key, required this.tool, required this.color, required this.widthIndex});

  final PenTool tool;
  final Color color;
  final int widthIndex;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(penIcon(tool), size: 22, color: color),
        const SizedBox(height: 2),
        Container(
          width: 18,
          height: 1.5 + widthIndex * 1.1,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
      ],
    );
  }
}
