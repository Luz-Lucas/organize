import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart' hide TextBox;

import '../../ui/org_theme.dart';
import '../core/notebook_core.dart';
import 'notebook_prefs.dart';
import 'tool_settings.dart';
import 'tool_widgets.dart';

/// Menu "Ferramentas": folha inferior no celular, painel lateral no tablet/desktop.
///
/// Com a barra **compacta** traz tudo (canetas, cores, espessuras, borracha, laço,
/// texto, imagem, página, zoom, dedo). Com a barra **completa** esses itens já
/// estão na barra e o menu só traz favoritos, o modo da barra e as ações da página.
class NotebookToolsMenu extends StatefulWidget {
  const NotebookToolsMenu({
    super.key,
    required this.settings,
    required this.prefs,
    required this.palette,
    required this.currentColor,
    required this.background,
    required this.zoom,
    required this.canDeletePage,
    required this.onSettings,
    required this.onColor,
    required this.onCustomColor,
    required this.onBackground,
    required this.onAddPage,
    required this.onDuplicatePage,
    required this.onDeletePage,
    required this.onInsertImage,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onPrefs,
    this.onInsertPdf,
    this.onConvertPage,
    this.canConvert = false,
    this.onStraightenPage,
    this.onCopyPageText,
  });

  final ToolSettings settings;
  final NotebookPrefs prefs;
  final List<Color> palette;
  final Color currentColor;
  final PageBackground background;
  final ValueListenable<double> zoom;
  final bool canDeletePage;
  final ValueChanged<ToolSettings> onSettings;
  final ValueChanged<int> onColor;
  final VoidCallback onCustomColor;
  final ValueChanged<PageBackground> onBackground;
  final VoidCallback onAddPage;
  final VoidCallback onDuplicatePage;
  final VoidCallback onDeletePage;
  final VoidCallback onInsertImage;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final ValueChanged<NotebookPrefs> onPrefs;

  /// "Inserir PDF": as páginas do PDF entram no fim do caderno, prontas para escrever
  /// por cima (`null` esconde, ex.: sem leitor de PDF).
  final VoidCallback? onInsertPdf;

  /// "Converter página em texto". Só aparece com [canConvert] (há reconhecedor);
  /// sem ele, o lugar mostra a dica "disponível no Android".
  final VoidCallback? onConvertPage;
  final bool canConvert;

  /// "Endireitar página" (`null` esconde).
  final VoidCallback? onStraightenPage;

  /// "Copiar texto da página" (`null` esconde).
  final VoidCallback? onCopyPageText;

  @override
  State<NotebookToolsMenu> createState() => _NotebookToolsMenuState();
}

class _NotebookToolsMenuState extends State<NotebookToolsMenu> {
  bool _editing = false;

  ToolSettings get _s => widget.settings;
  NotebookPrefs get _prefs => widget.prefs;
  bool get _allTools => _prefs.compact;

  /// Executa [f] depois de fechar o menu (para ações que abrem outra tela/diálogo).
  void _closeThen(VoidCallback f) {
    Navigator.of(context).pop();
    f();
  }

