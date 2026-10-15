import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/note.dart';
import 'package:organizacional/domain/notebook_pdf.dart';
import 'package:organizacional/features/notes/notebooks/notebooks_prefs.dart';
import 'package:organizacional/notebook/data/memory_notebook_repository.dart';
import 'package:organizacional/notebook/pdf/notebook_pdf_store.dart';
import 'package:organizacional/notebook/pdf/pdf_import.dart' show PdfImportException;
import 'package:organizacional/notebook/pdf/pdf_providers.dart';
import 'package:organizacional/notebook/pdf/pdf_reader.dart';
import 'package:organizacional/notebook/pdf/pick_pdf.dart';
import 'package:organizacional/domain/notebook_cover.dart';

import '../data/fake_image_store.dart';

import '../../helpers.dart';
import 'pdf_import_test.dart' show FakePdfRasterizer;

Finder _key(String k) => find.byKey(Key(k));

/// Leitor falso: mostra o tamanho do PDF e a página inicial; botões simulam a
/// seleção, o "Criar nota" do menu do leitor e a troca de página.
Widget fakePdfView(BuildContext context, PdfViewRequest r) => Column(
  children: [
    Text('PDF ${r.data.length} bytes, abriu na p. ${r.initialPage}', key: const Key('fake-pdf')),
    TextButton(
      key: const Key('fake-select'),
      onPressed: () => r.onSelection(const PdfSelection('O limite\nde f(x)', page: 3)),
      child: const Text('selecionar'),
    ),
    TextButton(key: const Key('fake-unselect'), onPressed: () => r.onSelection(null), child: const Text('limpar')),
    TextButton(
      key: const Key('fake-menu-note'),
      onPressed: () => r.onCreateNote(const PdfSelection('Teorema do valor médio', page: 7)),
      child: const Text('menu'),
    ),
    TextButton(key: const Key('fake-page'), onPressed: () => r.onPage?.call(5, 10), child: const Text('página')),
  ],
);

