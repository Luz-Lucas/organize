import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../data/repository.dart';
import '../domain/ids.dart';
import '../domain/note.dart';
import '../domain/wikilinks.dart';
import 'state/notebook_providers.dart';

/// Cria um caderno novo ("Caderno", "Caderno 2"…, ou [title] se dado) com uma página em branco pautada.
/// Lança [RepositoryException] se a nota não puder ser criada; a página é criada
/// "no melhor esforço" (se falhar, o controller cria a primeira ao abrir).
Future<Note> createNotebook(WidgetRef ref, {String? spaceId, String title = 'Caderno'}) async {
  final all = ref.read(notesProvider).value ?? const <Note>[];
  final note = Note(
    id: newId(),
    title: uniqueTitle(title, all),
    spaceId: spaceId,
    kind: NoteKind.notebook,
  );
  await ref.read(repositoryProvider).upsertNote(note);
  try {
    await ref.read(notebookRepositoryProvider).addPage(note.id);
  } on RepositoryException {
    // O controller adiciona a 1ª página quando o caderno abre sem nenhuma.
  }
  return note;
}
