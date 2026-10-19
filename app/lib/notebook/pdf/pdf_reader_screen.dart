import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/repository.dart';
import '../../domain/note.dart';
import '../../domain/notebook_linked_note.dart';
import '../../domain/notebook_pdf.dart';
import '../../ui/common.dart';
import '../linked_notes_ui.dart';
import 'notebook_pdf_store.dart';
import 'pdf_reader.dart';
import 'pick_pdf.dart';

/// Lê o PDF original de um caderno, como um livro: abre na página onde parou e
/// deixa selecionar texto para mandar às notas do caderno.
///
/// [book]: o caderno é um livro (só leitura) e esta é a tela dele; aparece
/// "Escrever neste PDF", que o transforma em caderno de escrever.
class PdfReaderScreen extends ConsumerStatefulWidget {
  const PdfReaderScreen({super.key, required this.noteId, this.book = false});

  final String noteId;
  final bool book;

  @override
  ConsumerState<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends ConsumerState<PdfReaderScreen> {
  int _fileIndex = 0;
  String? _loadedPath;
  Future<({Uint8List bytes, int page})>? _load;
  PdfSelection? _selection;
  int _page = 0, _count = 0;

  Note? get _note => (ref.read(notesProvider).value ?? const <Note>[]).where((n) => n.id == widget.noteId).firstOrNull;

  void _ensureLoad(NotebookPdfFile file) {
    if (_loadedPath == file.path && _load != null) return;
    _loadedPath = file.path;
    _selection = null;
    _page = 0;
    _count = file.pages;
    _load = () async {
      final bytes = await ref.read(notebookPdfStoreFactoryProvider)(widget.noteId).downloadPdf(file.path);
      final page = await ref.read(pdfReadingPositionsProvider).page(file.path).catchError((Object _) => null);
      return (bytes: bytes, page: page ?? 1);
    }();
  }

  void _retry() => setState(() => _load = null);

  /// Muda o estado fora de uma fase de build/layout: o leitor avisa de página e
  /// seleção enquanto se desenha, e um setState ali quebraria a tela.
  void _update(VoidCallback change) {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(change);
      });
    } else {
      setState(change);
    }
  }

  void _onPage(String path, int page, int count) {
    if (!mounted || (page == _page && count == _count)) return;
    _update(() {
      _page = page;
      _count = count;
    });
    unawaited(ref.read(pdfReadingPositionsProvider).setPage(path, page).catchError((Object _) {}));
  }

  void _onSelection(PdfSelection? s) {
    if (!mounted) return;
    final next = s == null || s.isEmpty ? null : s;
    // Arrastando a seleção chegam muitas: só redesenha quando o botão aparece ou some.
    if ((next == null) == (_selection == null)) {
      _selection = next;
      return;
    }
    _update(() => _selection = next);
  }

  /// Acrescenta o trecho (com as linhas juntas) às notas do caderno, como citação
  /// com a fonte "p. N · dd/MM". Entra direto, sem caixa de edição.
  Future<void> _addToNotes(PdfSelection sel, String bookTitle) async {
    final block = pdfQuoteBlock(cleanPdfText(sel.text), sel.page, ref.read(clockProvider)());
    final ok = await addToNotebookNotes(
      context,
      ref,
      notebookId: widget.noteId,
      notebookTitle: bookTitle,
      block: block,
    );
    if (ok && mounted) setState(() => _selection = null);
  }

  /// Livro → caderno de escrever: as páginas do PDF entram no caderno (com o PDF
  /// de fundo); o original continua guardado para ler e selecionar texto.
  Future<void> _annotate(NotebookPdfFile file, Uint8List bytes) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Escrever neste PDF?'),
        content: const Text(
          'As páginas do PDF viram páginas do caderno, para escrever por cima. '
          'O PDF original continua aqui para ler e selecionar texto.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          FilledButton(
            key: const Key('pdf-annotate-ok'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Escrever'),
          ),
        ],
      ),
    );
    final note = _note;
    if (ok != true || note == null || !mounted) return;
    try {
      await ref.read(repositoryProvider).upsertNote(note.withPdfBook(false));
    } on RepositoryException {
      if (mounted) showError(context, 'Não foi possível mudar o caderno.');
      return;
    }
    if (!mounted) return;
    context.pushReplacement(
      '/caderno/${widget.noteId}',
      extra: PickedPdf(bytes: bytes, name: file.name, storedPath: file.path),
    );
  }

  @override
  Widget build(BuildContext context) {
    final note = ref.watch(notesProvider.select((a) => a.value?.where((n) => n.id == widget.noteId).firstOrNull));
    final files = note?.pdfInfo?.files ?? const <NotebookPdfFile>[];
    if (note == null || files.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Este caderno não tem PDF.')),
      );
    }
    final index = _fileIndex.clamp(0, files.length - 1);
    final file = files[index];
    _ensureLoad(file);
    final viewBuilder = ref.watch(pdfViewBuilderProvider);
    final theme = Theme.of(context);
    final subtitle = [
      if (files.length > 1) file.name,
      if (_page > 0) _count > 0 ? 'p. $_page de $_count' : 'p. $_page',
    ].join(' · ');
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(note.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (subtitle.isNotEmpty)
              Text(
                subtitle,
                key: const Key('pdf-page-label'),
                style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
          ],
        ),
        actions: [
          IconButton(
            key: const Key('pdf-open-notes'),
            tooltip: 'Notas',
            icon: const Icon(Icons.sticky_note_2_outlined),
            onPressed: () => unawaited(openNotebookNotes(context, ref, widget.noteId)),
          ),
          if (files.length > 1)
            PopupMenuButton<int>(
              key: const Key('pdf-files'),
              tooltip: 'Escolher PDF',
              icon: const Icon(Icons.library_books_outlined),
              initialValue: index,
              onSelected: (i) => setState(() => _fileIndex = i),
              itemBuilder: (_) => [
                for (var i = 0; i < files.length; i++)
                  PopupMenuItem(
                    value: i,
                    child: Text(files[i].name, overflow: TextOverflow.ellipsis),
                  ),
              ],
            ),
          if (widget.book)
            FutureBuilder<({Uint8List bytes, int page})>(
              future: _load,
              builder: (context, snap) => IconButton(
                key: const Key('pdf-annotate'),
                tooltip: 'Escrever neste PDF',
                icon: const Icon(Icons.edit_note),
                onPressed: snap.hasData ? () => unawaited(_annotate(file, snap.data!.bytes)) : null,
              ),
            ),
        ],
      ),
      floatingActionButton: _selection == null
          ? null
          : FloatingActionButton.extended(
              key: const Key('pdf-add-note'),
              onPressed: () => unawaited(_addToNotes(_selection!, note.title)),
              icon: const Icon(Icons.note_add_outlined),
              label: const Text('Adicionar às notas do caderno'),
            ),
      body: viewBuilder == null
          ? const Center(child: Text('Não há leitor de PDF neste aparelho.'))
          : FutureBuilder<({Uint8List bytes, int page})>(
              future: _load,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          snap.error is RepositoryException
                              ? 'Não foi possível baixar o PDF. Confira a internet.'
                              : 'Não foi possível abrir o PDF.',
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          key: const Key('pdf-retry'),
                          onPressed: _retry,
                          child: const Text('Tentar de novo'),
                        ),
                      ],
                    ),
                  );
                }
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final data = snap.data!;
                return KeyedSubtree(
                  key: ValueKey(file.path),
                  child: viewBuilder(
                    context,
                    PdfViewRequest(
                      data: data.bytes,
                      sourceName: 'caderno-pdf:${file.path}',
                      initialPage: data.page,
                      onSelection: _onSelection,
                      onAddToNotes: (s) => unawaited(_addToNotes(s, note.title)),
                      onPage: (page, count) => _onPage(file.path, page, count),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// Texto copiado do PDF arrumado para a nota: junta as linhas quebradas no meio da
/// frase (e as palavras hifenizadas no fim da linha), mantendo os parágrafos.
String cleanPdfText(String raw) {
  final text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
  final paragraphs = text.split(RegExp(r'\n\s*\n'));
  return paragraphs
      .map(
        (p) => p
            .replaceAllMapped(RegExp(r'(\p{L})-\n(\p{Ll})', unicode: true), (m) => '${m[1]}${m[2]}')
            .replaceAll(RegExp(r'[ \t]*\n[ \t]*'), ' ')
            .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
            .trim(),
      )
      .where((p) => p.isNotEmpty)
      .join('\n\n');
}
