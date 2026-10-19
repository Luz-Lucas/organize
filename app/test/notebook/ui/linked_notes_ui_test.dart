import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide TextBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/note.dart';
import 'package:organizacional/domain/notebook_cover.dart';
import 'package:organizacional/domain/notebook_linked_note.dart';
import 'package:organizacional/notebook/core/notebook_core.dart';
import 'package:organizacional/notebook/data/memory_notebook_repository.dart';
import 'package:organizacional/notebook/intelligence/model_manager.dart';
import 'package:organizacional/notebook/intelligence/recognizer.dart';
import 'package:organizacional/notebook/ui/notebook_screen.dart';
import 'package:organizacional/ui/org_theme.dart';

import '../../helpers.dart';
import '../intelligence/fake_recognizer.dart';
import '../intelligence/handwriting.dart';
import 'ui_support.dart';

Finder _key(String k) => find.byKey(Key(k));
Finder _vkey(String k) => find.byKey(ValueKey(k));

/// Uma linha escrita à mão e o reconhecedor que a "lê".
({PageDoc doc, FakeInkRecognizer rec}) written(String text) {
  final w = writeLine(text, start: const Offset(80, 400), ids: IdGen(), hand: const Hand(seed: 5));
  final words = text.split(' ');
  final rec = FakeInkRecognizer(resolve: (strokes) {
    final ids = {for (final s in strokes) s.id};
    final parts = [
      for (var i = 0; i < words.length; i++)
        if (w.wordIds[i].every(ids.contains)) words[i],
    ];
    return parts.isEmpty ? const [] : [parts.join(' ')];
  });
  return (doc: PageDoc.empty.withStrokes(w.strokes), rec: rec);
}

Future<void> lassoAll(WidgetTester tester) async {
  await tester.tap(_vkey('nb-tool-lasso'));
  await tester.pump();
  await SimPointer(tester, PointerDeviceKind.stylus).drag(const [
    Offset(30, 320),
    Offset(960, 320),
    Offset(960, 470),
    Offset(30, 470),
    Offset(30, 322),
  ]);
}

