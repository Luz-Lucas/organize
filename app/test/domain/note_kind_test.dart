import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/domain/note.dart';

void main() {
  test('Note.kind é "text" por padrão e vem do mapa quando presente', () {
    expect(const Note(id: 'a', title: 'T').kind, NoteKind.text);
    expect(Note.fromMap({'id': 'a', 'title': 'T'}).kind, NoteKind.text);
    expect(Note.fromMap({'id': 'a', 'title': 'T', 'kind': 'text'}).kind, NoteKind.text);
    final nb = Note.fromMap({'id': 'a', 'title': 'T', 'kind': 'notebook'});
    expect(nb.kind, NoteKind.notebook);
    expect(nb.isNotebook, isTrue);
  });

  test('kind desconhecido cai em texto (nunca quebra a lista)', () {
    expect(Note.fromMap({'id': 'a', 'title': 'T', 'kind': 'outro'}).kind, NoteKind.text);
  });

  test('toMap grava kind e copyWith mantém o kind', () {
    const nb = Note(id: 'a', title: 'T', kind: NoteKind.notebook);
    expect(nb.toMap()['kind'], 'notebook');
    expect(const Note(id: 'a', title: 'T').toMap()['kind'], 'text');
    expect(nb.copyWith(title: 'U').kind, NoteKind.notebook);
  });

  test('kind entra na igualdade', () {
    expect(const Note(id: 'a', title: 'T'), isNot(const Note(id: 'a', title: 'T', kind: NoteKind.notebook)));
  });
}
