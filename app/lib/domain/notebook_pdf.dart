import 'note.dart';
import 'notebook_cover.dart';

/// Um PDF guardado no caderno: o arquivo original, no Storage do caderno.
///
/// As páginas do caderno têm o PDF só como imagem de fundo; o original é o que
/// permite ler com o texto de verdade (selecionar e virar nota).
class NotebookPdfFile {
  const NotebookPdfFile({required this.path, required this.name, this.pages = 0});

  /// Caminho no Storage do caderno.
  final String path;

  /// Nome do arquivo (com `.pdf`).
  final String name;

  /// Quantas páginas o PDF tem (0 = não se sabe).
  final int pages;

  Map<String, dynamic> toMap() => {'path': path, 'name': name, if (pages > 0) 'pages': pages};

  static NotebookPdfFile? fromMap(Object? m) {
    if (m is! Map) return null;
    final path = m['path'], name = m['name'], pages = m['pages'];
    if (path is! String || path.isEmpty) return null;
    return NotebookPdfFile(path: path, name: name is String ? name : 'PDF', pages: pages is int ? pages : 0);
  }

  @override
  bool operator ==(Object other) =>
      other is NotebookPdfFile && other.path == path && other.name == name && other.pages == pages;

  @override
  int get hashCode => Object.hash(path, name, pages);
}

/// Os PDFs de um caderno e como ele abre: [book] = só leitura, como um livro
/// (abre direto no leitor de PDF); senão é um caderno normal para escrever por cima.
///
/// Fica no `body` do caderno como `{"pdf":{"book":true,"files":[…]}}`.
class NotebookPdfInfo {
  const NotebookPdfInfo({this.files = const [], this.book = false});

  final List<NotebookPdfFile> files;
  final bool book;

  Map<String, dynamic> toMap() => {
    if (book) 'book': true,
    'files': [for (final f in files) f.toMap()],
  };

  static NotebookPdfInfo? fromMap(Object? m) {
    if (m is! Map) return null;
    final raw = m['files'];
    final files = [
      if (raw is List)
        for (final f in raw) ?NotebookPdfFile.fromMap(f),
    ];
    if (files.isEmpty) return null;
    return NotebookPdfInfo(files: files, book: m['book'] == true);
  }
}

extension NotebookPdfNote on Note {
  /// Os PDFs guardados neste caderno, se houver.
  NotebookPdfInfo? get pdfInfo => isNotebook ? NotebookPdfInfo.fromMap(notebookBodyMap(body)['pdf']) : null;

  /// Abre como livro (só leitura do PDF)?
  bool get isPdfBook => pdfInfo?.book ?? false;

  /// O caderno com mais um PDF guardado (o mesmo caminho não se repete). [book]
  /// muda o modo; omitido, mantém.
  Note withPdfFile(NotebookPdfFile file, {bool? book}) {
    final info = pdfInfo;
    final files = [...?info?.files.where((f) => f.path != file.path), file];
    return _withPdf(NotebookPdfInfo(files: files, book: book ?? info?.book ?? false));
  }

  /// O caderno como livro ([book]) ou como caderno de escrever.
  Note withPdfBook(bool book) {
    final info = pdfInfo;
    if (info == null) return this;
    return _withPdf(NotebookPdfInfo(files: info.files, book: book));
  }

  Note _withPdf(NotebookPdfInfo info) => copyWith(body: notebookBodyWith(body, 'pdf', info.toMap()));
}