/// A barra da seleção rola na horizontal: leva "Enviar…" até a tela e toca.
Future<void> tapSend(WidgetTester tester) async {
  final target = _vkey('nb-sel-send');
  await tester.dragUntilVisible(target, _selectionBarScroll, const Offset(-120, 0));
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Finder get _selectionBarScroll =>
    find.ancestor(of: _vkey('nb-sel-delete'), matching: find.byType(Scrollable)).first;

void main() {
  late MemoryRepository repo;
  late MemoryNotebookRepository nb;
  const cover = NotebookCover(kind: CoverKind.emoji, emoji: '📒');

  setUp(() async {
    repo = MemoryRepository();
    nb = MemoryNotebookRepository();
    await repo.upsertNote(
      const Note(id: 'c1', title: 'Cálculo', kind: NoteKind.notebook, spaceId: 's1').withCover(cover),
    );
  });

  Future<List<Note>> notes() => repo.watchNotes().first;
  Future<List<Note>> texts() async => (await notes()).where((n) => !n.isNotebook).toList();

  Future<void> openNotebook(WidgetTester tester, {InkRecognizer? rec, PageDoc? doc, Size size = const Size(800, 1300)}) async {
    final page = await nb.addPage('c1');
    if (doc != null) await nb.savePage(page.copyWith(data: encodePage(doc)));
    await pumpApp(
      tester,
      repo,
      notebookRepo: nb,
      size: size,
      location: '/caderno/c1',
      overrides: [if (rec != null) inkRecognizerProvider.overrideWithValue(rec)],
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('botão Notas', () {
    testWidgets('na barra do caderno: cria a nota vazia na primeira vez e abre', (tester) async {
      await openNotebook(tester);
      expect(find.byTooltip('Notas'), findsOneWidget);
      await tester.tap(_vkey('nb-open-notes'));
      await tester.pumpAndSettle();
      final note = (await texts()).single;
      expect(note.title, 'Notas — Cálculo');
      expect(note.body, '');
      expect(note.spaceId, 's1');
      expect(_key('note-title'), findsOneWidget);
      expect((await notes()).firstWhere((n) => n.id == 'c1').cover, cover, reason: 'a capa fica');
      expect(find.text('📒 Abrir o caderno Cálculo'), findsOneWidget);
    });

    testWidgets('da segunda vez abre a mesma nota', (tester) async {
      await openNotebook(tester);
      await tester.tap(_vkey('nb-open-notes'));
      await tester.pumpAndSettle();
      await tester.tap(_key('linked-notebook-link'));
      await tester.pumpAndSettle();
      await tester.tap(_vkey('nb-open-notes'));
      await tester.pumpAndSettle();
      expect(await texts(), hasLength(1));
      expect(_key('note-title'), findsOneWidget);
    });
  });

  group('Enviar para as notas do caderno', () {
    testWidgets('converte a seleção em texto e acrescenta com a fonte, sem mexer na página', (tester) async {
      final p = written('o gato quase');
      await openNotebook(tester, rec: p.rec, doc: p.doc);
      await lassoAll(tester);
      await tapSend(tester);

      final note = (await texts()).single;
      expect(note.title, 'Notas — Cálculo');
      expect(note.body, 'o gato quase\n\n_Caderno · p. 1 · 28/09_');
      expect(find.text('Adicionado às notas de Cálculo'), findsOneWidget);
      expect(_key('linked-note-open'), findsOneWidget);
      expect(find.text('Desfazer'), findsOneWidget);
      expect((await notes()).firstWhere((n) => n.id == 'c1').linkedNoteId, note.id);
    });

    testWidgets('o segundo envio vai para a mesma nota', (tester) async {
      final p = written('o gato quase');
      await openNotebook(tester, rec: p.rec, doc: p.doc);
      await lassoAll(tester);
      await tapSend(tester);
      tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).removeCurrentSnackBar();
      await tester.pumpAndSettle();
      await tapSend(tester);
      final all = await texts();
      expect(all, hasLength(1));
      expect(all.single.body, 'o gato quase\n\n_Caderno · p. 1 · 28/09_\n\no gato quase\n\n_Caderno · p. 1 · 28/09_');
    });

    testWidgets('Desfazer apaga a nota criada agora e solta o vínculo', (tester) async {
      final p = written('o gato quase');
      await openNotebook(tester, rec: p.rec, doc: p.doc);
      await lassoAll(tester);
      await tapSend(tester);
      await tester.tap(find.text('Desfazer'));
      await tester.pumpAndSettle();
      expect(await texts(), isEmpty);
      final book = (await notes()).single;
      expect(book.linkedNoteId, isNull);
      expect(book.cover, cover);
    });

    testWidgets('Abrir leva à nota, com o link de volta ao caderno', (tester) async {
      final p = written('o gato quase');
      await openNotebook(tester, rec: p.rec, doc: p.doc);
      await lassoAll(tester);
      await tapSend(tester);
      await tester.tap(_key('linked-note-open'));
      await tester.pumpAndSettle();
      expect(_key('note-title'), findsOneWidget);
      expect(find.text('📒 Abrir o caderno Cálculo'), findsOneWidget);
      // Voltar ao caderno pelo link (o caderno já estava na pilha).
      await tester.tap(_key('linked-notebook-link'));
      await tester.pumpAndSettle();
      expect(_key('notebook-screen'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('texto já convertido (caixa de texto selecionada) também é enviado', (tester) async {
      final p = written('o gato quase');
      await openNotebook(tester, rec: p.rec, doc: p.doc);
      await lassoAll(tester);
      await tester.dragUntilVisible(_vkey('nb-sel-convert'), _selectionBarScroll, const Offset(-120, 0));
      await tester.pumpAndSettle();
      await tester.tap(_vkey('nb-sel-convert'));
      await tester.pumpAndSettle();
      tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).removeCurrentSnackBar();
      await tester.pumpAndSettle();
      await tapSend(tester);
      expect((await texts()).single.body, 'o gato quase\n\n_Caderno · p. 1 · 28/09_');
    });

    testWidgets('nada reconhecido: avisa e não cria nota', (tester) async {
      final p = written('o gato quase');
      await openNotebook(tester, rec: FakeInkRecognizer(), doc: p.doc);
      await lassoAll(tester);
      await tapSend(tester);
      expect(find.text('Não deu para reconhecer a escrita.'), findsOneWidget);
      expect(await texts(), isEmpty);
    });

    testWidgets('sem o modelo baixado: avisa e não cria nota', (tester) async {
      final p = written('o gato quase');
      p.rec.ready = false;
      await openNotebook(tester, rec: p.rec, doc: p.doc);
      await lassoAll(tester);
      await tapSend(tester);
      expect(find.text('Baixe o modelo de escrita em Ajustes → Escrita à mão.'), findsOneWidget);
      expect(await texts(), isEmpty);
    });

    testWidgets('sem reconhecimento (Linux/Windows) a ação fica escondida', (tester) async {
      final p = written('o gato quase');
      await openNotebook(tester, doc: p.doc);
      await lassoAll(tester);
      await tester.dragUntilVisible(_vkey('nb-sel-convert-hint'), _selectionBarScroll, const Offset(-120, 0));
      expect(_vkey('nb-sel-send'), findsNothing);
    });

    testWidgets('sem conexão: avisa e a página não muda', (tester) async {
      final p = written('o gato quase');
      await openNotebook(tester, rec: p.rec, doc: p.doc);
      await lassoAll(tester);
      repo.failWrites = true;
      await tapSend(tester);
      expect(find.text('Não foi possível adicionar às notas do caderno.'), findsOneWidget);
      repo.failWrites = false;
      expect(await texts(), isEmpty);
    });
  });

  testWidgets('em 360 dp a barra do caderno com o botão Notas não estoura', (tester) async {
    final p = written('o gato quase');
    await openNotebook(tester, rec: p.rec, doc: p.doc, size: const Size(360, 740));
    expect(_vkey('nb-open-notes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('nota vinculada: o link de volta cabe em 360 dp mesmo com nome de caderno comprido', (tester) async {
    const long = 'Cálculo diferencial e integral para engenharia — volume 2 (edição revisada)';
    await repo.upsertNote(const Note(id: 'c2', title: long, kind: NoteKind.notebook).withLinkedNoteId('n1'));
    await repo.upsertNote(const Note(id: 'n1', title: 'Notas — $long'));
    await pumpApp(tester, repo, notebookRepo: nb, size: const Size(360, 740), location: '/nota/n1');
    expect(_key('linked-notebook-link'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('nota comum não mostra o link do caderno', (tester) async {
    await repo.upsertNote(const Note(id: 'n1', title: 'Uma nota', body: 'texto'));
    await pumpApp(tester, repo, notebookRepo: nb, size: const Size(400, 800), location: '/nota/n1');
    expect(_key('note-title'), findsOneWidget);
    expect(_key('linked-notebook-link'), findsNothing);
  });

  testWidgets('NotebookScreen sozinha: sem os callbacks não há botão Notas nem envio', (tester) async {
    final session = FakeSession();
    await setSurface(tester, const Size(360, 740));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildOrgTheme(orgThemes.first, googleFonts: false),
        home: NotebookScreen(noteId: 'n1', session: session, title: 'Caderno'),
      ),
    );
    await tester.pump();
    expect(_vkey('nb-open-notes'), findsNothing);
  });
}