  @override
  Widget build(BuildContext context) {
    final org = context.org;
    final text = Theme.of(context).textTheme;
    return Material(
      key: const ValueKey('nb-tools-menu'),
      color: org.surfaceRaised,
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
              child: Row(
                children: [
                  Expanded(child: Text('Ferramentas', style: text.titleMedium)),
                  IconButton(
                    key: const ValueKey('nb-menu-close'),
                    tooltip: 'Fechar',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_allTools) ..._toolSections(context),
                    ..._pageSection(context),
                    ..._favoritesSection(context),
                    const Divider(),
                    SwitchListTile(
                      key: const ValueKey('nb-compact-toggle'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Barra compacta'),
                      subtitle: const Text('Só as canetas e cores favoritas na barra'),
                      value: _prefs.compact,
                      onChanged: (v) => widget.onPrefs(_prefs.withCompact(v)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _title(String t) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 4),
    child: Text(t, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: context.org.inkMuted)),
  );

  // ---- ferramentas (só com a barra compacta) -------------------------------

  List<Widget> _toolSections(BuildContext context) {
    final org = context.org;
    final isDraw = _s.kind == ToolKind.draw;
    Widget kind(String key, ToolKind k, IconData icon, String tip) => toolIconButton(
      context,
      key: key,
      icon: icon,
      tip: tip,
      selected: _s.kind == k,
      onTap: () => widget.onSettings(_s.copyWith(kind: k)),
    );
    return [
      _title('Canetas'),
      Wrap(
        children: [
          for (final (key, pen) in [
            ('nb-tool-fountain', PenTool.fountain),
            ('nb-tool-pen', PenTool.pen),
            ('nb-tool-pencil', PenTool.pencil),
            ('nb-tool-highlighter', PenTool.highlighter),
          ])
            toolIconButton(
              context,
              key: key,
              icon: penIcon(pen),
              tip: penLabel(pen),
              selected: isDraw && _s.pen == pen,
              onTap: () => widget.onSettings(_s.copyWith(kind: ToolKind.draw, pen: pen)),
            ),
        ],
      ),
      _title('Cores'),
      Wrap(
        children: [
          for (var i = 0; i < widget.palette.length; i++)
            ColorDot(
              key: ValueKey('nb-color-$i'),
              color: widget.palette[i],
              selected: widget.palette[i].toARGB32() == widget.currentColor.toARGB32(),
              onTap: () => widget.onColor(widget.palette[i].toARGB32()),
            ),
          IconButton(
            key: const ValueKey('nb-color-custom'),
            tooltip: 'Outra cor',
            onPressed: widget.onCustomColor,
            icon: const Icon(Icons.palette_outlined, size: 22),
          ),
        ],
      ),
      _title('Espessura'),
      Wrap(
        children: [
          for (var i = 0; i < kPenWidths.length; i++)
            WidthDot(
              key: ValueKey('nb-width-$i'),
              index: i,
              selected: _s.widthIndex == i,
              onTap: () => widget.onSettings(_s.copyWith(widthIndex: i)),
            ),
        ],
      ),
      _title('Outras ferramentas'),
      Wrap(
        children: [
          kind('nb-menu-tool-eraser', ToolKind.eraser, Icons.auto_fix_normal_outlined, 'Borracha'),
          kind('nb-menu-tool-lasso', ToolKind.lasso, Icons.gesture, 'Laço'),
          kind('nb-tool-text', ToolKind.text, Icons.text_fields, 'Texto'),
          toolIconButton(
            context,
            key: 'nb-tool-image',
            icon: Icons.image_outlined,
            tip: 'Imagem',
            selected: false,
            onTap: () => _closeThen(widget.onInsertImage),
          ),
          if (widget.onInsertPdf != null)
            toolIconButton(
              context,
              key: 'nb-insert-pdf',
              icon: Icons.picture_as_pdf_outlined,
              tip: 'Inserir PDF',
              selected: false,
              onTap: () => _closeThen(widget.onInsertPdf!),
            ),
        ],
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const ValueKey('nb-eraser-mode'),
          onPressed: () => widget.onSettings(
            _s.copyWith(eraserMode: _s.eraserMode == EraserMode.stroke ? EraserMode.partial : EraserMode.stroke),
          ),
          icon: Icon(_s.eraserMode == EraserMode.stroke ? Icons.linear_scale : Icons.content_cut, size: 18),
          label: Text(
            _s.eraserMode == EraserMode.stroke
                ? 'Borracha: apagar traço inteiro'
                : 'Borracha: apagar parte do traço',
          ),
        ),
      ),
      Row(children: eraserSizeDots(_s, widget.onSettings)),
      _title('Visualização'),
      Row(
        children: [
          toolIconButton(
            context,
            key: 'nb-zoom-out',
            icon: Icons.zoom_out,
            tip: 'Diminuir zoom',
            selected: false,
            onTap: widget.onZoomOut,
          ),
          ValueListenableBuilder<double>(
            valueListenable: widget.zoom,
            builder: (_, z, _) => SizedBox(
              width: 56,
              child: Text(
                '${(z * 100).round()}%',
                key: const ValueKey('nb-zoom-label'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
          ),
          toolIconButton(
            context,
            key: 'nb-zoom-in',
            icon: Icons.zoom_in,
            tip: 'Aumentar zoom',
            selected: false,
            onTap: widget.onZoomIn,
          ),
        ],
      ),
      SwitchListTile(
        key: const ValueKey('nb-finger-toggle'),
        contentPadding: EdgeInsets.zero,
        secondary: Icon(Icons.touch_app_outlined, color: org.inkMuted),
        title: const Text('Desenhar com o dedo'),
        value: _s.fingerDraws,
        onChanged: (v) => widget.onSettings(_s.copyWith(fingerDraws: v)),
      ),
    ];
  }

  // ---- página ---------------------------------------------------------------

  List<Widget> _pageSection(BuildContext context) {
    return [
      _title('Página'),
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (_allTools)
            PopupMenuButton<PageBackground>(
              key: const ValueKey('nb-background'),
              tooltip: 'Fundo da página',
              icon: Icon(backgroundIcon(widget.background)),
              onSelected: (b) => _closeThen(() => widget.onBackground(b)),
              itemBuilder: (_) => [
                for (final b in PageBackground.values)
                  PopupMenuItem(
                    key: ValueKey('nb-bg-${b.name}'),
                    value: b,
                    child: Text(backgroundLabel(b)),
                  ),
              ],
            ),
          if (_allTools)
            toolIconButton(
              context,
              key: 'nb-add-page',
              icon: Icons.note_add_outlined,
              tip: 'Nova página',
              selected: false,
              onTap: () => _closeThen(widget.onAddPage),
            ),
          toolIconButton(
            context,
            key: 'nb-dup-page',
            icon: Icons.copy_all_outlined,
            tip: 'Duplicar página',
            selected: false,
            onTap: () => _closeThen(widget.onDuplicatePage),
          ),
          toolIconButton(
            context,
            key: 'nb-del-page',
            icon: Icons.delete_outline,
            tip: 'Apagar página',
            selected: false,
            onTap: widget.canDeletePage ? () => _closeThen(widget.onDeletePage) : null,
          ),
        ],
      ),
      ..._writingSection(context),
    ];
  }

  // ---- escrita à mão (fase 2) -------------------------------------------------

  List<Widget> _writingSection(BuildContext context) {
    final convert = widget.onConvertPage;
    final straighten = widget.onStraightenPage;
    final copy = widget.onCopyPageText;
    if (convert == null && straighten == null && copy == null) return const [];
    return [
      _title('Escrita à mão'),
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (convert != null && widget.canConvert)
            toolIconButton(
              context,
              key: 'nb-page-convert',
              icon: Icons.text_fields,
              tip: 'Converter página em texto',
              selected: false,
              onTap: () => _closeThen(convert),
            )
          else if (convert != null)
            Tooltip(
              key: const ValueKey('nb-page-convert-hint'),
              message: 'Converter em texto: disponível no Android',
              child: IconButton(
                icon: const Icon(Icons.text_fields, size: 22),
                onPressed: null,
              ),
            ),
          if (straighten != null)
            toolIconButton(
              context,
              key: 'nb-page-straighten',
              icon: Icons.format_align_left,
              tip: 'Endireitar página',
              selected: false,
              onTap: () => _closeThen(straighten),
            ),
          if (copy != null)
            toolIconButton(
              context,
              key: 'nb-page-copy-text',
              icon: Icons.content_copy,
              tip: 'Copiar texto da página',
              selected: false,
              onTap: () => _closeThen(copy),
            ),
        ],
      ),
    ];
  }

  // ---- favoritos --------------------------------------------------------------

  List<Widget> _favoritesSection(BuildContext context) {
    final org = context.org;
    return [
      _title('Favoritos'),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          key: const ValueKey('nb-fav-edit'),
          onPressed: () => setState(() => _editing = !_editing),
          icon: Icon(_editing ? Icons.expand_less : Icons.star_outline),
          label: Text(_editing ? 'Fechar edição dos favoritos' : 'Editar favoritos'),
        ),
      ),
      if (_editing) ..._favoritesEditor(context, org),
    ];
  }

