import 'dart:typed_data';

import 'package:flutter/gestures.dart';

import 'package:flutter/material.dart' hide TextBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/core/notebook_core.dart';
import 'package:organizacional/notebook/pdf/pdf_import.dart' show PdfImportException;
import 'package:organizacional/notebook/ui/notebook_screen.dart';
import 'package:organizacional/ui/org_theme.dart';

import '../pdf/pdf_import_test.dart' show FakePdfRasterizer;
import 'menu_support.dart';
import 'ui_support.dart';

final _pdf = PickedPdf(bytes: Uint8List.fromList([37, 80, 68, 70]), name: 'Lista 3.pdf');

Future<void> pumpPdf(
  WidgetTester tester,
  FakeSession session, {
  PdfRasterizer rasterizer = const NoopPdfRasterizer(),
  Future<PickedPdf?> Function()? pickPdf,
  PickedPdf? initialPdf,
}) async {
  await setSurface(tester, const Size(800, 1300));
  await tester.pumpWidget(
    MaterialApp(
      theme: buildOrgTheme(orgThemes.first, googleFonts: false),
      home: NotebookScreen(
        noteId: 'n1',
        session: session,
        title: 'Caderno',
        pdfRasterizer: rasterizer,
        pickPdf: pickPdf,
        initialPdf: initialPdf,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// Abre o menu Ferramentas e rola até [key].
Future<void> tapInToolsMenu(WidgetTester tester, String key) async {
  await openMenu(tester);
  final menu = find.descendant(of: find.byKey(const ValueKey('nb-tools-menu')), matching: find.byType(Scrollable)).first;
  await tester.dragUntilVisible(find.byKey(ValueKey(key)), menu, const Offset(0, -200));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Inserir PDF: cada página vira uma página nova com o PDF de fundo', (tester) async {
    final s = FakeSession();
    final r = FakePdfRasterizer([(2000, 2828), (2000, 1125)]);
    await pumpPdf(tester, s, rasterizer: r, pickPdf: () async => _pdf);
    await tapInToolsMenu(tester, 'nb-insert-pdf');
    await tester.pumpAndSettle();

    expect(s.current, hasLength(3), reason: 'a página em branco que já existia continua');
    expect(s.images.uploads.map((u) => u.ext), ['jpg', 'jpg']);
    for (final p in s.current.skip(1)) {
      expect(p.background, PageBackground.blank);
      final bg = p.doc.images.single;
      expect(bg.background, isTrue);
      expect(bg.path, startsWith('u/n/img-'));
    }
    expect(find.byKey(const ValueKey('nb-pdf-progress')), findsNothing, reason: 'o progresso fecha sozinho');
    expect(find.text('2 páginas do PDF adicionadas.'), findsOneWidget);
  });

  testWidgets('caderno novo a partir de PDF: as páginas do PDF substituem a página em branco', (tester) async {
    final s = FakeSession();
    await pumpPdf(tester, s, rasterizer: FakePdfRasterizer([(2000, 2828), (2000, 2828), (2000, 2828)]), initialPdf: _pdf);
    await tester.pumpAndSettle();
    expect(s.current, hasLength(3));
    expect(s.current.every((p) => p.doc.images.single.background), isTrue);
    expect(find.text('3 páginas do PDF adicionadas.'), findsOneWidget);
  });

  testWidgets('PDF protegido: avisa e não cria página', (tester) async {
    final s = FakeSession();
    final r = FakePdfRasterizer(const [], error: const PdfImportException('Este PDF é protegido por senha.'));
    await pumpPdf(tester, s, rasterizer: r, pickPdf: () async => _pdf);
    await tapInToolsMenu(tester, 'nb-insert-pdf');
    await tester.pumpAndSettle();
    expect(s.current, hasLength(1));
    expect(find.text('Este PDF é protegido por senha.'), findsOneWidget);
  });

  testWidgets('sem leitor de PDF a opção não aparece', (tester) async {
    await pumpPdf(tester, FakeSession());
    await openMenu(tester);
    final menu = find.descendant(of: find.byKey(const ValueKey('nb-tools-menu')), matching: find.byType(Scrollable)).first;
    await tester.dragUntilVisible(find.byKey(const ValueKey('nb-tool-image')), menu, const Offset(0, -200));
    expect(find.byKey(const ValueKey('nb-insert-pdf')), findsNothing);
  });

  testWidgets('escrever por cima do PDF: a borracha de traço não apaga o fundo', (tester) async {
    final bg = const ImageBox(id: 'bg', x: 0, y: 0, w: 1000, h: 1414, path: 'u/n/p.jpg', background: true);
    final s = FakeSession(docs: [PageDoc.empty.withImage(bg)]);
    await pumpPdf(tester, s);
    await SimPointer(tester, PointerDeviceKind.stylus).drag(linePath(const Offset(200, 300), const Offset(500, 300)));
    expect(s.docOf(0).strokes, hasLength(1));
    await tester.tap(find.byKey(const ValueKey('nb-tool-eraser')));
    await tester.pump();
    await SimPointer(tester, PointerDeviceKind.stylus).drag(linePath(const Offset(350, 250), const Offset(350, 350)));
    expect(s.docOf(0).strokes, isEmpty);
    expect(s.docOf(0).images.single.id, 'bg');
  });
}
