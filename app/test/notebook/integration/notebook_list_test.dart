import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/note.dart';
import 'package:organizacional/domain/space.dart';
import 'package:organizacional/notebook/data/memory_notebook_repository.dart';

import '../../helpers.dart';
import '../data/notebook_test_support.dart';

const _phone = Size(400, 800);

void main() {
  late MemoryRepository repo;
  late MemoryNotebookRepository nb;

  setUp(() async {
    repo = MemoryRepository();
    nb = MemoryNotebookRepository();
    await repo.upsertNote(const Note(id: 'c1', title: 'Biologia', kind: NoteKind.notebook));
    await repo.upsertNote(const Note(id: 'c2', title: 'Rascunhos', kind: NoteKind.notebook));
    await repo.upsertNote(const Note(id: 't1', title: 'Resumo', body: 'fotossíntese básica'));
    final p = await nb.addPage('c1');
    await nb.savePage(p.copyWith(data: enc(['a', 'b'])));
    await nb.addPage('c2');
  });

  group('lista', () {
    testWidgets('caderno tem ícone próprio; nota de texto mantém o ícone de documento', (tester) async {
      await pumpApp(tester, repo, notebookRepo: nb, size: _phone, location: '/notas');
      expect(find.byKey(const ValueKey('tree-note-icon-c1')), findsOneWidget);
      final nbIcon = tester.widget<Icon>(find.byKey(const ValueKey('tree-note-icon-c1')));
      final txtIcon = tester.widget<Icon>(find.byKey(const ValueKey('tree-note-icon-t1')));
      expect(nbIcon.icon, isNot(txtIcon.icon));
      expect(txtIcon.icon, Icons.description_outlined);
    });

    testWidgets('miniatura da 1ª página aparece no caderno com tinta e some no caderno vazio', (tester) async {
      await pumpApp(tester, repo, notebookRepo: nb, size: _phone, location: '/notas');
      expect(find.byKey(const ValueKey('notebook-thumb-c1')), findsOneWidget);
      expect(find.byKey(const ValueKey('notebook-thumb-c2')), findsNothing);
      expect(find.byKey(const ValueKey('notebook-thumb-t1')), findsNothing);
    });

    testWidgets('a miniatura também aparece na lista do espaço', (tester) async {
      await repo.upsertSpace(const Space(id: 's1', name: 'Bio', kind: SpaceKind.materia));
      await repo.upsertNote(const Note(id: 'c3', title: 'Bio caderno', kind: NoteKind.notebook, spaceId: 's1'));
      final p = await nb.addPage('c3');
      await nb.savePage(p.copyWith(data: enc(['x'])));
      await pumpApp(tester, repo, notebookRepo: nb, size: _phone, location: '/espacos/s1');
      expect(find.byKey(const ValueKey('notebook-thumb-c3')), findsOneWidget);
      expect(find.byKey(const ValueKey('space-note-icon-c3')), findsOneWidget);
    });
  });

  group('busca', () {
    testWidgets('acha o caderno pelo texto reconhecido (sem acento e sem caixa)', (tester) async {
      final pages = await nb.listPages('c2');
      nb.setRecognizedText(pages.first.id, 'Lista de compras: FOTOSSÍNTESE e mitose');
      await pumpApp(tester, repo, notebookRepo: nb, size: _phone, location: '/notas');
      await tester.enterText(find.byKey(const Key('notes-search')), 'fotossintese');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tree-note-c2')), findsOneWidget); // texto reconhecido
      expect(find.byKey(const ValueKey('tree-note-t1')), findsOneWidget); // corpo da nota de texto
      expect(find.byKey(const ValueKey('tree-note-c1')), findsNothing);
    });

    testWidgets('título continua vindo primeiro e sem resultado mostra "Nada encontrado."', (tester) async {
      await pumpApp(tester, repo, notebookRepo: nb, size: _phone, location: '/notas');
      await tester.enterText(find.byKey(const Key('notes-search')), 'xyzzy');
      await tester.pumpAndSettle();
      expect(find.text('Nada encontrado.'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('notes-search')), 'biolo');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tree-note-c1')), findsOneWidget);
    });
  });
}
