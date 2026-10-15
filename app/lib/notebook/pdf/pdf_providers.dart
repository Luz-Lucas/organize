import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pdf_import.dart';
import 'pick_pdf.dart';

/// Leitor de PDF. Padrão: nenhum (testes); `main.dart` liga o `PdfrxRasterizer`.
final pdfRasterizerProvider = Provider<PdfRasterizer>((ref) => const NoopPdfRasterizer());

/// Escolhe um PDF (seletor do sistema). Injetável nos testes.
final pdfPickerProvider = Provider<Future<PickedPdf?> Function()>((ref) => pickPdfFromSystem);
