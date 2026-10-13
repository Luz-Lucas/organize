import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart' hide TextBox;

import '../../ui/org_theme.dart';
import '../core/notebook_core.dart';
import 'notebook_prefs.dart';
import 'tool_settings.dart';
import 'tool_widgets.dart';

/// Barra de ferramentas do Caderno.
///
/// * **Compacta** (padrão): só as canetas e cores favoritas, borracha, laço,
///   desfazer/refazer e o botão "Ferramentas" (o menu com todo o resto).
/// * **Completa**: a barra antiga de duas linhas (ferramentas e opções).
///
/// Desfazer, refazer e "Ferramentas" ficam sempre fixos à direita; o resto rola
/// na horizontal (cabe em 360 dp).
class NotebookToolbar extends StatelessWidget {
  const NotebookToolbar({
    super.key,
    required this.settings,
    required this.prefs,
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
    required this.onUndo,
    required this.onRedo,
    required this.onMore,
    required this.onFavoritePen,
    required this.onFavoriteColor,
    required this.onEraserOptions,
  });

  final ToolSettings settings;
  final NotebookPrefs prefs;
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

  /// `null` desabilita (nada a desfazer/refazer).
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback onMore;

  /// Toque na caneta/cor favorita de índice `i` (a tela decide: selecionar, ajuste rápido…).
  final ValueChanged<int> onFavoritePen;
  final ValueChanged<int> onFavoriteColor;

  /// Toque na borracha que já está selecionada.
  final VoidCallback onEraserOptions;

