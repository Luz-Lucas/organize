// Testa o leitor de verdade (pdfrx + PDFium). Precisa da biblioteca nativa do PDFium:
//   PDFIUM_PATH=/caminho/libpdfium.so flutter test test/notebook/pdf/pdfrx_viewer_test.dart
// (https://github.com/bblanchon/pdfium-binaries). Sem ela, o teste é pulado.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/pdf/pdf_reader.dart';
import 'package:organizacional/notebook/pdf/pdfrx_viewer.dart';
import 'package:organizacional/ui/org_theme.dart';
import 'package:pdfrx/pdfrx.dart';

/// Um PDF de uma página com três linhas de texto (Helvetica).
Uint8List _samplePdf() {
  const lines = [
    'Querido Vermebile, compreendo o que voce diz sobre guiar o seu',
    'paciente em suas leituras e tambem fazer de tudo para que',
    'ele sempre tenha encontros com o tal amigo materialista.',
  ];
  final content = 'BT /F1 14 Tf 72 720 Td 18 TL\n${lines.map((l) => '($l) Tj T*').join('\n')}\nET';
  final objs = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  final out = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objs.length; i++) {
    offsets.add(out.length);
    out.write('${i + 1} 0 obj\n${objs[i]}\nendobj\n');
  }
  final xref = out.length;
  out.write('xref\n0 ${objs.length + 1}\n0000000000 65535 f \n');
  for (final o in offsets) {
    out.write('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  out.write('trailer\n<< /Size ${objs.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  return Uint8List.fromList(latin1.encode(out.toString()));
}

void main() {
  final pdfium = Platform.environment['PDFIUM_PATH'];
  final skip = pdfium == null || !File(pdfium).existsSync() ? 'sem PDFIUM_PATH (PDFium nativo)' : null;

  testWidgets(
    'em português, o menu da seleção aparece (sem o bloco cinza) e "Adicionar às notas do caderno" leva o trecho',
    skip: skip != null,
    (tester) async {
      tester.view.physicalSize = const Size(392 * 2.75, 842 * 2.75);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        Pdfrx.pdfiumModulePath = pdfium;
        await pdfrxInitialize(tmpPath: Directory.systemTemp.createTempSync('pdfrx').path);
      });

      Future<void> settle() async {
        for (var i = 0; i < 10; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      final data = _samplePdf();
      final selections = <PdfSelection?>[];
      final notes = <PdfSelection>[];
      var rebuilds = 0;
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('pt', 'BR'),
          supportedLocales: const [Locale('pt', 'BR')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: buildOrgTheme(orgThemes.first, googleFonts: false),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                rebuilds++;
                // Pedido novo (callbacks novos) a cada reconstrução, como na tela de leitura.
                return buildPdfrxView(
                  context,
                  PdfViewRequest(data: data, sourceName: 'teste', onSelection: selections.add, onAddToNotes: notes.add),
                );
              },
            ),
          ),
        ),
      );
      await settle();

      final viewer = tester.state(find.byType(PdfViewer)) as dynamic;
      await tester.runAsync(() async {
        // "leituras", na 2ª linha (coordenadas do documento).
        await (viewer.selectWord(const Offset(200, 100), deviceKind: PointerDeviceKind.touch) as Future);
      });
      await settle();
      expect(selections.last?.text, 'leituras');
      expect(selections.last?.page, 1);

      // Reconstruir a tela (o botão "Adicionar às notas do caderno" aparecendo) não pode recarregar o PDF
      // nem perder a seleção.
      rebuild(() {});
      await settle();
      expect(rebuilds, greaterThan(1));
      expect(viewer.hasSelectedText as bool, isTrue);

      viewer.showContextMenu(const Offset(200, 100), forPart: PdfViewerPart.selectedText);
      await settle();
      expect(find.byType(ErrorWidget), findsNothing);
      expect(find.text('Adicionar às notas do caderno'), findsOneWidget);
      expect(find.text('Copiar'), findsOneWidget);

      await tester.tap(find.text('Adicionar às notas do caderno'));
      await settle();
      expect(notes.single.text, 'leituras');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
