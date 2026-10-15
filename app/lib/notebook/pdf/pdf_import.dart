/// PDF no Caderno: cada página do PDF vira uma página do caderno com a página do
/// PDF como **fundo** (um `ImageBox` com `background: true`), onde se escreve por cima.
///
/// A página é renderizada uma vez, na importação, e guardada como imagem no mesmo
/// Storage das imagens do caderno. Assim ela abre e sincroniza em qualquer aparelho
/// (inclusive offline, pelo cache) sem precisar de um leitor de PDF em cada um.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import '../core/notebook_core.dart';

/// Largura, em pixels, da imagem de cada página (≈ 2× a página na tela de um tablet).
const int kPdfRenderWidth = 2000;

/// Máximo de páginas importadas de uma vez (PDFs maiores: avisa e importa as primeiras).
const int kMaxPdfPages = 100;

/// Uma página do PDF já renderizada e codificada (JPEG).
class PdfPageImage {
  const PdfPageImage({required this.bytes, required this.width, required this.height, this.ext = 'jpg'});

  final Uint8List bytes;
  final int width;
  final int height;
  final String ext;
}

/// O PDF não pôde ser aberto (inválido, protegido por senha…). [message] é para o usuário.
class PdfImportException implements Exception {
  const PdfImportException(this.message);
  final String message;

  @override
  String toString() => 'PdfImportException: $message';
}

/// Renderiza as páginas de um PDF em imagens.
abstract class PdfRasterizer {
  const PdfRasterizer();

  /// `false` onde não há leitor de PDF (testes, web): a tela esconde "Inserir PDF".
  bool get supported => true;

  /// Quantas páginas o PDF tem. Lança [PdfImportException] se não abrir.
  Future<int> pageCount(Uint8List pdf);

  /// As páginas, em ordem, até [maxPages]. Lança [PdfImportException] se não abrir.
  Stream<PdfPageImage> render(Uint8List pdf, {int width = kPdfRenderWidth, int maxPages = kMaxPdfPages});
}

/// Sem leitor de PDF.
class NoopPdfRasterizer extends PdfRasterizer {
  const NoopPdfRasterizer();

  @override
  bool get supported => false;

  @override
  Future<int> pageCount(Uint8List pdf) async => throw const PdfImportException('PDF não disponível aqui.');

  @override
  Stream<PdfPageImage> render(Uint8List pdf, {int width = kPdfRenderWidth, int maxPages = kMaxPdfPages}) =>
      Stream.error(const PdfImportException('PDF não disponível aqui.'));
}

/// O documento de uma página nova com a imagem [path] (de [width]×[height] px) de
/// fundo: ocupa a largura toda da página; se for mais alta que a folha, ocupa a
/// altura toda e fica centralizada. Uma página deitada (slide) fica no topo e
/// sobra espaço para anotar embaixo.
PageDoc pdfPageDoc(String path, int width, int height, {String Function() newId = newInkId}) {
  final ratio = height / math.max(width, 1);
  var w = pageWidth, h = pageWidth * ratio, x = 0.0;
  if (h > pageHeight) {
    h = pageHeight;
    w = pageHeight / ratio;
    x = (pageWidth - w) / 2;
  }
  return PageDoc.empty.withImage(ImageBox(id: newId(), x: x, y: 0, w: w, h: h, path: path, background: true));
}

/// Progresso de uma importação: [done] de [total] páginas prontas.
typedef PdfImportProgress = void Function(int done, int total);

/// Importa [pdf]: renderiza cada página, envia a imagem com [upload] e cria a página
/// do caderno com [addPage] (o documento já com o fundo). Devolve quantas páginas
/// criou ([done]) e quantas o PDF tem ([pageCount]; acima de [maxPages] só as
/// primeiras entram). [isCancelled] é consultado entre as páginas: as já criadas ficam.
Future<({int done, int pageCount})> importPdfPages({
  required Uint8List pdf,
  required PdfRasterizer rasterizer,
  required Future<String> Function(Uint8List bytes, String ext) upload,
  required void Function(PageDoc doc) addPage,
  PdfImportProgress? onProgress,
  bool Function()? isCancelled,
  int maxPages = kMaxPdfPages,
}) async {
  final count = await rasterizer.pageCount(pdf);
  final total = math.min(count, maxPages);
  if (total == 0) throw const PdfImportException('O PDF não tem páginas.');
  onProgress?.call(0, total);
  var done = 0;
  await for (final page in rasterizer.render(pdf, maxPages: total)) {
    if (isCancelled?.call() ?? false) break;
    final path = await upload(page.bytes, page.ext);
    addPage(pdfPageDoc(path, page.width, page.height));
    done++;
    onProgress?.call(done, total);
  }
  return (done: done, pageCount: count);
}

/// Título do caderno criado a partir de um arquivo: o nome sem a extensão.
String notebookTitleForPdf(String fileName) {
  var name = fileName.trim();
  final dot = name.lastIndexOf('.');
  if (dot > 0 && name.substring(dot).toLowerCase() == '.pdf') name = name.substring(0, dot);
  name = name.replaceAll(RegExp(r'[_]+'), ' ').trim();
  return name.isEmpty ? 'PDF' : name;
}
