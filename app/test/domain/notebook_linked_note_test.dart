import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/domain/note.dart';
import 'package:organizacional/domain/notebook_cover.dart';
import 'package:organizacional/domain/notebook_linked_note.dart';
import 'package:organizacional/domain/notebook_pdf.dart';

void main() {
  const pdf = NotebookPdfFile(path: 'u/c1/0.pdf', name: 'Cálculo.pdf', pages: 10);
  final cover = NotebookCover(kind: CoverKind.emoji, emoji: '📒');
  Note notebook() => const Note(id: 'c1', title: 'Cálculo', kind: NoteKind.notebook)
      .withPdfFile(pdf, book: true)
      .withCover(cover);

  group('vínculo no body do caderno', () {
    test('sem vínculo: null', () {
      expect(notebook().linkedNoteId, isNull);
      expect(const Note(id: 'x', title: 'x').linkedNoteId, isNull, reason: 'nota de texto nunca tem vínculo');
    });

    test('grava o id sem perder capa nem PDF', () {
      final n = notebook().withLinkedNoteId('n9');
      expect(n.linkedNoteId, 'n9');
      expect(n.cover, cover);
      expect(n.pdfInfo!.files, [pdf]);
      expect(n.isPdfBook, isTrue);
      expect(jsonDecode(n.body)['linkedNoteId'], 'n9');
    });

    test('limpar o vínculo mantém o resto; sem nada, o body fica vazio', () {
      final n = notebook().withLinkedNoteId('n9').withLinkedNoteId(null);
      expect(n.linkedNoteId, isNull);
      expect(n.cover, cover);
      expect(const Note(id: 'c', title: 'c', kind: NoteKind.notebook).withLinkedNoteId('a').withLinkedNoteId(null).body, '');
    });

    test('trocar capa ou PDF depois não apaga o vínculo', () {
      final n = notebook().withLinkedNoteId('n9').withCover(null).withPdfBook(false);
      expect(n.linkedNoteId, 'n9');
    });
  });

  group('notebookLinkedTo', () {
    test('acha o caderno cujo body aponta para a nota', () {
      final a = notebook().withLinkedNoteId('n9');
      final other = const Note(id: 'c2', title: 'Outro', kind: NoteKind.notebook).withLinkedNoteId('n8');
      final text = const Note(id: 'n9', title: 'Notas — Cálculo');
      expect(notebookLinkedTo('n9', [other, text, a])?.id, 'c1');
      expect(notebookLinkedTo('n7', [other, text, a]), isNull);
    });

    test('nota de texto que só cita o id no corpo não conta', () {
      const t = Note(id: 't', title: 't', body: '{"linkedNoteId":"n9"}');
      expect(notebookLinkedTo('n9', [t]), isNull);
    });
  });

  group('blocos', () {
    final day = DateTime(2026, 10, 19, 14);

    test('trecho do PDF: citação por parágrafo e fonte "p. N · dd/MM"', () {
      expect(pdfQuoteBlock('O limite\n\nsegundo', 3, day), '> O limite\n\n> segundo\n\n_p. 3 · 19/10_');
    });

    test('trecho do PDF sem página: só a data', () {
      expect(pdfQuoteBlock('Algo', null, day), '> Algo\n\n_19/10_');
    });

    test('data com zero à esquerda', () {
      expect(pdfQuoteBlock('Algo', 1, DateTime(2026, 3, 5)), '> Algo\n\n_p. 1 · 05/03_');
    });

    test('escrita convertida: parágrafo normal e "Caderno · p. N · dd/MM"', () {
      expect(writingBlock('o gato\nquase', 2, day), 'o gato quase\n\n_Caderno · p. 2 · 19/10_');
    });

    test('appendBlock separa por linha em branco; nota vazia leva só o bloco', () {
      expect(appendBlock('', 'B'), 'B');
      expect(appendBlock('  \n', 'B'), 'B');
      expect(appendBlock('A\n', 'B'), 'A\n\nB');
    });

    test('removeBlock tira o último bloco igual e a separação', () {
      expect(removeBlock('A\n\nB', 'B'), 'A');
      expect(removeBlock('B', 'B'), '');
      expect(removeBlock('A\n\nB\n\nC', 'B'), 'A\n\nC');
      expect(removeBlock('B\n\nA\n\nB', 'B'), 'B\n\nA');
    });

    test('removeBlock devolve null se o bloco não está mais lá', () {
      expect(removeBlock('A', 'B'), isNull);
    });
  });
}
