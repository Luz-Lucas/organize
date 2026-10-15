import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:organizacional/domain/note.dart';
import 'package:organizacional/domain/space.dart';
import 'package:organizacional/domain/task_item.dart';
import 'package:organizacional/features/notes/notebooks/notebooks_prefs.dart';
import 'package:organizacional/features/notes/notebooks/notebooks_view.dart';
import 'package:organizacional/notebook/data/memory_notebook_repository.dart';

import 'dart:typed_data';

import 'package:organizacional/notebook/pdf/pdf_providers.dart';
import 'package:organizacional/notebook/pdf/pick_pdf.dart';

import '../../helpers.dart';
import '../../notebook/pdf/pdf_import_test.dart' show FakePdfRasterizer;

const _phone = Size(400, 800);
const _small = Size(360, 740);
const _tablet = Size(1000, 800);

Finder _key(String k) => find.byKey(Key(k));
Finder _vkey(String k) => find.byKey(ValueKey(k));

extension on WidgetTester {
  /// Toca/segura um item da lista de pastas, rolando a fila de chips até ele se preciso.
  Future<void> tapV(Finder f) async {
    await ensureVisible(f);
    await pumpAndSettle();
    await tap(f);
  }

  Future<void> pressV(Finder f) async {
    await ensureVisible(f);
    await pumpAndSettle();
    await longPress(f);
  }
}

