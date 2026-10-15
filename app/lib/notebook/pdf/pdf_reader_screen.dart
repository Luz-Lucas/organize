import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/repository.dart';
import '../../domain/ids.dart';
import '../../domain/note.dart';
import '../../domain/notebook_pdf.dart';
import '../../domain/wikilinks.dart';
import '../../ui/common.dart';
import 'notebook_pdf_store.dart';
import 'pdf_reader.dart';
import 'pick_pdf.dart';

/// Lê o PDF original de um caderno, como um livro: abre na página onde parou e
/// deixa selecionar texto para virar uma nota.
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

  void _onPage(String path, int page, int count) {
    if (!mounted || (page == _page && count == _count)) return;
    setState(() {
      _page = page;
      _count = count;
    });
    unawaited(ref.read(pdfReadingPositionsProvider).setPage(path, page).catchError((Object _) {}));
  }

  void _onSelection(PdfSelection? s) {
    if (!mounted) return;
    setState(() => _selection = s == null || s.isEmpty ? null : s);
  }

  Future<void> _createNote(PdfSelection sel, String bookTitle) async {
    final page = sel.page;
    final draft = await showDialog<({String title, String body})>(
      context: context,
      builder: (_) =>
          _NoteFromPdfDialog(text: cleanPdfText(sel.text), title: page == null ? bookTitle : '$bookTitle — p. $page'),
    );
    if (draft == null || !mounted) return;
    final notes = ref.read(notesProvider).value ?? const <Note>[];
    final source = page == null ? bookTitle : '$bookTitle, p. $page';
    final note = Note(
      id: newId(),
      title: uniqueTitle(draft.title.isEmpty ? bookTitle : draft.title, notes),
      body: '${draft.body.trim()}\n\n_Fonte: ${source}_',
      spaceId: _note?.spaceId,
    );
    try {
      await ref.read(repositoryProvider).upsertNote(note);
    } on RepositoryException {
      if (mounted) showError(context, 'Não foi possível criar a nota.');
      return;
    }
    if (!mounted) return;
    setState(() => _selection = null);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Nota “${note.title}” criada.'),
          action: SnackBarAction(label: 'Abrir', onPressed: () => context.push('/nota/${note.id}')),
        ),
      );
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
              key: const Key('pdf-create-note'),
              onPressed: () => unawaited(_createNote(_selection!, note.title)),
              icon: const Icon(Icons.note_add_outlined),
              label: const Text('Criar nota'),
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
                      onCreateNote: (s) => unawaited(_createNote(s, note.title)),
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

class _NoteFromPdfDialog extends StatefulWidget {
  const _NoteFromPdfDialog({required this.text, required this.title});

  final String text;
  final String title;

  @override
  State<_NoteFromPdfDialog> createState() => _NoteFromPdfDialogState();
}

class _NoteFromPdfDialogState extends State<_NoteFromPdfDialog> {
  late final _title = TextEditingController(text: widget.title);
  late final _body = TextEditingController(text: widget.text);

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nova nota com o trecho'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('pdf-note-title'),
              controller: _title,
              decoration: const InputDecoration(labelText: 'Título'),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('pdf-note-body'),
              controller: _body,
              minLines: 4,
              maxLines: 12,
              decoration: const InputDecoration(labelText: 'Texto', alignLabelWithHint: true),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
      FilledButton(
        key: const Key('pdf-note-ok'),
        onPressed: () => Navigator.of(context).pop((title: _title.text.trim(), body: _body.text)),
        child: const Text('Criar nota'),
      ),
    ],
  );
}
