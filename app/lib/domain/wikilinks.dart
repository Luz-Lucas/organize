import 'note.dart';

class WikiLink {
  const WikiLink(this.target, this.label);

  final String target;
  final String label;
}

final _wikiLink = RegExp(r'\[\[([^\[\]|]+?)(?:\|([^\[\]]+?))?\]\]');
final _spaces = RegExp(r'\s+');

String normalizeTitle(String title) =>
    title.trim().replaceAll(_spaces, ' ').toLowerCase();

List<WikiLink> parseWikiLinks(String body) => [
      for (final m in _wikiLink.allMatches(body))
        if (m.group(1)!.trim().isNotEmpty)
          WikiLink(m.group(1)!.trim(), (m.group(2) ?? m.group(1)!).trim()),
    ];

Note? resolveWikiLink(String target, Iterable<Note> notes) {
  final key = normalizeTitle(target);
  for (final note in notes) {
    if (normalizeTitle(note.title) == key) return note;
  }
  return null;
}

List<Note> backlinksFor(Note target, Iterable<Note> notes) {
  final key = normalizeTitle(target.title);
  return notes
      .where((n) =>
          n.id != target.id &&
          parseWikiLinks(n.body).any((l) => normalizeTitle(l.target) == key))
      .toList()
    ..sort((a, b) => a.title.compareTo(b.title));
}

String wikiLinksToMarkdown(String body) => body.replaceAllMapped(_wikiLink, (m) {
      final target = m.group(1)!.trim();
      if (target.isEmpty) return m.group(0)!;
      final label = (m.group(2) ?? m.group(1)!).trim();
      return '[$label](wiki:${encodeWikiTarget(target)})';
    });

String uniqueTitle(String base, Iterable<Note> notes) {
  final taken = {for (final n in notes) normalizeTitle(n.title)};
  if (!taken.contains(normalizeTitle(base))) return base;
  var i = 2;
  while (taken.contains(normalizeTitle('$base $i'))) {
    i++;
  }
  return '$base $i';
}

/// `Uri.encodeComponent` deixa `(` e `)` intactos, o que quebra o link
/// Markdown `[x](wiki:...)`; aqui eles também são codificados.
String encodeWikiTarget(String target) =>
    Uri.encodeComponent(target).replaceAll('(', '%28').replaceAll(')', '%29');
