import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/note.dart';
import '../../domain/notebook_cover.dart';
import '../../domain/notebook_pdf.dart';
import '../create_notebook.dart';
import '../state/notebook_providers.dart';
import 'notebook_pdf_store.dart';
import 'pdf_import.dart';
import 'pdf_providers.dart';
import 'pick_pdf.dart';

/// Como usar um PDF importado.
enum PdfOpenMode {
  /// As páginas viram páginas do caderno, para escrever por cima.
  write,

  /// Só leitura, como um livro: abre no leitor de PDF (com seleção de texto).
  read,
}

/// Pergunta se o PDF é para escrever por cima ou só para ler. [canRead] = há leitor
/// de PDF neste aparelho (sem ele, nem pergunta: é para escrever).
Future<PdfOpenMode?> askPdfMode(BuildContext context, {required bool canRead}) async {
  if (!canRead) return PdfOpenMode.write;
  return showDialog<PdfOpenMode>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Como usar este PDF?'),
      children: [
        ListTile(
          key: const Key('pdf-mode-write'),
          leading: const Icon(Icons.edit_note),
          title: const Text('Para escrever'),
          subtitle: const Text('As páginas viram um caderno; escreva e desenhe por cima.'),
          onTap: () => Navigator.of(ctx).pop(PdfOpenMode.write),
        ),
        ListTile(
          key: const Key('pdf-mode-read'),
          leading: const Icon(Icons.menu_book_outlined),
          title: const Text('Só ler (como livro)'),
          subtitle: const Text('Abre o PDF original; selecione trechos para virar notas.'),
          onTap: () => Navigator.of(ctx).pop(PdfOpenMode.read),
        ),
      ],
    ),
  );
}

/// Cria um caderno-livro a partir de [pdf]: guarda o PDF original no caderno e usa
/// a 1ª página como capa. Lança [PdfImportException] (PDF que não abre) ou
/// [RepositoryException] (sem rede…); nesses casos nada fica criado.
Future<Note> createPdfBook(WidgetRef ref, PickedPdf pdf, {String? spaceId}) async {
  if (pdf.bytes.length > kMaxStoredPdfBytes) {
    throw PdfImportException('O PDF passa de ${kMaxStoredPdfBytes ~/ (1024 * 1024)} MB.');
  }
  final rasterizer = ref.read(pdfRasterizerProvider);
  // Confere se o PDF abre antes de criar qualquer coisa.
  final pages = rasterizer.supported ? await rasterizer.pageCount(pdf.bytes) : 0;
  final note = await createNotebook(ref, spaceId: spaceId, title: notebookTitleForPdf(pdf.name));
  final repo = ref.read(repositoryProvider);
  try {
    final path = await ref.read(notebookPdfStoreFactoryProvider)(note.id).uploadPdf(pdf.bytes);
    var book = note.withPdfFile(NotebookPdfFile(path: path, name: pdf.name, pages: pages), book: true);
    final cover = await _firstPageCover(ref, note.id, pdf);
    if (cover != null) book = book.withCover(cover);
    await repo.upsertNote(book);
    return book;
  } catch (_) {
    try {
      await repo.deleteNote(note.id);
    } catch (_) {}
    rethrow;
  }
}

/// A 1ª página do PDF como capa (inteira, sobre fundo papel). `null` se não der.
Future<NotebookCover?> _firstPageCover(WidgetRef ref, String noteId, PickedPdf pdf) async {
  final rasterizer = ref.read(pdfRasterizerProvider);
  if (!rasterizer.supported) return null;
  try {
    final page = await rasterizer.render(pdf.bytes, width: 800, maxPages: 1).first;
    final path = await ref.read(notebookImageStoreFactoryProvider)(noteId).upload(page.bytes, page.ext);
    return NotebookCover(kind: CoverKind.image, imagePath: path, fit: CoverFit.fit, color: kCoverColors.last);
  } catch (_) {
    return null;
  }
}

/// Guarda no caderno [noteId] o PDF original de [pdf] (importado para escrever),
/// para poder lê-lo com o texto de verdade depois. No melhor esforço: se falhar,
/// o caderno fica só com as páginas.
Future<void> storeImportedPdf(WidgetRef ref, String noteId, PickedPdf pdf, int pages) async {
  if (pdf.storedPath != null || pdf.bytes.length > kMaxStoredPdfBytes) return;
  try {
    final path = await ref.read(notebookPdfStoreFactoryProvider)(noteId).uploadPdf(pdf.bytes);
    final note = (ref.read(notesProvider).value ?? const <Note>[]).where((n) => n.id == noteId).firstOrNull;
    if (note == null) return;
    await ref
        .read(repositoryProvider)
        .upsertNote(note.withPdfFile(NotebookPdfFile(path: path, name: pdf.name, pages: pages)));
  } catch (_) {
    // Sem o original, só não dá para selecionar texto.
  }
}
