import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/note.dart';
import 'package:organizacional/domain/notebook_linked_note.dart';
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
/// seleção, o "Adicionar às notas" do menu do leitor e a troca de página.
Widget fakePdfView(BuildContext context, PdfViewRequest r) => Column(
  children: [
    Text('PDF ${r.data.length} bytes, abriu na p. ${r.initialPage}', key: const Key('fake-pdf')),
    TextButton(
      key: const Key('fake-select'),
      onPressed: () => r.onSelection(const PdfSelection('O limite\nde f(x)', page: 3)),
      child: const Text('selecionar'),
    ),
    TextButton(
      key: const Key('fake-select-more'),
      onPressed: () => r.onSelection(const PdfSelection('O limite de f(x) quando x tende a zero', page: 3)),
      child: const Text('arrastar'),
    ),
    TextButton(key: const Key('fake-unselect'), onPressed: () => r.onSelection(null), child: const Text('limpar')),
    TextButton(
      key: const Key('fake-menu-note'),
      onPressed: () => r.onAddToNotes(const PdfSelection('Teorema do valor médio', page: 7)),
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

  Future<Note> linkedNote() async =>
      (await notes()).firstWhere((n) => !n.isNotebook && n.title == 'Notas — Cálculo');

  testWidgets('selecionar texto mostra "Adicionar às notas do caderno", que acrescenta o trecho sem diálogo', (tester) async {
    await open(tester);
    expect(_key('pdf-add-note'), findsNothing);
    await tester.tap(_key('fake-select'));
    await tester.pumpAndSettle();
    expect(find.text('Adicionar às notas do caderno'), findsOneWidget);
    expect(find.text('Criar nota'), findsNothing);
    await tester.tap(_key('pdf-add-note'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing, reason: 'entra direto, sem caixa de edição');
    final note = await linkedNote();
    expect(note.isNotebook, isFalse);
    expect(note.spaceId, 's1', reason: 'na mesma pasta do caderno');
    // Linhas juntas, citação e a fonte "p. N · dd/MM" (a data do relógio do teste).
    expect(note.body, '> O limite de f(x)\n\n_p. 3 · 28/09_');
    expect(find.text('Adicionado às notas de Cálculo'), findsOneWidget);
    expect(_key('linked-note-open'), findsOneWidget);
    expect(find.text('Desfazer'), findsOneWidget);
    expect(_key('pdf-add-note'), findsNothing, reason: 'a seleção já foi enviada');
    expect((await notes()).firstWhere((n) => n.id == 'c1').linkedNoteId, note.id);
  });

  testWidgets('arrastar a seleção: o botão fica e a nota leva o trecho final', (tester) async {
    await open(tester);
    await tester.tap(_key('fake-select'));
    await tester.pumpAndSettle();
    await tester.tap(_key('fake-select-more'));
    await tester.pumpAndSettle();
    expect(_key('pdf-add-note'), findsOneWidget);
    await tester.tap(_key('pdf-add-note'));
    await tester.pumpAndSettle();
    expect((await linkedNote()).body, startsWith('> O limite de f(x) quando x tende a zero'));
  });

  testWidgets('"Adicionar às notas do caderno" do menu do leitor também acrescenta, sempre na mesma nota', (tester) async {
    await open(tester);
    await tester.tap(_key('fake-menu-note'));
    await tester.pumpAndSettle();
    await tester.tap(_key('fake-select'));
    await tester.pumpAndSettle();
    await tester.tap(_key('pdf-add-note'));
    await tester.pumpAndSettle();
    final all = (await notes()).where((n) => !n.isNotebook).toList();
    expect(all, hasLength(1), reason: 'toda vez na mesma nota');
    expect(all.single.body, '> Teorema do valor médio\n\n_p. 7 · 28/09_\n\n> O limite de f(x)\n\n_p. 3 · 28/09_');
  });

  testWidgets('Desfazer tira o bloco; a nota criada agora some e o vínculo é limpo', (tester) async {
    await open(tester);
    await tester.tap(_key('fake-menu-note'));
    await tester.pumpAndSettle();
    expect((await linkedNote()).body, isNotEmpty);
    await tester.tap(find.text('Desfazer'));
    await tester.pumpAndSettle();
    expect((await notes()).where((n) => !n.isNotebook), isEmpty);
    final book = (await notes()).single;
    expect(book.linkedNoteId, isNull);
    expect(book.pdfInfo!.files, [file], reason: 'o PDF continua no caderno');
  });

  testWidgets('Desfazer o segundo trecho deixa o primeiro', (tester) async {
    await open(tester);
    await tester.tap(_key('fake-menu-note'));
    await tester.pumpAndSettle();
    await tester.tap(_key('fake-select'));
    await tester.pumpAndSettle();
    await tester.tap(_key('pdf-add-note'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Desfazer'));
    await tester.pumpAndSettle();
    expect((await linkedNote()).body, '> Teorema do valor médio\n\n_p. 7 · 28/09_');
  });

  testWidgets('Abrir leva à nota vinculada, com o link de volta ao caderno', (tester) async {
    await open(tester);
    await tester.tap(_key('fake-menu-note'));
    await tester.pumpAndSettle();
    await tester.tap(_key('linked-note-open'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: _key('note-title'), matching: find.text('Notas — Cálculo')), findsOneWidget);
    expect(_key('linked-notebook-link'), findsOneWidget);
    expect(find.text('📒 Abrir o caderno Cálculo'), findsOneWidget);
  });

  testWidgets('sem conexão: avisa e não cria nada', (tester) async {
    await open(tester);
    repo.failWrites = true;
    await tester.tap(_key('fake-menu-note'));
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível adicionar às notas do caderno.'), findsOneWidget);
    repo.failWrites = false;
    expect((await notes()).where((n) => !n.isNotebook), isEmpty);
  });

  testWidgets('botão "Notas": cria a nota vazia na primeira vez e abre; depois abre a mesma', (tester) async {
    await open(tester);
    expect(find.byTooltip('Notas'), findsOneWidget);
    await tester.tap(_key('pdf-open-notes'));
    await tester.pumpAndSettle();
    final first = await linkedNote();
    expect(first.body, '');
    expect(find.descendant(of: _key('note-title'), matching: find.text('Notas — Cálculo')), findsOneWidget);
    // Volta ao leitor (o caderno é o livro) pelo link do topo da nota.
    await tester.tap(_key('linked-notebook-link'));
    await tester.pumpAndSettle();
    expect(_key('fake-pdf'), findsOneWidget);
    await tester.tap(_key('pdf-open-notes'));
    await tester.pumpAndSettle();
    expect((await notes()).where((n) => !n.isNotebook), hasLength(1));
    expect(_key('note-title'), findsOneWidget);
  });

  testWidgets('em 360 dp a barra e o botão cabem sem estourar', (tester) async {
    const second = NotebookPdfFile(path: 'u/c1/1.pdf', name: 'Lista.pdf');
    pdfs[second.path] = Uint8List(7);
    await repo.upsertNote((await notes()).single.withPdfFile(second));
    await pumpApp(
      tester,
      repo,
      notebookRepo: nb,
      size: const Size(360, 640),
      location: '/caderno/c1',
      overrides: [
        notesTabPrefsProvider.overrideWithValue(MemoryNotesTabPrefs()),
        notebookPdfStoreFactoryProvider.overrideWithValue((id) => MemoryNotebookPdfStore(id, pdfs)),
        pdfReadingPositionsProvider.overrideWithValue(positions),
        pdfViewBuilderProvider.overrideWithValue(fakePdfView),
      ],
    );
    await tester.pumpAndSettle();
    await tester.tap(_key('fake-select'));
    await tester.pumpAndSettle();
    expect(_key('pdf-add-note'), findsOneWidget);
    expect(_key('pdf-open-notes'), findsOneWidget);
    await tester.tap(_key('pdf-add-note'));
    await tester.pumpAndSettle();
    expect(find.text('Adicionado às notas de Cálculo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desfazer a seleção esconde o botão e nada é criado', (tester) async {
    await open(tester);
    await tester.tap(_key('fake-select'));
    await tester.pumpAndSettle();
    expect(_key('pdf-add-note'), findsOneWidget);
    await tester.tap(_key('fake-unselect'));
    await tester.pumpAndSettle();
    expect(_key('pdf-add-note'), findsNothing);
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