  List<Widget> _favoritesEditor(BuildContext context, OrgThemeSpec org) {
    final colors = _prefs.colorsFor(org);
    final mine = FavoritePen.fromSettings(_s);
    final labelStyle = Theme.of(context).textTheme.bodyMedium;
    return [
      Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Text('Canetas (${_prefs.pens.length} de $kMaxFavoritePens) — arraste para reordenar', style: labelStyle),
      ),
      ReorderableListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        onReorderItem: (a, b) => widget.onPrefs(_prefs.movePen(a, b)),
        children: [
          for (var i = 0; i < _prefs.pens.length; i++)
            SizedBox(
              key: ValueKey('fav-$i-${_prefs.pens[i].hashCode}'),
              height: 52,
              child: Row(
                key: ValueKey('nb-fav-item-$i'),
                children: [
                  ReorderableDragStartListener(
                    index: i,
                    child: Padding(
                      key: ValueKey('nb-fav-handle-$i'),
                      padding: const EdgeInsets.all(10),
                      child: const Icon(Icons.drag_handle),
                    ),
                  ),
                  PenGlyph(
                    tool: _prefs.pens[i].tool,
                    color: _prefs.pens[i].color(org),
                    widthIndex: _prefs.pens[i].widthIndex,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${penLabel(_prefs.pens[i].tool)}, ${kWidthLabels[_prefs.pens[i].widthIndex]}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    key: ValueKey('nb-fav-remove-$i'),
                    tooltip: 'Remover dos favoritos',
                    icon: const Icon(Icons.close),
                    onPressed: () => widget.onPrefs(_prefs.removePenAt(i)),
                  ),
                ],
              ),
            ),
        ],
      ),
      Row(
        children: [
          PenGlyph(tool: mine.tool, color: mine.color(org), widthIndex: mine.widthIndex),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              key: const ValueKey('nb-fav-add-current'),
              onPressed: _prefs.canAddPen && !_prefs.pens.any((p) => p.sameAs(mine, org))
                  ? () => widget.onPrefs(_prefs.addPen(mine))
                  : null,
              icon: const Icon(Icons.add),
              label: Text(
                _prefs.canAddPen ? 'Adicionar caneta atual' : 'Limite de $kMaxFavoritePens canetas',
              ),
            ),
          ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 4),
        child: Text('Cores (${colors.length} de $kMaxFavoriteColors)', style: labelStyle),
      ),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (var i = 0; i < colors.length; i++)
            InputChip(
              key: ValueKey('nb-fav-color-chip-$i'),
              avatar: CircleAvatar(backgroundColor: Color(colors[i])),
              label: const SizedBox.shrink(),
              labelPadding: EdgeInsets.zero,
              deleteIcon: Icon(Icons.close, key: ValueKey('nb-fav-color-remove-$i'), size: 18),
              deleteButtonTooltipMessage: 'Remover cor dos favoritos',
              onDeleted: () => widget.onPrefs(_prefs.removeColorAt(i, org)),
            ),
        ],
      ),
      Row(
        children: [
          Container(
            width: 24,
            height: 24,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: widget.currentColor,
              shape: BoxShape.circle,
              border: Border.all(color: org.line),
            ),
          ),
          Expanded(
            child: OutlinedButton.icon(
              key: const ValueKey('nb-fav-color-add'),
              onPressed: _prefs.canAddColor(org) ? () => widget.onPrefs(_prefs.addColor(widget.currentColor.toARGB32(), org)) : null,
              icon: const Icon(Icons.add),
              label: Text(
                _prefs.canAddColor(org) ? 'Adicionar cor atual' : 'Limite de $kMaxFavoriteColors cores',
              ),
            ),
          ),
        ],
      ),
    ];
  }
}

