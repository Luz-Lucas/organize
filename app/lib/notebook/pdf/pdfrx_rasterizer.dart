import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart';

import 'pdf_import.dart';

/// Leitor de PDF de verdade (PDFium, via `pdfrx`): Android, Linux e Windows.
class PdfrxRasterizer extends PdfRasterizer {
  const PdfrxRasterizer();

  Future<PdfDocument> _open(Uint8List pdf) async {
    await pdfrxFlutterInitialize();
    try {
      return await PdfDocument.openData(pdf, sourceName: 'caderno-${pdf.length}-${pdf.hashCode}');
    } on PdfPasswordException {
      throw const PdfImportException('Este PDF é protegido por senha.');
    } catch (_) {
      throw const PdfImportException('Não foi possível abrir o PDF.');
    }
  }

  @override
  Future<int> pageCount(Uint8List pdf) async {
    final doc = await _open(pdf);
    try {
      return doc.pages.length;
    } finally {
      await doc.dispose();
    }
  }

  @override
  Stream<PdfPageImage> render(Uint8List pdf, {int width = kPdfRenderWidth, int maxPages = kMaxPdfPages}) async* {
    final doc = await _open(pdf);
    try {
      for (final page in doc.pages.take(maxPages)) {
        final w = width.toDouble();
        final h = (w * page.height / (page.width <= 0 ? 1 : page.width)).roundToDouble();
        // Fundo branco: PDFs com fundo transparente ficariam pretos no JPEG.
        final image = await page.render(fullWidth: w, fullHeight: h, backgroundColor: 0xFFFFFFFF);
        if (image == null) continue;
        final pw = image.width, ph = image.height;
        final pixels = Uint8List.fromList(image.pixels);
        image.dispose();
        // Codificar o JPEG é pesado: fora da tela.
        final jpg = await Isolate.run(() => _encodeJpg(pixels, pw, ph));
        yield PdfPageImage(bytes: jpg, width: pw, height: ph);
      }
    } finally {
      await doc.dispose();
    }
  }
}

Uint8List _encodeJpg(Uint8List bgra, int width, int height) {
  final image = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: bgra.buffer,
    numChannels: 4,
    order: img.ChannelOrder.bgra,
  );
  return img.encodeJpg(image, quality: 85);
}
