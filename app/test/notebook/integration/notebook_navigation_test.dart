import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/note.dart';
import 'package:organizacional/features/notes/note_screen.dart';
import 'package:organizacional/features/notes/notes_screen.dart';
import 'package:organizacional/features/today/today_screen.dart';
import 'package:organizacional/notebook/data/memory_notebook_repository.dart';
import 'package:organizacional/notebook/state/notebook_providers.dart';
import 'package:organizacional/notebook/ui/notebook_screen.dart';

import '../../helpers.dart';
import '../data/notebook_test_support.dart';

const _phone = Size(400, 800);
const _notebookScreen = Key('notebook-screen');

Future<void> back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

void main() {
  late MemoryRepository repo;
  late MemoryNotebookRepository nb;

  setUp(() async {
    repo = MemoryRepository();
    nb = MemoryNotebookRepository();
    await repo.upsertNote(const Note(id: 'c1', title: 'Cálculo (caderno)', kind: NoteKind.notebook));
    await repo.upsertNote(const Note(id: 't1', title: 'Resumo', body: 'texto'));
    await nb.addPage('c1');
  });

  Future<List<Note>> notes() => repo.watchNotes().first;

  group('novo caderno', () {
    testWidgets('cria uma nota kind=notebook com uma página e abre o caderno', (tester) async {
      await pumpApp(tester, repo, notebookRepo: nb, size: _phone, location: '/notas');
      await tester.tap(find.byKey(const Key('new-notebook')));
      await tester.pumpAndSettle();
      final created = (await notes()).firstWhere((n) => n.title == 'Caderno');
      expect(created.kind, NoteKind.notebook);
      expect(created.body, '');
      expect(await nb.listPages(created.id), hasLength(1));
      expect(find.byKey(_notebookScreen), findsOneWidget);
      expect(find.byType(NotebookScreen), findsOneWidget);
    });

    testWidgets('o título é único: Caderno, Caderno 2…', (tester) async {
      await pumpApp(tester, repo, notebookRepo: nb, size: _phone, location: '/notas');
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byKey(const Key('new-notebook')));
        await tester.pumpAndSettle();
        await back(tester);
      }
      final titles = (await notes()).map((n) => n.title).toSet();
      expect(titles, containsAll(['Caderno', 'Caderno 2']));
    });

    testWidgets('também existe na barra lateral (tela larga)', (tester) async {
      await pumpApp(tester, repo, notebookRepo: nb, location: '/notas');
      await tester.tap(find.byKey(const Key('new-notebook')));
      await tester.pumpAndSettle();
      expect(find.byKey(_notebookScreen), findsOneWidget);
    });

    testWidgets('ação rápida "Caderno" do Início cria e abre', (tester) async {
      await pumpApp(tester, repo, notebookRepo: nb, size: _phone);
      expect(find.byType(TodayScreen), findsOneWidget);
      await tester.tap(find.byKey(const Key('quick-new-notebook')));
      await tester.pumpAndSettle();
      expect(find.byKey(_notebookScreen), findsOneWidget);
      expect((await notes()).where((n) => n.isNotebook), hasLength(2));
    });
  });

  group('abrir', () {
    testWidgets('tocar num caderno na árvore abre /caderno/:id; nota de texto continua no editor', (tester) async {
      await pumpApp(tester, repo, notebookRepo: nb, size: _phone, location: '/notas');
      await tester.tap(find.byKey(const ValueKey('tree-note-t1')));
      await tester.pumpAndSettle();
      expect(find.byType(NoteScreen), findsOneWidget);
      expect(find.byKey(_notebookScreen), findsNothing);
      await back(tester);
      await tester.tap(find.byKey(const ValueKey('tree-note-c1')));
      await tester.pumpAndSettle();
      expect(find.byKey(_notebookScreen), findsOneWidget);
      expect(find.byType(NoteScreen), findsNothing);
      final screen = tester.widget<NotebookScreen>(find.byKey(_notebookScreen));
      expect(screen.noteId, 'c1');
      expect(screen.title, 'Cálculo (caderno)');
    });

    testWidgets('/nota/:id de um caderno (link, espaço, busca) redireciona para o caderno', (tester) async {
      await pumpApp(tester, repo, notebookRepo: nb, size: _phone, location: '/nota/c1');
      expect(find.byKey(_notebookScreen), findsOneWidget);
      expect(find.byType(NoteScreen), findsNothing);
    });

    testWidgets('caderno inexistente mostra aviso em vez de quebrar', (tester) async {
      await pumpApp(tester, repo, notebookRepo: nb, size: _phone, location: '/caderno/nao-existe');
      expect(find.byKey(_notebookScreen), findsNothing);
      expect(find.text('Caderno não encontrado.'), findsOneWidget);
    });
  });

  group('voltar', () {
    testWidgets('de um caderno aberto pela lista, voltar leva à lista de notas (sem sair)', (tester) async {
      var exits = 0;
      await pumpApp(tester, repo, notebookRepo: nb, size: _phone, location: '/notas', exitApp: () => exits++);
      await tester.tap(find.byKey(const ValueKey('tree-note-c1')));
      await tester.pumpAndSettle();
      await back(tester);
      expect(find.byKey(_notebookScreen), findsNothing);
      expect(find.byType(NotesScreen), findsOneWidget);
      expect(exits, 0);
    });

    testWidgets('aberto por link direto (sem pilha), voltar vai para Notas e não fecha o app', (tester) async {
      var exits = 0;
      await pumpApp(tester, repo, notebookRepo: nb, size: _phone, location: '/caderno/c1', exitApp: () => exits++);
      expect(find.byKey(_notebookScreen), findsOneWidget);
      await back(tester);
      expect(find.byKey(_notebookScreen), findsNothing);
      expect(find.byType(NotesScreen), findsOneWidget);
      expect(exits, 0);
    });

    testWidgets('sair antes do debounce não perde a tinta: o controller segue vivo até gravar', (tester) async {
      await pumpApp(tester, repo, notebookRepo: nb, size: _phone, location: '/notas');
      await tester.tap(find.byKey(const ValueKey('tree-note-c1')));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(tester.element(find.byKey(_notebookScreen)));
      final controller = container.read(notebookControllerProvider('c1'));
      controller.updatePage(0, docOf(['s1']));
      await back(tester); // sai logo, antes dos 1,5 s
      expect(find.byKey(_notebookScreen), findsNothing);
      expect(idsOf((await nb.listPages('c1')).single.data), isEmpty);
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pumpAndSettle();
      expect(idsOf((await nb.listPages('c1')).single.data), {'s1'});
      // Depois de salvar, o controller é descartado (nada fica vivo à toa).
      await tester.pump(const Duration(seconds: 1));
      expect(container.exists(notebookControllerProvider('c1')), isFalse);
    });
  });
}