void main() {
  late MemoryRepository repo;
  late MemoryNotebookRepository nb;
  late MemoryNotesTabPrefs prefs;

  setUp(() async {
    repo = MemoryRepository();
    nb = MemoryNotebookRepository();
    prefs = MemoryNotesTabPrefs();
    await repo.upsertSpace(const Space(id: 'm1', name: 'Cálculo', kind: SpaceKind.materia, color: '#E5484D'));
    await repo.upsertSpace(const Space(id: 'm2', name: 'Redes', kind: SpaceKind.materia, position: 1));
    await repo.upsertSpace(const Space(id: 'g1', name: 'Projetos', position: 2));
    await repo.upsertNote(Note(
        id: 'c1', title: 'Limites', spaceId: 'm1', kind: NoteKind.notebook, updatedAt: DateTime(2026, 9, 28, 8)));
    await repo.upsertNote(Note(
        id: 'c2', title: 'Ideias', spaceId: 'g1', kind: NoteKind.notebook, updatedAt: DateTime(2026, 9, 20)));
    await repo.upsertNote(
        Note(id: 'c3', title: 'Rascunho', kind: NoteKind.notebook, updatedAt: DateTime(2026, 9, 10)));
    await repo.upsertNote(const Note(id: 'n1', title: 'Resumo', spaceId: 'm1'));
  });

  Future<void> open(WidgetTester tester, {Size size = _phone, bool notebooksTab = true}) async {
    await pumpApp(tester, repo,
        notebookRepo: nb, size: size, location: '/notas', overrides: [notesTabPrefsProvider.overrideWithValue(prefs)]);
    if (notebooksTab) {
      await tester.tap(_key('notes-tab-notebooks'));
      await tester.pumpAndSettle();
    }
  }

  Future<Note> note(String id) async => (await repo.watchNotes().first).firstWhere((n) => n.id == id);
  Future<List<Space>> spaces() => repo.watchSpaces().first;
  Future<Space> space(String id) async => (await spaces()).firstWhere((s) => s.id == id);
  Finder card(String id) => _vkey('nb-card-$id');

  group('abas Notas | Cadernos', () {
    testWidgets('abre em Notas; Cadernos mostra a grade com título e data', (tester) async {
      await open(tester, notebooksTab: false);
      expect(_key('notes-tab-notes'), findsOneWidget);
      expect(_key('notes-tab-notebooks'), findsOneWidget);
      expect(_key('notes-search'), findsOneWidget); // a árvore de notas
      expect(card('c1'), findsNothing);

      await tester.tap(_key('notes-tab-notebooks'));
      await tester.pumpAndSettle();
      expect(_key('notes-search'), findsNothing);
      for (final id in ['c1', 'c2', 'c3']) {
        expect(card(id), findsOneWidget);
      }
      expect(card('n1'), findsNothing, reason: 'nota de texto não é caderno');
      expect(find.descendant(of: card('c1'), matching: find.text('Limites')), findsOneWidget);
      expect(find.descendant(of: card('c1'), matching: find.text('há 2 h')), findsOneWidget);
      expect(find.descendant(of: card('c2'), matching: find.text('20 set')), findsOneWidget);
    });

    testWidgets('a aba escolhida é lembrada por aparelho', (tester) async {
      await open(tester);
      expect(await prefs.load(), 'notebooks');
      await tester.tap(_key('notes-tab-notes'));
      await tester.pumpAndSettle();
      expect(await prefs.load(), 'notes');
    });

    testWidgets('abre direto em Cadernos se foi a última aba usada', (tester) async {
      await prefs.save('notebooks');
      await open(tester, notebooksTab: false);
      expect(card('c1'), findsOneWidget);
    });
  });

  group('lista de pastas', () {
    testWidgets('no celular: chips Todos, matérias | pastas, Sem pasta, nessa ordem', (tester) async {
      await open(tester);
      expect(_key('nb-folder-rail'), findsNothing);
      double x(Finder f) => tester.getTopLeft(f).dx;
      final order = [
        x(_vkey('nb-folder-all')),
        x(_vkey('nb-folder-m1')),
        x(_vkey('nb-folder-m2')),
        x(_key('nb-folder-divider')),
        x(_vkey('nb-folder-g1')),
        x(_vkey('nb-folder-none')),
      ];
      expect(order, [...order]..sort());
      expect(order.toSet().length, order.length);
    });

    testWidgets('no tablet: coluna lateral com rótulos Matérias e Pastas', (tester) async {
      await open(tester, size: _tablet);
      expect(_key('nb-folder-rail'), findsOneWidget);
      double y(Finder f) => tester.getTopLeft(f).dy;
      final order = [
        y(_vkey('nb-folder-all')),
        y(_key('nb-folder-label-materias')),
        y(_vkey('nb-folder-m1')),
        y(_vkey('nb-folder-m2')),
        y(_key('nb-folder-label-pastas')),
        y(_vkey('nb-folder-g1')),
        y(_vkey('nb-folder-none')),
      ];
      expect(order, [...order]..sort());
      expect(order.toSet().length, order.length);
    });

    testWidgets('sem pastas de um dos grupos, o separador e o rótulo somem', (tester) async {
      await repo.deleteSpace('g1');
      await open(tester, size: _tablet);
      expect(_key('nb-folder-label-materias'), findsOneWidget);
      expect(_key('nb-folder-label-pastas'), findsNothing);
    });

    testWidgets('tocar numa pasta filtra os cadernos', (tester) async {
      await open(tester);
      await tester.tapV(_vkey('nb-folder-m1'));
      await tester.pumpAndSettle();
      expect(card('c1'), findsOneWidget);
      expect(card('c2'), findsNothing);
      expect(card('c3'), findsNothing);

      await tester.tapV(_vkey('nb-folder-none'));
      await tester.pumpAndSettle();
      expect(card('c3'), findsOneWidget);
      expect(card('c1'), findsNothing);

      await tester.tapV(_vkey('nb-folder-all'));
      await tester.pumpAndSettle();
      expect(card('c1'), findsOneWidget);
      expect(card('c2'), findsOneWidget);
      expect(card('c3'), findsOneWidget);
    });

    testWidgets('pasta vazia mostra um aviso', (tester) async {
      await open(tester);
      await tester.tapV(_vkey('nb-folder-m2'));
      await tester.pumpAndSettle();
      expect(find.text('Nenhum caderno nesta pasta.'), findsOneWidget);
    });
  });

  group('ordenar e buscar', () {
    testWidgets('mais recentes primeiro; por nome pelo menu de ordem', (tester) async {
      await open(tester);
      List<double> ys(List<String> ids) => [for (final id in ids) tester.getTopLeft(card(id)).dy * 1000 + tester.getTopLeft(card(id)).dx];
      expect(ys(['c1', 'c2', 'c3']), [...ys(['c1', 'c2', 'c3'])]..sort());
      await tester.tap(_key('nb-sort'));
      await tester.pumpAndSettle();
      await tester.tap(_key('nb-sort-name'));
      await tester.pumpAndSettle();
      // Ideias, Limites, Rascunho
      expect(ys(['c2', 'c1', 'c3']), [...ys(['c2', 'c1', 'c3'])]..sort());
    });

    testWidgets('busca pelo título e pelo texto reconhecido, sem acento', (tester) async {
      final page = await nb.addPage('c2');
      nb.setRecognizedText(page.id, 'derivada parcial');
      await open(tester);
      await tester.enterText(_key('nb-search'), 'LIMITES');
      await tester.pumpAndSettle();
      expect(card('c1'), findsOneWidget);
      expect(card('c2'), findsNothing);

      await tester.enterText(_key('nb-search'), 'Parcial');
      await tester.pumpAndSettle();
      expect(card('c2'), findsOneWidget);
      expect(card('c1'), findsNothing);

      await tester.enterText(_key('nb-search'), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('Nada encontrado.'), findsOneWidget);
    });
  });

  group('novo caderno', () {
    testWidgets('nasce na pasta aberta', (tester) async {
      await open(tester);
      await tester.tapV(_vkey('nb-folder-g1'));
      await tester.pumpAndSettle();
      await tester.tap(_key('new-notebook'));
      await tester.pumpAndSettle();
      final created = (await repo.watchNotes().first).firstWhere((n) => n.title == 'Caderno');
      expect(created.isNotebook, isTrue);
      expect(created.spaceId, 'g1');
      expect(_key('notebook-screen'), findsOneWidget);
    });

    testWidgets('em Todos e em Sem pasta nasce sem pasta', (tester) async {
      await open(tester);
      await tester.tap(_key('new-notebook'));
      await tester.pumpAndSettle();
      expect((await note((await repo.watchNotes().first).firstWhere((n) => n.title == 'Caderno').id)).spaceId, isNull);
    });

    testWidgets('no tablet o botão da aba cria na pasta aberta', (tester) async {
      await open(tester, size: _tablet);
      await tester.tapV(_vkey('nb-folder-m2'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(NotebooksView), matching: _key('new-notebook')));
      await tester.pumpAndSettle();
      final created = (await repo.watchNotes().first).firstWhere((n) => n.title == 'Caderno');
      expect(created.spaceId, 'm2');
    });
  });

  group('novo caderno a partir de PDF', () {
    testWidgets('sem leitor de PDF o botão não aparece', (tester) async {
      await open(tester);
      expect(_key('new-notebook-pdf'), findsNothing);
    });

    testWidgets('cria o caderno com o nome do arquivo e abre com as páginas do PDF', (tester) async {
      await pumpApp(tester, repo, notebookRepo: nb, size: _phone, location: '/notas', overrides: [
        notesTabPrefsProvider.overrideWithValue(prefs),
        pdfRasterizerProvider.overrideWithValue(FakePdfRasterizer([(2000, 2828), (2000, 2828)])),
        pdfPickerProvider.overrideWithValue(
            () async => PickedPdf(bytes: Uint8List.fromList([1, 2, 3]), name: 'Lista_3 Cálculo.pdf')),
      ]);
      await tester.tap(_key('notes-tab-notebooks'));
      await tester.pumpAndSettle();
      await tester.tap(_key('new-notebook-pdf'));
      await tester.pumpAndSettle();
      final created = (await repo.watchNotes().first).firstWhere((n) => n.title == 'Lista 3 Cálculo');
      expect(created.isNotebook, isTrue);
      expect(_key('notebook-screen'), findsOneWidget);
      // Espera o salvamento do caderno (debounce) e confere o que foi gravado.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      final pages = await nb.listPages(created.id);
      expect(pages, hasLength(2), reason: 'a página em branco inicial dá lugar às do PDF');
    });
  });

  group('segurar um caderno', () {
    testWidgets('mover para outra pasta e para Sem pasta', (tester) async {
      await open(tester);
      await tester.longPress(card('c3'));
      await tester.pumpAndSettle();
      await tester.tap(_key('notebook-menu-move'));
      await tester.pumpAndSettle();
      await tester.tap(_key('move-to-m1'));
      await tester.pumpAndSettle();
      expect((await note('c3')).spaceId, 'm1');

      await tester.longPress(card('c1'));
      await tester.pumpAndSettle();
      await tester.tap(_key('notebook-menu-move'));
      await tester.pumpAndSettle();
      await tester.tap(_key('move-to-none'));
      await tester.pumpAndSettle();
      expect((await note('c1')).spaceId, isNull);
    });

    testWidgets('a folha de mover lista as pastas (matérias, pastas e Sem pasta)', (tester) async {
      await open(tester);
      await tester.longPress(card('c1'));
      await tester.pumpAndSettle();
      await tester.tap(_key('notebook-menu-move'));
      await tester.pumpAndSettle();
      for (final k in ['move-to-m1', 'move-to-m2', 'move-to-g1', 'move-to-none']) {
        expect(_key(k), findsOneWidget);
      }
    });

    testWidgets('renomear', (tester) async {
      await open(tester);
      await tester.longPress(card('c1'));
      await tester.pumpAndSettle();
      await tester.tap(_key('notebook-menu-rename'));
      await tester.pumpAndSettle();
      await tester.enterText(_key('notebook-rename-field'), 'Limites e derivadas');
      await tester.tap(_key('notebook-rename-ok'));
      await tester.pumpAndSettle();
      expect((await note('c1')).title, 'Limites e derivadas');
      expect(find.descendant(of: card('c1'), matching: find.text('Limites e derivadas')), findsOneWidget);
    });

    testWidgets('excluir pede confirmação e apaga só esse caderno', (tester) async {
      await open(tester);
      await tester.longPress(card('c3'));
      await tester.pumpAndSettle();
      await tester.tap(_key('notebook-menu-delete'));
      await tester.pumpAndSettle();
      await tester.tap(_key('notebook-delete-confirm'));
      await tester.pumpAndSettle();
      final ids = (await repo.watchNotes().first).map((n) => n.id).toSet();
      expect(ids, {'c1', 'c2', 'n1'});
      expect(card('c3'), findsNothing);
    });
  });

  group('menu do caderno na árvore de notas', () {
    testWidgets('segurar um caderno na aba Notas também oferece Mover para pasta', (tester) async {
      await open(tester, notebooksTab: false);
      await tester.longPress(_vkey('tree-note-c3'));
      await tester.pumpAndSettle();
      await tester.tap(_key('notebook-menu-move'));
      await tester.pumpAndSettle();
      await tester.tap(_key('move-to-g1'));
      await tester.pumpAndSettle();
      expect((await note('c3')).spaceId, 'g1');
    });
  });

  group('preferência da aba no aparelho', () {
    test('SharedPreferences guarda e devolve a aba', () async {
      SharedPreferences.setMockInitialValues({});
      const p = SharedPreferencesNotesTabPrefs();
      expect(await p.load(), isNull);
      await p.save('notebooks');
      expect(await p.load(), 'notebooks');
    });
  });

  group('pastas', () {
    Future<void> newFolder(WidgetTester tester, String name, {String? color, String? kind}) async {
      await tester.tap(_key('nb-new-folder'));
      await tester.pumpAndSettle();
      await tester.enterText(_key('folder-name'), name);
      if (color != null) await tester.tap(_key('folder-color-$color'));
      if (kind != null) await tester.tap(_key('folder-kind-$kind'));
      await tester.pumpAndSettle();
      await tester.tap(_key('folder-ok'));
      await tester.pumpAndSettle();
    }

    testWidgets('+ Pasta cria uma pasta livre (kind geral) com a cor, e já abre nela', (tester) async {
      await open(tester);
      await newFolder(tester, 'Anotações diversas', color: '3E63DD');
      final s = (await spaces()).firstWhere((s) => s.name == 'Anotações diversas');
      expect(s.kind, SpaceKind.geral);
      expect(s.color, '#3E63DD');
      expect(s.position, 3);
      expect(_vkey('nb-folder-${s.id}'), findsOneWidget);
      // Pasta aberta (vazia): o aviso aparece e um caderno novo nasce nela.
      expect(find.text('Nenhum caderno nesta pasta.'), findsOneWidget);
      await tester.tap(_key('new-notebook'));
      await tester.pumpAndSettle();
      expect((await repo.watchNotes().first).firstWhere((n) => n.title == 'Caderno').spaceId, s.id);
    });

    testWidgets('o tipo padrão do diálogo é Pasta', (tester) async {
      await open(tester);
      await newFolder(tester, 'Sem escolher tipo');
      expect((await spaces()).firstWhere((s) => s.name == 'Sem escolher tipo').kind, SpaceKind.geral);
    });

    testWidgets('+ Pasta com o tipo Matéria cria um espaço kind=materia, no grupo das matérias', (tester) async {
      await open(tester, size: _tablet);
      await newFolder(tester, 'Física', kind: 'materia');
      final s = (await spaces()).firstWhere((s) => s.name == 'Física');
      expect(s.kind, SpaceKind.materia);
      // Aparece antes do rótulo "Pastas".
      expect(tester.getTopLeft(_vkey('nb-folder-${s.id}')).dy,
          lessThan(tester.getTopLeft(_key('nb-folder-label-pastas')).dy));
    });

    testWidgets('nome vazio não cria', (tester) async {
      await open(tester);
      await tester.tap(_key('nb-new-folder'));
      await tester.pumpAndSettle();
      await tester.enterText(_key('folder-name'), '   ');
      await tester.tap(_key('folder-ok'));
      await tester.pumpAndSettle();
      expect((await spaces()), hasLength(3));
    });

    testWidgets('segurar a pasta: renomear e mudar a cor', (tester) async {
      await open(tester);
      await tester.pressV(_vkey('nb-folder-g1'));
      await tester.pumpAndSettle();
      await tester.tap(_key('folder-menu-rename'));
      await tester.pumpAndSettle();
      await tester.enterText(_key('folder-name'), 'Projetos 2026');
      await tester.tap(_key('folder-ok'));
      await tester.pumpAndSettle();
      expect((await space('g1')).name, 'Projetos 2026');

      await tester.pressV(_vkey('nb-folder-g1'));
      await tester.pumpAndSettle();
      await tester.tap(_key('folder-menu-color'));
      await tester.pumpAndSettle();
      await tester.tap(_key('folder-color-30A46C'));
      await tester.tap(_key('folder-ok'));
      await tester.pumpAndSettle();
      expect((await space('g1')).color, '#30A46C');
      expect((await space('g1')).name, 'Projetos 2026');
    });

    testWidgets('converter: pasta vira matéria e matéria vira pasta', (tester) async {
      await open(tester);
      await tester.pressV(_vkey('nb-folder-g1'));
      await tester.pumpAndSettle();
      expect(find.text('Transformar em matéria'), findsOneWidget);
      expect(find.text('Transformar em pasta'), findsNothing);
      await tester.tap(_key('folder-menu-kind'));
      await tester.pumpAndSettle();
      expect((await space('g1')).kind, SpaceKind.materia);

      await tester.pressV(_vkey('nb-folder-m2'));
      await tester.pumpAndSettle();
      expect(find.text('Transformar em pasta'), findsOneWidget);
      await tester.tap(_key('folder-menu-kind'));
      await tester.pumpAndSettle();
      expect((await space('m2')).kind, SpaceKind.geral);
    });

    testWidgets('Todos e Sem pasta não têm menu de pasta', (tester) async {
      await open(tester);
      await tester.pressV(_vkey('nb-folder-all'));
      await tester.pumpAndSettle();
      await tester.pressV(_vkey('nb-folder-none'));
      await tester.pumpAndSettle();
      expect(_key('folder-menu-rename'), findsNothing);
    });
  });

  group('excluir pasta nunca apaga cadernos', () {
    Future<void> startDelete(WidgetTester tester, String id) async {
      await tester.pressV(_vkey('nb-folder-$id'));
      await tester.pumpAndSettle();
      await tester.tap(_key('folder-menu-delete'));
      await tester.pumpAndSettle();
    }

    testWidgets('com só cadernos: confirma, os cadernos vão para Sem pasta e a pasta some', (tester) async {
      await open(tester);
      await tester.tapV(_vkey('nb-folder-g1'));
      await tester.pumpAndSettle();
      await startDelete(tester, 'g1');
      expect(find.textContaining('1 caderno'), findsOneWidget);
      expect(find.textContaining('Sem pasta'), findsWidgets);
      await tester.tap(_key('folder-delete-confirm'));
      await tester.pumpAndSettle();
      expect((await spaces()).map((s) => s.id), ['m1', 'm2']);
      final c2 = await note('c2');
      expect(c2.spaceId, isNull);
      expect(c2.isNotebook, isTrue);
      // Estava aberta: volta para Todos e o caderno continua à vista.
      expect(card('c2'), findsOneWidget);
      expect(card('c1'), findsOneWidget);
    });

    testWidgets('cancelar não muda nada', (tester) async {
      await open(tester);
      await startDelete(tester, 'g1');
      await tester.tap(_key('folder-delete-cancel'));
      await tester.pumpAndSettle();
      expect((await spaces()), hasLength(3));
      expect((await note('c2')).spaceId, 'g1');
    });

    testWidgets('pasta com notas de texto é bloqueada: nada é apagado', (tester) async {
      await open(tester);
      await startDelete(tester, 'm1'); // tem a nota de texto n1 e o caderno c1
      expect(_key('folder-delete-blocked-ok'), findsOneWidget);
      expect(_key('folder-delete-confirm'), findsNothing);
      await tester.tap(_key('folder-delete-blocked-ok'));
      await tester.pumpAndSettle();
      expect((await spaces()), hasLength(3));
      expect((await note('c1')).spaceId, 'm1');
      expect((await note('n1')).spaceId, 'm1');
    });

    testWidgets('pasta com tarefas também é bloqueada', (tester) async {
      await repo.upsertTask(const TaskItem(id: 't1', title: 'Lista', spaceId: 'g1'));
      await open(tester);
      await startDelete(tester, 'g1');
      expect(_key('folder-delete-blocked-ok'), findsOneWidget);
      await tester.tap(_key('folder-delete-blocked-ok'));
      await tester.pumpAndSettle();
      expect((await spaces()), hasLength(3));
      expect((await repo.watchTasks().first), hasLength(1));
    });

    testWidgets('se mover um caderno falhar, a pasta não é excluída', (tester) async {
      await open(tester);
      await startDelete(tester, 'g1');
      repo.failWrites = true;
      await tester.tap(_key('folder-delete-confirm'));
      await tester.pumpAndSettle();
      repo.failWrites = false;
      expect((await spaces()), hasLength(3));
      expect((await note('c2')).spaceId, 'g1');
      expect(find.textContaining('Não foi possível'), findsOneWidget);
    });

    testWidgets('pasta vazia é excluída direto após confirmar', (tester) async {
      await open(tester);
      await startDelete(tester, 'm2');
      await tester.tap(_key('folder-delete-confirm'));
      await tester.pumpAndSettle();
      expect((await spaces()).map((s) => s.id), ['m1', 'g1']);
    });
  });

  group('tamanhos', () {
    testWidgets('360 dp com fonte 1,3x e nomes longos não estoura', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await repo.upsertSpace(const Space(id: 'g2', name: 'Uma pasta com um nome bem comprido mesmo', position: 5));
      await repo.upsertNote(Note(
          id: 'c9',
          title: 'Um caderno com um título muito, muito comprido que não cabe em uma linha só',
          spaceId: 'g2',
          kind: NoteKind.notebook,
          updatedAt: DateTime(2025, 1, 2)));
      await open(tester, size: _small);
      expect(tester.takeException(), isNull);
      await tester.tap(_key('nb-new-folder'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(_key('folder-cancel'));
      await tester.pumpAndSettle();
      await tester.longPress(card('c9'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('tablet com fonte 1,3x não estoura', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await open(tester, size: _tablet);
      expect(tester.takeException(), isNull);
    });
  });
}