void main() {
  late MemoryRepository repo;
  late MemoryNotebookRepository nb;
  late Map<String, Uint8List> pdfs;
  late MemoryPdfReadingPositions positions;
  final pdfBytes = Uint8List.fromList(List.filled(42, 1));

  const file = NotebookPdfFile(path: 'u/c1/0.pdf', name: 'Cálculo.pdf', pages: 10);

  setUp(() async {
    repo = MemoryRepository();
    nb = MemoryNotebookRepository();
    pdfs = {file.path: pdfBytes};
    positions = MemoryPdfReadingPositions();
    await repo.upsertNote(
      const Note(id: 'c1', title: 'Cálculo', kind: NoteKind.notebook, spaceId: 's1').withPdfFile(file, book: true),
    );
  });

  Future<void> open(WidgetTester tester, {String location = '/caderno/c1', bool viewer = true}) async {
    await pumpApp(
      tester,
      repo,
      notebookRepo: nb,
      size: const Size(400, 800),
      location: location,
      overrides: [
        notesTabPrefsProvider.overrideWithValue(MemoryNotesTabPrefs()),
        notebookPdfStoreFactoryProvider.overrideWithValue((id) => MemoryNotebookPdfStore(id, pdfs)),
        pdfReadingPositionsProvider.overrideWithValue(positions),
        if (viewer) pdfViewBuilderProvider.overrideWithValue(fakePdfView),
        pdfRasterizerProvider.overrideWithValue(FakePdfRasterizer([(2000, 2828), (2000, 2828)])),
      ],
    );
    await tester.pumpAndSettle();
  }

  Future<List<Note>> notes() => repo.watchNotes().first;

  testWidgets('o caderno-livro abre direto no PDF', (tester) async {
    await open(tester);
    expect(find.text('PDF 42 bytes, abriu na p. 1'), findsOneWidget);
    expect(_key('notebook-screen'), findsNothing);
    expect(_key('pdf-annotate'), findsOneWidget);
  });

  testWidgets('lembra a página onde parou', (tester) async {
    await open(tester);
    await tester.tap(_key('fake-page'));
    await tester.pump();
    expect(find.text('p. 5 de 10'), findsOneWidget);
    expect(await positions.page(file.path), 5);

    await open(tester, location: '/notas');
    await open(tester);
    expect(find.text('PDF 42 bytes, abriu na p. 5'), findsOneWidget);
  });

  testWidgets('selecionar texto mostra "Criar nota", que cria a nota com a fonte', (tester) async {
    await open(tester);
    expect(_key('pdf-create-note'), findsNothing);
    await tester.tap(_key('fake-select'));
    await tester.pumpAndSettle();
    await tester.tap(_key('pdf-create-note'));
    await tester.pumpAndSettle();
    // Título sugerido e texto já com as linhas juntas.
    expect(find.descendant(of: _key('pdf-note-title'), matching: find.text('Cálculo — p. 3')), findsOneWidget);
    expect(find.descendant(of: _key('pdf-note-body'), matching: find.text('O limite de f(x)')), findsOneWidget);
    await tester.enterText(_key('pdf-note-title'), 'Limites');
    await tester.tap(_key('pdf-note-ok'));
    await tester.pumpAndSettle();

    final created = (await notes()).firstWhere((n) => n.title == 'Limites');
    expect(created.isNotebook, isFalse);
    expect(created.body, 'O limite de f(x)\n\n_Fonte: Cálculo, p. 3_');
    expect(created.spaceId, 's1', reason: 'na mesma pasta do caderno');
    expect(find.text('Nota “Limites” criada.'), findsOneWidget);
    expect(_key('pdf-create-note'), findsNothing, reason: 'a seleção já virou nota');
  });

  testWidgets('"Criar nota" do menu do leitor também cria', (tester) async {
    await open(tester);
    await tester.tap(_key('fake-menu-note'));
    await tester.pumpAndSettle();
    await tester.tap(_key('pdf-note-ok'));
    await tester.pumpAndSettle();
    final created = (await notes()).firstWhere((n) => n.title == 'Cálculo — p. 7');
    expect(created.body, startsWith('Teorema do valor médio'));
  });

  testWidgets('desfazer a seleção esconde o botão; cancelar não cria nada', (tester) async {
    await open(tester);
    await tester.tap(_key('fake-select'));
    await tester.pumpAndSettle();
    expect(_key('pdf-create-note'), findsOneWidget);
    await tester.tap(_key('fake-unselect'));
    await tester.pumpAndSettle();
    expect(_key('pdf-create-note'), findsNothing);
    await tester.tap(_key('fake-menu-note'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(await notes(), hasLength(1));
  });

  testWidgets('sem leitor de PDF no aparelho, avisa', (tester) async {
    await open(tester, viewer: false);
    expect(find.text('Não há leitor de PDF neste aparelho.'), findsOneWidget);
  });

  testWidgets('PDF que não baixa: avisa e tenta de novo', (tester) async {
    pdfs.clear();
    await open(tester);
    expect(_key('pdf-retry'), findsOneWidget);
    pdfs[file.path] = pdfBytes;
    await tester.tap(_key('pdf-retry'));
    await tester.pumpAndSettle();
    expect(find.text('PDF 42 bytes, abriu na p. 1'), findsOneWidget);
  });

  testWidgets('"Escrever neste PDF" vira caderno com as páginas, sem enviar o PDF de novo', (tester) async {
    await open(tester);
    await tester.tap(_key('pdf-annotate'));
    await tester.pumpAndSettle();
    await tester.tap(_key('pdf-annotate-ok'));
    await tester.pumpAndSettle();
    expect(_key('notebook-screen'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(await nb.listPages('c1'), hasLength(2));
    final note = (await notes()).single;
    expect(note.isPdfBook, isFalse);
    expect(note.pdfInfo!.files, [file], reason: 'o mesmo PDF, sem cópia');
    expect(pdfs, hasLength(1));

    // No caderno, o botão de ler o PDF original abre o leitor.
    await tester.tap(_key('nb-open-pdf'));
    await tester.pumpAndSettle();
    expect(_key('fake-pdf'), findsOneWidget);
    expect(_key('pdf-annotate'), findsNothing);
  });

  testWidgets('vários PDFs no caderno: escolhe qual ler', (tester) async {
    const second = NotebookPdfFile(path: 'u/c1/1.pdf', name: 'Lista.pdf');
    pdfs[second.path] = Uint8List(7);
    final n = (await notes()).single;
    await repo.upsertNote(n.withPdfFile(second));
    await open(tester);
    await tester.tap(_key('pdf-files'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lista.pdf').last);
    await tester.pumpAndSettle();
    expect(find.text('PDF 7 bytes, abriu na p. 1'), findsOneWidget);
  });

  group('importar PDF', () {
    late FakeNotebookImageStore images;
    final picked = PickedPdf(bytes: Uint8List.fromList([9, 9, 9]), name: 'Apostila_Física.pdf');

    Future<void> openNotebooks(WidgetTester tester, {bool viewer = true}) async {
      images = FakeNotebookImageStore();
      await pumpApp(
        tester,
        repo,
        notebookRepo: nb,
        notebookImages: (_) => images,
        size: const Size(400, 800),
        location: '/notas',
        overrides: [
          notesTabPrefsProvider.overrideWithValue(MemoryNotesTabPrefs()),
          notebookPdfStoreFactoryProvider.overrideWithValue((id) => MemoryNotebookPdfStore(id, pdfs)),
          pdfReadingPositionsProvider.overrideWithValue(positions),
          if (viewer) pdfViewBuilderProvider.overrideWithValue(fakePdfView),
          pdfRasterizerProvider.overrideWithValue(FakePdfRasterizer([(2000, 2828), (2000, 2828), (2000, 2828)])),
          pdfPickerProvider.overrideWithValue(() async => picked),
        ],
      );
      await tester.tap(_key('notes-tab-notebooks'));
      await tester.pumpAndSettle();
      await tester.tap(_key('new-notebook-pdf'));
      await tester.pumpAndSettle();
    }

    Future<Note> created() async => (await notes()).firstWhere((n) => n.title == 'Apostila Física');

    testWidgets('"Só ler": livro com o PDF original e a 1ª página de capa', (tester) async {
      pdfs.clear();
      await openNotebooks(tester);
      await tester.tap(_key('pdf-mode-read'));
      await tester.pumpAndSettle();

      final book = await created();
      expect(book.isPdfBook, isTrue);
      final f = book.pdfInfo!.files.single;
      expect(f.name, 'Apostila_Física.pdf');
      expect(f.pages, 3);
      expect(pdfs[f.path], picked.bytes);
      expect(book.cover?.kind, CoverKind.image);
      expect(book.cover?.fit, CoverFit.fit);
      expect(images.uploads.keys, [book.cover?.imagePath]);
      // Já abriu no leitor.
      expect(find.text('PDF 3 bytes, abriu na p. 1'), findsOneWidget);
    });

    testWidgets('"Para escrever": páginas no caderno e o original guardado para ler', (tester) async {
      pdfs.clear();
      await openNotebooks(tester);
      await tester.tap(_key('pdf-mode-write'));
      await tester.pumpAndSettle();
      expect(_key('notebook-screen'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      final note = await created();
      expect(await nb.listPages(note.id), hasLength(3));
      expect(note.isPdfBook, isFalse);
      expect(note.pdfInfo!.files.single.pages, 3);
      expect(pdfs.values.single, picked.bytes);
      await tester.tap(_key('nb-open-pdf'));
      await tester.pumpAndSettle();
      expect(find.text('PDF 3 bytes, abriu na p. 1'), findsOneWidget);
    });

    testWidgets('fechar a pergunta não cria nada', (tester) async {
      await openNotebooks(tester);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect((await notes()).where((n) => n.title == 'Apostila Física'), isEmpty);
    });

    testWidgets('sem leitor de PDF, nem pergunta: é para escrever', (tester) async {
      await openNotebooks(tester, viewer: false);
      expect(_key('pdf-mode-read'), findsNothing);
      expect(_key('notebook-screen'), findsOneWidget);
    });

    testWidgets('PDF que não abre: avisa e não cria o livro', (tester) async {
      images = FakeNotebookImageStore();
      await pumpApp(
        tester,
        repo,
        notebookRepo: nb,
        size: const Size(400, 800),
        location: '/notas',
        overrides: [
          notesTabPrefsProvider.overrideWithValue(MemoryNotesTabPrefs()),
          notebookPdfStoreFactoryProvider.overrideWithValue((id) => MemoryNotebookPdfStore(id, pdfs)),
          pdfViewBuilderProvider.overrideWithValue(fakePdfView),
          pdfRasterizerProvider.overrideWithValue(
            FakePdfRasterizer(const [], error: const PdfImportException('Este PDF é protegido por senha.')),
          ),
          pdfPickerProvider.overrideWithValue(() async => picked),
        ],
      );
      await tester.tap(_key('notes-tab-notebooks'));
      await tester.pumpAndSettle();
      await tester.tap(_key('new-notebook-pdf'));
      await tester.pumpAndSettle();
      await tester.tap(_key('pdf-mode-read'));
      await tester.pumpAndSettle();
      expect(find.text('Este PDF é protegido por senha.'), findsOneWidget);
      expect((await notes()).where((n) => n.title == 'Apostila Física'), isEmpty);
    });
  });
}
