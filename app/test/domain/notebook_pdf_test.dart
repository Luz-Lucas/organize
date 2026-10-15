import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/domain/note.dart';
import 'package:organizacional/domain/notebook_cover.dart';
import 'package:organizacional/domain/notebook_pdf.dart';
import 'package:organizacional/notebook/pdf/pdf_reader_screen.dart' show cleanPdfText;

void main() {
  const notebook = Note(id: 'c1', title: 'Livro', kind: NoteKind.notebook);
  const a = NotebookPdfFile(path: 'u/c1/a.pdf', name: 'a.pdf', pages: 12);
  const b = NotebookPdfFile(path: 'u/c1/b.pdf', name: 'b.pdf');
  const cover = NotebookCover(kind: CoverKind.emoji, emoji: '📚');

  test('sem PDF', () {
    expect(notebook.pdfInfo, isNull);
    expect(notebook.isPdfBook, isFalse);
    expect(notebook.withPdfBook(true), notebook);
  });

  test('guarda os PDFs em ordem, sem repetir o mesmo caminho', () {
    final n = notebook.withPdfFile(a, book: true).withPdfFile(b).withPdfFile(a);
    expect(n.pdfInfo!.files, [b, a]);
    expect(n.isPdfBook, isTrue, reason: 'sem book, o modo fica');
    expect(n.withPdfBook(false).isPdfBook, isFalse);
    expect(n.withPdfBook(false).pdfInfo!.files, [b, a]);
  });

  test('capa e PDF convivem no body', () {
    final n = notebook.withCover(cover).withPdfFile(a, book: true);
    expect(n.cover, cover);
    expect(n.pdfInfo!.files, [a]);
    final semCapa = n.withCover(null);
    expect(semCapa.cover, isNull);
    expect(semCapa.isPdfBook, isTrue, reason: 'tirar a capa não apaga o PDF');
    final outraCapa = n.withCover(const NotebookCover(kind: CoverKind.text, text: 'x'));
    expect(outraCapa.pdfInfo!.files, [a]);
  });

  test('nota comum não tem PDF', () {
    final body = notebook.withPdfFile(a).body;
    expect(Note(id: 'n', title: 'n', body: body).pdfInfo, isNull);
  });

  test('body inválido ou arquivo sem caminho é ignorado', () {
    expect(notebook.copyWith(body: '{"pdf":{"files":[{"name":"x.pdf"}]}}').pdfInfo, isNull);
    expect(notebook.copyWith(body: '{"pdf":"x"}').pdfInfo, isNull);
  });

  group('cleanPdfText', () {
    test('junta linhas quebradas no meio da frase e mantém os parágrafos', () {
      expect(
        cleanPdfText('O limite de f(x)\r\nquando x tende a 0\n\nSegundo parágrafo\ncom duas linhas'),
        'O limite de f(x) quando x tende a 0\n\nSegundo parágrafo com duas linhas',
      );
    });

    test('desfaz a hifenização no fim da linha', () {
      expect(cleanPdfText('a deriva-\nda da função'), 'a derivada da função');
      expect(cleanPdfText('pré-\nRequisito'), 'pré- Requisito', reason: 'maiúscula: não é palavra partida');
    });

    test('espaços repetidos viram um', () {
      expect(cleanPdfText('  muito    espaço  '), 'muito espaço');
    });
  });
}
