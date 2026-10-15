import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/domain/note.dart';
import 'package:organizacional/domain/notebook_cover.dart';

void main() {
  const notebook = Note(id: 'c1', title: 'Cálculo', kind: NoteKind.notebook);

  test('ida e volta pelo body, nos três tipos', () {
    const covers = [
      NotebookCover(kind: CoverKind.text, text: 'Cálculo I', color: 0xFF7C3AED),
      NotebookCover(kind: CoverKind.emoji, emoji: '📐', color: 0xFFF5F5F4),
      NotebookCover(kind: CoverKind.image, imagePath: 'u/c1/x.png', fit: CoverFit.fit, color: 0xFF1E293B),
    ];
    for (final c in covers) {
      expect(NotebookCover.fromBody(c.toBody()), c);
      expect(notebook.withCover(c).cover, c);
    }
  });

  test('sem capa: body vazio, texto comum ou JSON de outra coisa', () {
    expect(notebook.cover, isNull);
    expect(NotebookCover.fromBody('anotação qualquer'), isNull);
    expect(NotebookCover.fromBody('{quebrado'), isNull);
    expect(NotebookCover.fromBody('{"outra":1}'), isNull);
    expect(NotebookCover.fromBody('{"cover":{"kind":"nada"}}'), isNull);
  });

  test('capa sem conteúdo não vale', () {
    expect(NotebookCover.fromBody('{"cover":{"kind":"text","text":"  "}}'), isNull);
    expect(NotebookCover.fromBody('{"cover":{"kind":"image"}}'), isNull);
  });

  test('withCover(null) tira a capa', () {
    final c = notebook.withCover(const NotebookCover(kind: CoverKind.emoji, emoji: '🧪'));
    expect(c.withCover(null).body, '');
    expect(c.withCover(null).cover, isNull);
  });

  test('nota comum nunca tem capa', () {
    final body = const NotebookCover(kind: CoverKind.text, text: 'x').toBody();
    expect(Note(id: 'n1', title: 'n', body: body).cover, isNull);
  });

  test('texto de busca: só o texto da capa de texto', () {
    expect(
      notebook.withCover(const NotebookCover(kind: CoverKind.text, text: 'Derivadas')).coverSearchText,
      'Derivadas',
    );
    expect(notebook.withCover(const NotebookCover(kind: CoverKind.emoji, emoji: '📐')).coverSearchText, '');
    expect(notebook.coverSearchText, '');
  });
}
