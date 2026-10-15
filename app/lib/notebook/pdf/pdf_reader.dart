import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Um trecho de texto selecionado no PDF.
class PdfSelection {
  const PdfSelection(this.text, {this.page});

  final String text;

  /// Página (1…) onde a seleção começa, se o leitor souber.
  final int? page;

  bool get isEmpty => text.trim().isEmpty;
}

/// O que a tela de leitura passa ao leitor de PDF.
class PdfViewRequest {
  const PdfViewRequest({
    required this.data,
    required this.sourceName,
    required this.onSelection,
    required this.onCreateNote,
    this.initialPage = 1,
    this.onPage,
  });

  final Uint8List data;

  /// Identifica o arquivo (o mesmo PDF → o mesmo nome).
  final String sourceName;
  final int initialPage;

  /// A seleção mudou (`null` = nada selecionado).
  final ValueChanged<PdfSelection?> onSelection;

  /// "Criar nota" no menu da seleção do próprio leitor.
  final ValueChanged<PdfSelection> onCreateNote;

  /// A página visível mudou: (página, total).
  final void Function(int page, int count)? onPage;
}

/// Monta o leitor de PDF. `null` = sem leitor neste aparelho (testes, web);
/// `main.dart` liga o do pdfrx.
typedef PdfViewBuilder = Widget Function(BuildContext context, PdfViewRequest request);

final pdfViewBuilderProvider = Provider<PdfViewBuilder?>((ref) => null);

/// Onde o leitor parou em cada PDF (para abrir de onde parou, como num livro).
abstract class PdfReadingPositions {
  Future<int?> page(String path);
  Future<void> setPage(String path, int page);
}

class MemoryPdfReadingPositions implements PdfReadingPositions {
  final _pages = <String, int>{};

  @override
  Future<int?> page(String path) async => _pages[path];

  @override
  Future<void> setPage(String path, int page) async => _pages[path] = page;
}

class SharedPreferencesPdfReadingPositions implements PdfReadingPositions {
  const SharedPreferencesPdfReadingPositions();

  static String _key(String path) => 'pdf_page:$path';

  @override
  Future<int?> page(String path) async => (await SharedPreferences.getInstance()).getInt(_key(path));

  @override
  Future<void> setPage(String path, int page) async => (await SharedPreferences.getInstance()).setInt(_key(path), page);
}

final pdfReadingPositionsProvider = Provider<PdfReadingPositions>((ref) => MemoryPdfReadingPositions());
