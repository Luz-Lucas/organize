import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../ui/org_theme.dart';
import 'markdown_bridge.dart';

/// Componente do bloco de código (```): reaproveita o visual de citação com
/// fonte monoespaçada. O appflowy_editor não traz um para o tipo `code`.
class CodeBlockComponentBuilder extends QuoteBlockComponentBuilder {
  CodeBlockComponentBuilder({super.configuration, super.iconBuilder});
}

/// Digitar `[[Título]]` (ao fechar o segundo `]`) vira um link wiki clicável.
final CharacterShortcutEvent wikiLinkShortcut = CharacterShortcutEvent(
  key: 'wiki link [[Título]]',
  character: ']',
  handler: (editorState) async {
    final selection = editorState.selection;
    if (selection == null || !selection.isCollapsed) return false;
    final node = editorState.getNodeAtPath(selection.start.path);
    final delta = node?.delta;
    if (node == null || delta == null) return false;
    final offset = selection.start.offset;
    final before = delta.toPlainText().substring(0, offset);
    final m = RegExp(r'\[\[([^\[\]]+)\]$').firstMatch(before);
    if (m == null) return false;
    final title = m.group(1)!.trim();
    if (title.isEmpty) return false;
    final tx = editorState.transaction
      ..deleteText(node, m.start, m.end - m.start)
      ..insertText(node, m.start, title,
          attributes: {AppFlowyRichTextKeys.href: 'wiki:${Uri.encodeComponent(title)}'})
      ..afterSelection = Selection.collapsed(
        Position(path: node.path, offset: m.start + title.length),
      );
    await editorState.apply(tx);
    return true;
  },
);

/// Editor rico (WYSIWYG) de uma nota. O Markdown continua sendo o formato
/// salvo: [initialMarkdown] entra, [onChanged] devolve Markdown.
///
/// [onChanged] só dispara quando o documento realmente é editado (abrir a
/// nota, focar ou mover o cursor não dispara).
class RichNoteEditor extends StatefulWidget {
  const RichNoteEditor({
    super.key,
    required this.initialMarkdown,
    required this.onChanged,
    required this.onWikiLink,
    this.footer,
  });

  final String initialMarkdown;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onWikiLink;

  /// Conteúdo depois do texto, dentro da rolagem do editor (ex.: backlinks).
  final Widget? footer;

  @override
  State<RichNoteEditor> createState() => RichNoteEditorState();
}

class RichNoteEditorState extends State<RichNoteEditor> {
  late EditorState editorState;
  late EditorScrollController _scroll;
  StreamSubscription<EditorTransactionValue>? _sub;

  @override
  void initState() {
    super.initState();
    _create();
  }

  void _create() {
    editorState = EditorState(document: noteMarkdownToDocument(widget.initialMarkdown));
    _scroll = EditorScrollController(editorState: editorState);
    _sub = editorState.transactionStream.listen((value) {
      final (time, transaction, _) = value;
      if (time != TransactionTime.after || transaction.operations.isEmpty) return;
      widget.onChanged(documentToNoteMarkdown(editorState.document));
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scroll.dispose();
    editorState.dispose();
    super.dispose();
  }

  TextSpan _decorate(BuildContext context, Node node, int index, TextInsert text,
      TextSpan before, TextSpan after) {
    final href = text.attributes?[AppFlowyRichTextKeys.href] as String?;
    if (href != null && href.startsWith('wiki:')) {
      final title = Uri.decodeComponent(href.substring('wiki:'.length));
      return TextSpan(
        style: before.style,
        text: text.text,
        recognizer: TapGestureRecognizer()..onTap = () => widget.onWikiLink(title),
        mouseCursor: SystemMouseCursors.click,
      );
    }
    return defaultTextSpanDecoratorForAttribute(context, node, index, text, before, after);
  }

  @override
  Widget build(BuildContext context) {
    final org = context.org;
    final theme = Theme.of(context);
    final body = (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(color: org.ink, height: 1.5);
    final mono = body.copyWith(fontFamily: 'monospace', fontSize: 14);
    TextStyle heading(double size) => body.copyWith(
          fontSize: size,
          fontWeight: FontWeight.w700,
          fontFamily: theme.textTheme.headlineSmall?.fontFamily,
        );
    final style = EditorStyle.desktop(
      padding: EdgeInsets.zero,
      cursorColor: org.accentText,
      selectionColor: org.accentSoft,
      textStyleConfiguration: TextStyleConfiguration(
        text: body,
        bold: const TextStyle(fontWeight: FontWeight.w700),
        href: TextStyle(color: org.accentText, decoration: TextDecoration.underline),
        code: mono.copyWith(color: org.accentText, backgroundColor: org.surfaceRaised),
        lineHeight: 1.5,
      ),
      textSpanDecorator: _decorate,
    );
    final menuStyle = SelectionMenuStyle(
      selectionMenuBackgroundColor: org.surfaceRaised,
      selectionMenuItemTextColor: org.ink,
      selectionMenuItemIconColor: org.inkMuted,
      selectionMenuItemSelectedTextColor: org.accentText,
      selectionMenuItemSelectedIconColor: org.accentText,
      selectionMenuItemSelectedColor: org.accentSoft,
      selectionMenuUnselectedLabelColor: org.inkMuted,
      selectionMenuDividerColor: org.line,
      selectionMenuLinkBorderColor: org.line,
      selectionMenuInvalidLinkColor: theme.colorScheme.error,
      selectionMenuButtonColor: org.accent,
      selectionMenuButtonTextColor: org.onAccent,
      selectionMenuButtonIconColor: org.onAccent,
      selectionMenuButtonBorderColor: org.accent,
      selectionMenuTabIndicatorColor: org.accent,
    );
    final blockText = BlockComponentConfiguration(textStyle: (_, {textSpan}) => body);
    final builders = <String, BlockComponentBuilder>{
      ...standardBlockComponentBuilderMap,
      codeBlockType: CodeBlockComponentBuilder(
        configuration: BlockComponentConfiguration(textStyle: (_, {textSpan}) => mono),
        iconBuilder: (context, node) => Padding(
          padding: const EdgeInsets.only(right: 8, top: 4),
          child: Icon(Icons.code, size: 16, color: org.inkMuted),
        ),
      ),
      'heading': HeadingBlockComponentBuilder(
        configuration: blockText,
        textStyleBuilder: (level) => heading(switch (level) {
          1 => 28,
          2 => 24,
          3 => 20,
          _ => 18,
        }),
      ),
    };
    final shortcuts = <CharacterShortcutEvent>[
      wikiLinkShortcut,
      for (final e in standardCharacterShortcutEvents)
        if (e == slashCommand)
          customSlashCommand(standardSelectionMenuItems, style: menuStyle)
        else
          e,
    ];
    return Localizations.override(
      context: context,
      delegates: const [AppFlowyEditorLocalizations.delegate],
      child: FloatingToolbar(
        items: [
          paragraphItem,
          ...headingItems,
          ...markdownFormatItems,
          quoteItem,
          bulletedListItem,
          numberedListItem,
          linkItem,
        ],
        style: FloatingToolbarStyle(
          backgroundColor: org.surfaceRaised,
          toolbarActiveColor: org.accentText,
          toolbarIconColor: org.ink,
        ),
        editorState: editorState,
        textDirection: TextDirection.ltr,
        editorScrollController: _scroll,
        child: AppFlowyEditor(
          editorState: editorState,
          editorScrollController: _scroll,
          footer: widget.footer,
          editorStyle: style,
          blockComponentBuilders: builders,
          characterShortcutEvents: shortcuts,
        ),
      ),
    );
  }
}
