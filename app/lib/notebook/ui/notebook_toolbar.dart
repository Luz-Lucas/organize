import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart' hide TextBox;

import '../../ui/org_theme.dart';
import '../core/notebook_core.dart';
import 'tool_settings.dart';

/// Barra de ferramentas do Caderno: duas linhas rolavem na horizontal (cabe em
/// 360 dp). Linha 1 = ferramentas e ações; linha 2 = opções da ferramenta.
class NotebookToolbar extends StatelessWidget {
  const NotebookToolbar({
    super.key,
    required this.settings,
    required this.palette,
    required this.currentColor,
    required this.background,
    required this.zoom,
    required this.onSettings,
    required this.onCustomColor,
    required this.onBackground,
    required this.onAddPage,
    required this.onInsertImage,
    required this.onZoomIn,
    required this.onZoomOut,
  });

  final ToolSettings settings;
  final List<Color> palette;
  final Color currentColor;
  final PageBackground background;
  final ValueListenable<double> zoom;
  final ValueChanged<ToolSettings> onSettings;
  final VoidCallback onCustomColor;
  final ValueChanged<PageBackground> onBackground;
  final VoidCallback onAddPage;
  final VoidCallback onInsertImage;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  @override
  Widget build(BuildContext context) {
    final org = context.org;
    return Material(
      color: org.surfaceRaised,
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: org.line))),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _scroller([
                _penButton(context, PenTool.fountain, 'nb-tool-fountain', Icons.draw_outlined, 'Tinteiro'),
                _penButton(context, PenTool.pen, 'nb-tool-pen', Icons.edit_outlined, 'Caneta'),
                _penButton(context, PenTool.pencil, 'nb-tool-pencil', Icons.create_outlined, 'Lápis'),
                _penButton(context, PenTool.highlighter, 'nb-tool-highlighter', Icons.border_color_outlined, 'Marca-texto'),
                _divider(org),
                _kindButton(context, ToolKind.eraser, 'nb-tool-eraser', Icons.auto_fix_normal_outlined, 'Borracha'),
                _kindButton(context, ToolKind.lasso, 'nb-tool-lasso', Icons.gesture, 'Laço'),
                _kindButton(context, ToolKind.text, 'nb-tool-text', Icons.text_fields, 'Texto'),
                _btn(context, 'nb-tool-image', Icons.image_outlined, 'Imagem', false, onInsertImage),
                _divider(org),
                _btn(
                  context,
                  'nb-finger-toggle',
                  Icons.touch_app_outlined,
                  settings.fingerDraws ? 'Desenhar com o dedo: ligado' : 'Desenhar com o dedo: desligado',
                  settings.fingerDraws,
                  () => onSettings(settings.copyWith(fingerDraws: !settings.fingerDraws)),
                ),
                PopupMenuButton<PageBackground>(
                  key: const ValueKey('nb-background'),
                  tooltip: 'Fundo da página',
                  icon: Icon(_bgIcon(background)),
                  onSelected: onBackground,
                  itemBuilder: (_) => [
                    for (final b in PageBackground.values)
                      PopupMenuItem(
                        key: ValueKey('nb-bg-${b.name}'),
                        value: b,
                        child: Text(_bgLabel(b)),
                      ),
                  ],
                ),
                _btn(context, 'nb-add-page', Icons.note_add_outlined, 'Nova página', false, onAddPage),
                _divider(org),
                _btn(context, 'nb-zoom-out', Icons.zoom_out, 'Diminuir zoom', false, onZoomOut),
                ValueListenableBuilder<double>(
                  valueListenable: zoom,
                  builder: (_, z, _) => SizedBox(
                    width: 48,
                    child: Text(
                      '${(z * 100).round()}%',
                      key: const ValueKey('nb-zoom-label'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                ),
                _btn(context, 'nb-zoom-in', Icons.zoom_in, 'Aumentar zoom', false, onZoomIn),
              ]),
              _scroller(_options(context)),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _options(BuildContext context) {
    final org = context.org;
    switch (settings.kind) {
      case ToolKind.eraser:
        return [
          TextButton.icon(
            key: const ValueKey('nb-eraser-mode'),
            onPressed: () => onSettings(
              settings.copyWith(
                eraserMode: settings.eraserMode == EraserMode.stroke ? EraserMode.partial : EraserMode.stroke,
              ),
            ),
            icon: Icon(settings.eraserMode == EraserMode.stroke ? Icons.linear_scale : Icons.content_cut, size: 18),
            label: Text(settings.eraserMode == EraserMode.stroke ? 'Apagar traço inteiro' : 'Apagar parte do traço'),
          ),
        ];
      case ToolKind.lasso:
        return [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'Contorne para selecionar',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: org.inkMuted),
            ),
          ),
        ];
      case ToolKind.draw:
      case ToolKind.text:
        return [
          for (var i = 0; i < palette.length; i++) _swatch(context, i, palette[i]),
          IconButton(
            key: const ValueKey('nb-color-custom'),
            tooltip: 'Outra cor',
            onPressed: onCustomColor,
            icon: const Icon(Icons.palette_outlined, size: 22),
          ),
          _divider(org),
          for (var i = 0; i < kPenWidths.length; i++) _widthDot(context, i),
        ];
    }
  }

  Widget _scroller(List<Widget> children) => SizedBox(
    height: 48,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(children: children),
    ),
  );

  Widget _divider(OrgThemeSpec org) => Container(
    width: 1,
    height: 24,
    margin: const EdgeInsets.symmetric(horizontal: 6),
    color: org.line,
  );

  Widget _btn(
    BuildContext context,
    String key,
    IconData icon,
    String tip,
    bool selected,
    VoidCallback onTap,
  ) => IconButton(
    key: ValueKey(key),
    tooltip: tip,
    isSelected: selected,
    icon: Icon(icon, size: 22),
    selectedIcon: Icon(icon, size: 22, color: context.org.accentText),
    style: selected
        ? IconButton.styleFrom(backgroundColor: context.org.accentSoft)
        : null,
    onPressed: onTap,
  );

  Widget _penButton(BuildContext context, PenTool pen, String key, IconData icon, String tip) => _btn(
    context,
    key,
    icon,
    tip,
    settings.kind == ToolKind.draw && settings.pen == pen,
    () => onSettings(settings.copyWith(kind: ToolKind.draw, pen: pen)),
  );

  Widget _kindButton(BuildContext context, ToolKind kind, String key, IconData icon, String tip) => _btn(
    context,
    key,
    icon,
    tip,
    settings.kind == kind,
    () => onSettings(settings.copyWith(kind: kind)),
  );

  Widget _swatch(BuildContext context, int i, Color c) {
    final selected = c.toARGB32() == currentColor.toARGB32();
    return GestureDetector(
      key: ValueKey('nb-color-$i'),
      behavior: HitTestBehavior.opaque,
      onTap: () => onSettings(settings.copyWith(argb: c.toARGB32())),
      child: Container(
        width: 36,
        height: 44,
        alignment: Alignment.center,
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: c,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? context.org.accentText : context.org.line,
              width: selected ? 3 : 1,
            ),
          ),
        ),
      ),
    );
  }

  Widget _widthDot(BuildContext context, int i) {
    final selected = settings.widthIndex == i;
    final d = 6.0 + i * 3.0;
    return GestureDetector(
      key: ValueKey('nb-width-$i'),
      behavior: HitTestBehavior.opaque,
      onTap: () => onSettings(settings.copyWith(widthIndex: i)),
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
    );
  }

  static IconData _bgIcon(PageBackground b) => switch (b) {
    PageBackground.blank => Icons.crop_portrait,
    PageBackground.lined => Icons.view_headline,
    PageBackground.grid => Icons.grid_4x4,
    PageBackground.dots => Icons.more_horiz,
  };

  static String _bgLabel(PageBackground b) => switch (b) {
    PageBackground.blank => 'Em branco',
    PageBackground.lined => 'Pautado',
    PageBackground.grid => 'Quadriculado',
    PageBackground.dots => 'Pontilhado',
  };
}
