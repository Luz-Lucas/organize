import 'note.dart';
import 'notebook_cover.dart';

/// A nota de texto vinculada a um caderno ("Notas — nome do caderno"): tudo o que o
/// usuário manda para as notas do caderno (trechos do PDF, escrita convertida)
/// vai para ela, sempre.
///
/// O vínculo fica no `body` do caderno como `{"linkedNoteId":"…"}`, junto da capa
/// e do PDF (ver [notebookBodyMap]); viaja com o caderno entre aparelhos.
extension NotebookLinkedNote on Note {
  /// O id da nota vinculada, se este caderno já tem uma.
  String? get linkedNoteId {
    if (!isNotebook) return null;
    final id = notebookBodyMap(body)['linkedNoteId'];
    return id is String && id.isNotEmpty ? id : null;
  }

  /// O caderno apontando para [noteId] (`null` solta o vínculo). Capa e PDF ficam.
  Note withLinkedNoteId(String? noteId) => copyWith(body: notebookBodyWith(body, 'linkedNoteId', noteId));
}

/// O caderno cujo vínculo aponta para a nota [noteId], se houver (para o link "Abrir o
/// caderno" na nota vinculada). Barato: só decodifica o `body` de quem cita o id.
Note? notebookLinkedTo(String noteId, Iterable<Note> notes) {
  for (final n in notes) {
    if (n.isNotebook && n.id != noteId && n.body.contains(noteId) && n.linkedNoteId == noteId) return n;
  }
  return null;
}

String _two(int n) => n.toString().padLeft(2, '0');

String _day(DateTime d) => '${_two(d.day)}/${_two(d.month)}';

/// Trecho do PDF como citação (um `>` por parágrafo, para o editor visual abrir
/// sem mexer) e, embaixo, a fonte: "p. N · dd/MM".
String pdfQuoteBlock(String text, int? page, DateTime now) {
  final paragraphs = text
      .replaceAll('\r\n', '\n')
      .split(RegExp(r'\n\s*\n'))
      .map((p) => p.replaceAll(RegExp(r'\s*\n\s*'), ' ').trim())
      .where((p) => p.isNotEmpty);
  final source = [if (page != null) 'p. $page', _day(now)].join(' · ');
  return '${paragraphs.map((p) => '> $p').join('\n\n')}\n\n_${source}_';
}

/// Escrita convertida em texto: um parágrafo normal e a fonte "Caderno · p. N · dd/MM".
String writingBlock(String text, int page, DateTime now) =>
    '${text.replaceAll(RegExp(r'\s+'), ' ').trim()}\n\n_Caderno · p. $page · ${_day(now)}_';

/// [body] com [block] no fim, separado por uma linha em branco.
String appendBlock(String body, String block) {
  final b = body.trimRight();
  return b.isEmpty ? block : '$b\n\n$block';
}

/// [body] sem a última ocorrência de [block] (e sem a separação dele), ou `null`
/// se o bloco não está mais lá (a nota foi editada).
String? removeBlock(String body, String block) {
  final i = body.lastIndexOf(block);
  if (i < 0) return null;
  final before = body.substring(0, i).trimRight();
  final after = body.substring(i + block.length).trimLeft();
  if (after.isEmpty) return before;
  return before.isEmpty ? after : '$before\n\n$after';
}
