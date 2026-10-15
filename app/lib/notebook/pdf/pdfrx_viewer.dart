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

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    return FutureBuilder<void>(
      future: _ready,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        return PdfViewer.data(
          r.data,
          sourceName: r.sourceName,
          controller: _controller,
          initialPageNumber: r.initialPage,
          params: PdfViewerParams(
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
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
                    if (!sel.isEmpty) r.onCreateNote(sel);
                  },
                ),
              );
            },
            onPageChanged: (page) {
              if (page != null && _controller.isReady) r.onPage?.call(page, _controller.pageCount);
            },
            onViewerReady: (doc, controller) =>
                r.onPage?.call(controller.pageNumber ?? r.initialPage, doc.pages.length),
            loadingBannerBuilder: (context, bytesDownloaded, totalBytes) =>
                const Center(child: CircularProgressIndicator()),
            errorBannerBuilder: (context, error, stackTrace, documentRef) =>
                const Center(child: Text('Não foi possível abrir o PDF.')),
          ),
        );
      },
    );
  }
}
