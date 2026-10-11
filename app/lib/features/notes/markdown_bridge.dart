import 'package:appflowy_editor/appflowy_editor.dart';
// markdown já vem como dependência do appflowy_editor.
import 'package:markdown/markdown.dart' as md;

import '../../domain/wikilinks.dart';

/// Tipo de bloco usado para blocos de código (o appflowy_editor lê, mas não
/// traz um componente para ele).
const codeBlockType = 'code';

final _wikiHref = RegExp(r'\[([^\[\]]*)\]\(wiki:([^()\s]*)\)');

/// Decodificador de blocos de código cercados (```), que o decodificador
/// padrão do appflowy_editor descarta.
class CodeFenceParser extends CustomMarkdownParser {
  const CodeFenceParser();

  @override
  List<Node> transform(
    md.Node element,
    List<CustomMarkdownParser> parsers, {
    MarkdownListType listType = MarkdownListType.unknown,
    int? startNumber,
  }) {
    if (element is! md.Element || element.tag != 'pre') return [];
    final code = element.children?.whereType<md.Element>().firstOrNull;
    if (code == null || code.tag != 'code') return [];
    var text = code.textContent;
    if (text.endsWith('\n')) text = text.substring(0, text.length - 1);
    final cls = code.attributes['class'] ?? '';
    final language =
        cls.startsWith('language-') ? cls.substring('language-'.length) : '';
    return [
      Node(
        type: codeBlockType,
        attributes: {
          'delta': (Delta()..insert(text)).toJson(),
          if (language.isNotEmpty) 'language': language,
        },
      ),
    ];
  }
}

/// Markdown da nota (com `[[Título]]`) -> documento do editor. Os links wiki
/// viram links comuns com href `wiki:<título codificado>`.
Document noteMarkdownToDocument(String md) => markdownToDocument(
      wikiLinksToMarkdown(md),
      markdownParsers: const [CodeFenceParser()],
    );

String _inline(Node node) {
  final delta = node.delta;
  return delta == null ? '' : DeltaMarkdownEncoder().convert(delta);
}

String _indent(String block, String prefix) =>
    block.split('\n').map((l) => l.isEmpty ? l : '$prefix$l').join('\n');

/// Um bloco e seus filhos (listas aninhadas), sem separadores finais.
String _block(Node node, int number) {
  final own = switch (node.type) {
    'paragraph' => _inline(node),
    'heading' =>
      '${'#' * ((node.attributes['level'] as int?) ?? 1)} ${_inline(node)}',
    'bulleted_list' => '- ${_inline(node)}',
    'numbered_list' => '$number. ${_inline(node)}',
    'todo_list' =>
      '- [${node.attributes['checked'] == true ? 'x' : ' '}] ${_inline(node)}',
    'quote' => _inline(node)
        .split('\n')
        .map((l) => l.isEmpty ? '>' : '> $l')
        .join('\n'),
    codeBlockType =>
      '```${node.attributes['language'] ?? ''}\n${node.delta?.toPlainText() ?? ''}\n```',
    'divider' => '---',
    _ => _fallback(node),
  };
  if (node.children.isEmpty) return own;
  final kids = _blocks(node.children.toList());
  return '$own\n${_indent(kids, '  ')}';
}

/// Tipos sem encoder próprio (imagem, tabela...) usam o do pacote.
String _fallback(Node node) {
  final doc = Document.blank()..insert([0], [node.copyWith()]);
  return documentToMarkdown(doc).trimRight();
}

bool _isList(Node n) =>
    n.type == 'bulleted_list' ||
    n.type == 'numbered_list' ||
    n.type == 'todo_list';

String _blocks(List<Node> nodes) {
  final out = StringBuffer();
  var number = 0;
  for (var i = 0; i < nodes.length; i++) {
    final n = nodes[i];
    final prev = i > 0 ? nodes[i - 1] : null;
    number = n.type == 'numbered_list' && prev?.type == 'numbered_list'
        ? number + 1
        : 1;
    if (prev != null) {
      out.write(_isList(n) && prev.type == n.type ? '\n' : '\n\n');
    }
    out.write(_block(n, number));
  }
  return out.toString();
}

/// Documento do editor -> Markdown da nota. Gera sempre a forma canônica
/// (`-` para marcadores, linha em branco entre blocos, itens de lista do
/// mesmo tipo colados), reverte `[X](wiki:X)` para `[[X]]` (ou `[[X|rótulo]]`)
/// e normaliza o fim de linha.
String documentToNoteMarkdown(Document d) {
  final raw = _blocks(d.root.children.toList());
  final text = raw.replaceAllMapped(_wikiHref, (m) {
    final label = m.group(1)!;
    final String target;
    try {
      target = Uri.decodeComponent(m.group(2)!);
    } on ArgumentError {
      return m.group(0)!;
    }
    return label == target ? '[[$target]]' : '[[$target|$label]]';
  });
  return text.replaceAll('\r\n', '\n').trimRight();
}