  @override
  Widget build(BuildContext context) {
    final org = context.org;
    return Material(
      color: org.surfaceRaised,
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: org.line))),
        child: SafeArea(
          top: false,
          child: prefs.compact ? _compact(context) : _full(context),
        ),
      ),
    );
  }

  // ---- compacta -----------------------------------------------------------

  Widget _compact(BuildContext context) {
    final org = context.org;
    final colors = prefs.colorsFor(org);
    final mine = FavoritePen.fromSettings(settings);
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  for (var i = 0; i < prefs.pens.length; i++) _favPen(context, i, prefs.pens[i], mine),
                  if (prefs.pens.isNotEmpty && colors.isNotEmpty) _divider(org),
                  for (var i = 0; i < colors.length; i++)
                    ColorDot(
                      key: ValueKey('nb-fav-color-$i'),
                      color: Color(colors[i]),
                      selected: (colors[i] & 0xFFFFFF) == (currentColor.toARGB32() & 0xFFFFFF),
                      onTap: () => onFavoriteColor(i),
                    ),
                  _divider(org),
                  _eraser(context),
                  toolIconButton(
                    context,
                    key: 'nb-tool-lasso',
                    icon: Icons.gesture,
                    tip: 'Laço',
                    selected: settings.kind == ToolKind.lasso,
                    onTap: () => onSettings(settings.copyWith(kind: ToolKind.lasso)),
                  ),
                ],
              ),
            ),
          ),
          _trailing(context),
        ],
      ),
    );
  }

  Widget _favPen(BuildContext context, int i, FavoritePen p, FavoritePen mine) {
    final org = context.org;
    final selected = settings.kind == ToolKind.draw && p.sameAs(mine, org);
    return IconButton(
      key: ValueKey('nb-fav-pen-$i'),
      tooltip: '${penLabel(p.tool)}, ${kWidthLabels[p.widthIndex]}',
      icon: PenGlyph(tool: p.tool, color: p.color(org), widthIndex: p.widthIndex),
      style: selected ? IconButton.styleFrom(backgroundColor: org.accentSoft) : null,
      onPressed: () => onFavoritePen(i),
    );
  }

  Widget _eraser(BuildContext context) {
    final selected = settings.kind == ToolKind.eraser;
    return toolIconButton(
      context,
      key: 'nb-tool-eraser',
      icon: Icons.auto_fix_normal_outlined,
      tip: 'Borracha',
      selected: selected,
      onTap: selected ? onEraserOptions : () => onSettings(settings.copyWith(kind: ToolKind.eraser)),
    );
  }

  /// Desfazer, refazer e "Ferramentas": sempre visíveis.
  Widget _trailing(BuildContext context) {
    final org = context.org;
    final wide = MediaQuery.sizeOf(context).width >= 520;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 1, height: 24, margin: const EdgeInsets.only(right: 2), color: org.line),
          IconButton(
            key: const ValueKey('nb-undo'),
            tooltip: 'Desfazer',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.undo),
            onPressed: onUndo,
          ),
          IconButton(
            key: const ValueKey('nb-redo'),
            tooltip: 'Refazer',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.redo),
            onPressed: onRedo,
          ),
          if (wide)
            TextButton.icon(
              key: const ValueKey('nb-more'),
              onPressed: onMore,
              icon: const Icon(Icons.more_horiz),
              label: const Text('Ferramentas'),
            )
          else
            IconButton(
              key: const ValueKey('nb-more'),
              tooltip: 'Ferramentas',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.more_horiz),
              onPressed: onMore,
            ),
        ],
      ),
    );
  }

  // ---- completa (barra antiga) -------------------------------------------

  Widget _full(BuildContext context) {
    final org = context.org;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 48,
          child: Row(
            children: [
              Expanded(
                child: _scroller([
                  _penButton(context, PenTool.fountain, 'nb-tool-fountain'),
                  _penButton(context, PenTool.pen, 'nb-tool-pen'),
                  _penButton(context, PenTool.pencil, 'nb-tool-pencil'),
                  _penButton(context, PenTool.highlighter, 'nb-tool-highlighter'),
                  _divider(org),
                  _kindButton(context, ToolKind.eraser, 'nb-tool-eraser', Icons.auto_fix_normal_outlined, 'Borracha'),
                  _kindButton(context, ToolKind.lasso, 'nb-tool-lasso', Icons.gesture, 'Laço'),
                  _kindButton(context, ToolKind.text, 'nb-tool-text', Icons.text_fields, 'Texto'),
                  toolIconButton(
                    context,
                    key: 'nb-tool-image',
                    icon: Icons.image_outlined,
                    tip: 'Imagem',
                    selected: false,
                    onTap: onInsertImage,
                  ),
                  _divider(org),
                  toolIconButton(
                    context,
                    key: 'nb-finger-toggle',
                    icon: Icons.touch_app_outlined,
                    tip: settings.fingerDraws ? 'Desenhar com o dedo: ligado' : 'Desenhar com o dedo: desligado',
                    selected: settings.fingerDraws,
                    onTap: () => onSettings(settings.copyWith(fingerDraws: !settings.fingerDraws)),
                  ),
                  PopupMenuButton<PageBackground>(
                    key: const ValueKey('nb-background'),
                    tooltip: 'Fundo da página',
                    icon: Icon(backgroundIcon(background)),
                    onSelected: onBackground,
                    itemBuilder: (_) => [
                      for (final b in PageBackground.values)
                        PopupMenuItem(
                          key: ValueKey('nb-bg-${b.name}'),
                          value: b,
                          child: Text(backgroundLabel(b)),
                        ),
                    ],
                  ),
                  toolIconButton(
                    context,
                    key: 'nb-add-page',
                    icon: Icons.note_add_outlined,
                    tip: 'Nova página',
                    selected: false,
                    onTap: onAddPage,
                  ),
                  _divider(org),
                  toolIconButton(
                    context,
                    key: 'nb-zoom-out',
                    icon: Icons.zoom_out,
                    tip: 'Diminuir zoom',
                    selected: false,
                    onTap: onZoomOut,
                  ),
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
                  toolIconButton(
                    context,
                    key: 'nb-zoom-in',
                    icon: Icons.zoom_in,
                    tip: 'Aumentar zoom',
                    selected: false,
                    onTap: onZoomIn,
                  ),
                ]),
              ),
              _trailing(context),
            ],
          ),
        ),
        SizedBox(height: 48, child: _scrollerRaw(_options(context))),
      ],
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
          for (var i = 0; i < palette.length; i++)
            ColorDot(
              key: ValueKey('nb-color-$i'),
              color: palette[i],
              selected: palette[i].toARGB32() == currentColor.toARGB32(),
              onTap: () => onSettings(settings.copyWith(argb: palette[i].toARGB32())),
            ),
          IconButton(
            key: const ValueKey('nb-color-custom'),
            tooltip: 'Outra cor',
            onPressed: onCustomColor,
            icon: const Icon(Icons.palette_outlined, size: 22),
          ),
          _divider(org),
          for (var i = 0; i < kPenWidths.length; i++)
            WidthDot(
              key: ValueKey('nb-width-$i'),
              index: i,
              selected: settings.widthIndex == i,
              onTap: () => onSettings(settings.copyWith(widthIndex: i)),
            ),
        ];
    }
  }

  Widget _scroller(List<Widget> children) => _scrollerRaw(children);

  Widget _scrollerRaw(List<Widget> children) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Row(children: children),
  );

  Widget _divider(OrgThemeSpec org) => Container(
    width: 1,
    height: 24,
    margin: const EdgeInsets.symmetric(horizontal: 6),
    color: org.line,
  );

  Widget _penButton(BuildContext context, PenTool pen, String key) => toolIconButton(
    context,
    key: key,
    icon: penIcon(pen),
    tip: penLabel(pen),
    selected: settings.kind == ToolKind.draw && settings.pen == pen,
    onTap: () => onSettings(settings.copyWith(kind: ToolKind.draw, pen: pen)),
  );

  Widget _kindButton(BuildContext context, ToolKind kind, String key, IconData icon, String tip) => toolIconButton(
    context,
    key: key,
    icon: icon,
    tip: tip,
    selected: settings.kind == kind,
    onTap: () => onSettings(settings.copyWith(kind: kind)),
  );
}
