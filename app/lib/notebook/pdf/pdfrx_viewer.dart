import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'pdf_reader.dart';

/// Leitor de PDF de verdade (PDFium, via `pdfrx`), com seleção de texto.
Widget buildPdfrxView(BuildContext context, PdfViewRequest request) => _PdfrxView(request: request);

class _PdfrxView extends StatefulWidget {
  const _PdfrxView({required this.request});

  final PdfViewRequest request;

  @override
  State<_PdfrxView> createState() => _PdfrxViewState();
}

class _PdfrxViewState extends State<_PdfrxView> {
  late final Future<void> _ready = pdfrxFlutterInitialize();
  final _controller = PdfViewerController();
  int _selectionSeq = 0;

  static Future<PdfSelection> _selectionOf(PdfTextSelection s) async {
    final ranges = await s.getSelectedTextRanges();
    final text = ranges.map((r) => r.text).join();
    return PdfSelection(text, page: ranges.isEmpty ? null : ranges.first.pageNumber);
  }

  Future<void> _selectionChanged(PdfTextSelection s) async {
    final seq = ++_selectionSeq;
    if (!s.hasSelectedText) {
      widget.request.onSelection(null);
      return;
    }
    final sel = await _selectionOf(s);
    // Arrastando a seleção chegam várias; vale só a última.
    if (seq == _selectionSeq && mounted) widget.request.onSelection(sel.isEmpty ? null : sel);
  }

  /// Os parâmetros do leitor, criados uma vez só. O pdfrx compara os parâmetros a
  /// cada reconstrução e **recarrega o documento** se mudaram (callbacks novos
  /// contam como mudança): a tela piscava em cinza e a seleção se perdia no meio
  /// do arraste, porque a seleção reconstrói a tela (o botão "Criar nota").
  /// Por isso os callbacks leem `widget.request` na hora, em vez de capturá-lo.
  PdfViewerParams? _params;
  Color? _paramsBackground;

  PdfViewerParams _paramsFor(Color background) {
    final cached = _params;
    if (cached != null && _paramsBackground == background) return cached;
    _paramsBackground = background;
    return _params = PdfViewerParams(
      backgroundColor: background,
      textSelectionParams: PdfTextSelectionParams(onTextSelectionChange: (s) => unawaited(_selectionChanged(s))),
      customizeContextMenuItems: (params, items) {
        if (!params.textSelectionDelegate.hasSelectedText) return;
        items.insert(
          0,
          ContextMenuButtonItem(
            label: 'Criar nota',
            onPressed: () async {
              final sel = await _selectionOf(params.textSelectionDelegate);
              params.dismissContextMenu();
              if (!sel.isEmpty && mounted) widget.request.onCreateNote(sel);
            },
          ),
        );
      },
      onPageChanged: (page) {
        if (page != null && _controller.isReady && mounted) widget.request.onPage?.call(page, _controller.pageCount);
      },
      onViewerReady: (doc, controller) {
        if (mounted) widget.request.onPage?.call(controller.pageNumber ?? widget.request.initialPage, doc.pages.length);
      },
      loadingBannerBuilder: (context, bytesDownloaded, totalBytes) => const Center(child: CircularProgressIndicator()),
      errorBannerBuilder: (context, error, stackTrace, documentRef) =>
          const Center(child: Text('Não foi possível abrir o PDF.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final background = Theme.of(context).colorScheme.surfaceContainerHighest;
    return FutureBuilder<void>(
      future: _ready,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        return PdfViewer.data(
          r.data,
          sourceName: r.sourceName,
          controller: _controller,
          initialPageNumber: r.initialPage,
          params: _paramsFor(background),
        );
      },
    );
  }
}
