import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/note.dart';
import 'package:organizacional/domain/space.dart';

import '../helpers.dart';

void main() {
  Future<MemoryRepository> seed() async {
    final repo = MemoryRepository();
    await repo.upsertSpace(const Space(id: 's1', name: 'Cálculo I', kind: SpaceKind.materia));
    await repo.upsertSpace(const Space(id: 's2', name: 'Redes', kind: SpaceKind.materia, position: 1));
    await repo.upsertNote(const Note(id: 'n1', title: 'Cálculo — Resumo', spaceId: 's1'));
    await repo.upsertNote(const Note(id: 'n2', title: 'Redes', spaceId: 's2'));
    await repo.upsertNote(const Note(id: 'n3', title: 'Ideias soltas'));
    return repo;
  }

  testWidgets('busca ignora acento e caixa e abre espaços com resultado', (tester) async {
    await pumpApp(tester, await seed());
    // Sem busca: espaços recolhidos, nota sem espaço visível.
    expect(find.byKey(const ValueKey('tree-note-n1')), findsNothing);
    expect(find.byKey(const ValueKey('tree-note-n3')), findsOneWidget);
    expect(find.text('Sem espaço'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('notes-search')), 'CALC');
    await tester.pumpAndSettle();
    expect(find.text('Cálculo — Resumo'), findsOneWidget);
    expect(find.byKey(const ValueKey('tree-note-n2')), findsNothing);
    expect(find.byKey(const ValueKey('tree-space-s2')), findsNothing);

    await tester.enterText(find.byKey(const Key('notes-search')), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('Nada encontrado.'), findsOneWidget);
  });

  testWidgets('tocar numa nota abre o editor', (tester) async {
    await pumpApp(tester, await seed());
    await tester.tap(find.byKey(const ValueKey('tree-space-s1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tree-note-n1')));
    await tester.pumpAndSettle();
    final title = tester.widget<TextField>(find.byKey(const Key('note-title')));
    expect(title.controller!.text, 'Cálculo — Resumo');
  });

  testWidgets('botão de nova nota cria "Sem título" único e abre', (tester) async {
    final repo = await seed();
    await repo.upsertNote(const Note(id: 'n4', title: 'Sem título'));
    await pumpApp(tester, repo);
    await tester.tap(find.byKey(const Key('tree-new-note')));
    await tester.pumpAndSettle();
    final title = tester.widget<TextField>(find.byKey(const Key('note-title')));
    expect(title.controller!.text, 'Sem título 2');
    expect((await repo.watchNotes().first).length, 5);
  });
}
