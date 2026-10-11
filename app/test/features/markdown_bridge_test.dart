import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/features/notes/markdown_bridge.dart';

const corpus = [
  '# Título\n\nTexto com **negrito** e _itálico_.',
  '- [ ] tarefa aberta\n- [x] tarefa feita',
  '- item 1\n- item 2\n\n1. um\n2. dois',
  '> citação',
  'Veja [[Cálculo — Resumo]] e [[Redes]].',
  '```\ncódigo\n```',
  '[site](https://example.com)',
];

void main() {
  for (final md in corpus) {
    test('ida e volta: ${md.split('\n').first}', () {
      final once = documentToNoteMarkdown(noteMarkdownToDocument(md));
      expect(once, md);
      expect(documentToNoteMarkdown(noteMarkdownToDocument(once)), once);
    });
  }

  test('link wiki vira href wiki: no documento', () {
    final doc = noteMarkdownToDocument('Veja [[Redes]].');
    expect(jsonEncode(doc.toJson()), contains('wiki:Redes'));
  });

  test('nota mista com wikilink, checklist e título é estável', () {
    const md = '# Meu título\n\nVeja [[Cálculo — Resumo]].\n\n'
        '- [ ] a\n- [x] b\n\nFim.';
    expect(documentToNoteMarkdown(noteMarkdownToDocument(md)), md);
  });

  group('canRoundTripMarkdown', () {
    test('conteúdo que o editor preserva passa', () {
      for (final md in corpus) {
        expect(canRoundTripMarkdown(md), isTrue, reason: md);
      }
    });
    test('tabela, HTML e citação com listas não passam', () {
      expect(canRoundTripMarkdown('| a | b |\n|---|---|\n| 1 | 2 |'), isFalse);
      expect(canRoundTripMarkdown('<details>oculto</details>'), isFalse);
      expect(canRoundTripMarkdown('> - item'), isFalse);
    });
  });
  test('link wiki com parênteses sobrevive à ida e volta', () {
    const md = 'Veja [[Reunião (2026)]].';
    expect(documentToNoteMarkdown(noteMarkdownToDocument(md)), md);
  });
}