/// Ajuste rápido de uma caneta favorita: espessura e cor, com "Salvar no favorito".
class NotebookQuickAdjust extends StatelessWidget {
  const NotebookQuickAdjust({
    super.key,
    required this.settings,
    required this.favoriteColors,
    required this.currentColor,
    required this.onSettings,
    required this.onSave,
  });

  final ToolSettings settings;
  final List<int> favoriteColors;
  final Color currentColor;
  final ValueChanged<ToolSettings> onSettings;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final org = context.org;
    return Material(
      key: const ValueKey('nb-quick-adjust'),
      color: org.surfaceRaised,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${penLabel(settings.pen)}: ajuste rápido', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                children: [
                  for (var i = 0; i < kPenWidths.length; i++)
                    WidthDot(
                      key: ValueKey('nb-quick-width-$i'),
                      index: i,
                      selected: settings.widthIndex == i,
                      onTap: () => onSettings(settings.copyWith(widthIndex: i)),
                    ),
                ],
              ),
              Wrap(
                children: [
                  for (var i = 0; i < favoriteColors.length; i++)
                    ColorDot(
                      key: ValueKey('nb-quick-color-$i'),
                      color: Color(favoriteColors[i]),
                      selected: (favoriteColors[i] & 0xFFFFFF) == (currentColor.toARGB32() & 0xFFFFFF),
                      onTap: () => onSettings(settings.copyWith(argb: favoriteColors[i])),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const ValueKey('nb-quick-save'),
                onPressed: onSave,
                icon: const Icon(Icons.star),
                label: const Text('Salvar no favorito'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opções da borracha (aparecem ao tocar de novo na borracha já selecionada).
class NotebookEraserQuick extends StatelessWidget {
  const NotebookEraserQuick({super.key, required this.settings, required this.onSettings});

  final ToolSettings settings;
  final ValueChanged<ToolSettings> onSettings;

  @override
  Widget build(BuildContext context) {
    final stroke = settings.eraserMode == EraserMode.stroke;
    return Material(
      key: const ValueKey('nb-quick-adjust'),
      color: context.org.surfaceRaised,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Borracha', style: Theme.of(context).textTheme.titleSmall),
              TextButton.icon(
                key: const ValueKey('nb-eraser-mode'),
                onPressed: () =>
                    onSettings(settings.copyWith(eraserMode: stroke ? EraserMode.partial : EraserMode.stroke)),
                icon: Icon(stroke ? Icons.linear_scale : Icons.content_cut, size: 18),
                label: Text(stroke ? 'Apagar traço inteiro' : 'Apagar parte do traço'),
              ),
              Text('Tamanho', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.org.inkMuted)),
              Row(children: eraserSizeDots(settings, onSettings)),
            ],
          ),
        ),
      ),
    );
  }
}
