import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/core/notebook_core.dart';
import 'package:organizacional/notebook/pdf/pdf_import.dart';

/// Leitor falso: [sizes] são as páginas (largura × altura em px).
class FakePdfRasterizer extends PdfRasterizer {
  FakePdfRasterizer(this.sizes, {this.error});
  final List<(int, int)> sizes;
  final PdfImportException? error;
  int rendered = 0;

  @override
  Future<int> pageCount(Uint8List pdf) async {
    if (error != null) throw error!;
    return sizes.length;
  }

  @override
  Stream<PdfPageImage> render(Uint8List pdf, {int width = kPdfRenderWidth, int maxPages = kMaxPdfPages}) async* {
    for (final (w, h) in sizes.take(maxPages)) {
      rendered++;
      yield PdfPageImage(bytes: Uint8List.fromList([rendered]), width: w, height: h);
    }
  }
}

void main() {
  final pdf = Uint8List.fromList([1, 2, 3]);

  group('pdfPageDoc: a página do PDF de fundo', () {
    test('A4 em pé ocupa a página toda', () {
      final doc = pdfPageDoc('u/n/a.jpg', 2000, 2828);
      final bg = doc.images.single;
      expect(bg.background, isTrue);
      expect(bg.path, 'u/n/a.jpg');
      expect(bg.bounds.left, 0);
      expect(bg.bounds.top, 0);
      expect(bg.w, pageWidth);
      expect(bg.h, closeTo(pageHeight, 1));
    });

    test('página deitada (slide) fica no topo, com espaço para anotar embaixo', () {
      final bg = pdfPageDoc('s.jpg', 2000, 1125).images.single;
      expect(bg.w, pageWidth);
      expect(bg.h, closeTo(562.5, 0.1));
      expect(bg.y, 0);
    });

    test('página mais alta que a folha ocupa a altura e fica centralizada', () {
      final bg = pdfPageDoc('t.jpg', 1000, 3000).images.single;
      expect(bg.h, pageHeight);
      expect(bg.w, closeTo(pageHeight / 3, 0.1));
      expect(bg.x + bg.w / 2, closeTo(pageWidth / 2, 0.1));
    });
  });

  group('importPdfPages', () {
    test('cria uma página por página do PDF, envia as imagens e informa o progresso', () async {
      final r = FakePdfRasterizer([(2000, 2828), (2000, 1125), (2000, 2828)]);
      final uploads = <String>[];
      final docs = <PageDoc>[];
      final progress = <(int, int)>[];
      final res = await importPdfPages(
        pdf: pdf,
        rasterizer: r,
        upload: (bytes, ext) async {
          uploads.add('p${bytes.single}.$ext');
          return 'u/n/p${bytes.single}.$ext';
        },
        addPage: docs.add,
        onProgress: (d, t) => progress.add((d, t)),
      );
      expect(res.done, 3);
      expect(res.pageCount, 3);
      expect(uploads, ['p1.jpg', 'p2.jpg', 'p3.jpg']);
      expect(docs.map((d) => d.images.single.path), ['u/n/p1.jpg', 'u/n/p2.jpg', 'u/n/p3.jpg']);
      expect(docs.every((d) => d.images.single.background && d.strokes.isEmpty), isTrue);
      expect(progress, [(0, 3), (1, 3), (2, 3), (3, 3)]);
    });

    test('acima do limite importa só as primeiras e conta o total', () async {
      final r = FakePdfRasterizer(List.filled(5, (100, 141)));
      final docs = <PageDoc>[];
      final res = await importPdfPages(
        pdf: pdf,
        rasterizer: r,
        upload: (b, e) async => 'x',
        addPage: docs.add,
        maxPages: 2,
      );
      expect(res.done, 2);
      expect(res.pageCount, 5);
      expect(r.rendered, 2);
    });

    test('parar no meio mantém as páginas já criadas', () async {
      final r = FakePdfRasterizer(List.filled(4, (100, 141)));
      final docs = <PageDoc>[];
      final res = await importPdfPages(
        pdf: pdf,
        rasterizer: r,
        upload: (b, e) async => 'x',
        addPage: docs.add,
        isCancelled: () => docs.length >= 2,
      );
      expect(res.done, 2);
      expect(docs, hasLength(2));
    });

    test('PDF protegido ou vazio vira erro com mensagem para o usuário', () async {
      await expectLater(
        importPdfPages(
          pdf: pdf,
          rasterizer: FakePdfRasterizer(const [], error: const PdfImportException('Este PDF é protegido por senha.')),
          upload: (b, e) async => 'x',
          addPage: (_) {},
        ),
        throwsA(isA<PdfImportException>().having((e) => e.message, 'message', contains('senha'))),
      );
      await expectLater(
        importPdfPages(pdf: pdf, rasterizer: FakePdfRasterizer(const []), upload: (b, e) async => 'x', addPage: (_) {}),
        throwsA(isA<PdfImportException>()),
      );
    });

    test('sem leitor de PDF (Noop) não é suportado', () {
      expect(const NoopPdfRasterizer().supported, isFalse);
    });
  });

  test('notebookTitleForPdf: nome do arquivo sem a extensão', () {
    expect(notebookTitleForPdf('Lista_3_Calculo.pdf'), 'Lista 3 Calculo');
    expect(notebookTitleForPdf('Apostila.PDF'), 'Apostila');
    expect(notebookTitleForPdf('.pdf'), '.pdf');
    expect(notebookTitleForPdf('  '), 'PDF');
  });

  group('fundo de PDF no núcleo', () {
    const bg = ImageBox(id: 'bg1', x: 0, y: 0, w: 1000, h: 1414, path: 'u/n/p.jpg', background: true);
    const pic = ImageBox(id: 'im1', x: 100, y: 100, w: 200, h: 200, path: 'u/n/i.png');

    test('codec: grava "bg" só quando é fundo e volta igual; página antiga lê como imagem comum', () {
      final doc = PageDoc.empty.withImage(bg).withImage(pic);
      final back = decodePage(encodePage(doc));
      expect(back, doc);
      expect(back.imageById('bg1')!.background, isTrue);
      expect(back.imageById('im1')!.background, isFalse);
      expect(pageJson(doc), contains('"bg":true'));
      expect(pageJson(PageDoc.empty.withImage(pic)), isNot(contains('"bg"')));
    });

    test('o laço e a borracha de itens não pegam o fundo', () {
      final doc = PageDoc.empty.withImage(bg).withImage(pic);
      final all = [const Offset(-10, -10), const Offset(1010, -10), const Offset(1010, 1424), const Offset(-10, 1424)];
      expect(lassoSelect(doc, all), {'im1'});
      expect(hitItems(doc, const Offset(500, 900), 5), isEmpty);
      expect(hitItems(doc, const Offset(200, 200), 5), ['im1']);
    });
  });
}
