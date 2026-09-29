import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/note.dart';

import '../helpers.dart';

void main() {
  testWidgets('edição é salva automaticamente', (tester) async {
    final repo = MemoryRepository();
    await repo.upsertNote(const Note(id: 'n1', title: 'Cálculo'));
    await pumpApp(tester, repo, location: '/nota/n1');
    await tester.enterText(find.byKey(const Key('note-body')), '# Limites');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect((await repo.watchNotes().first).single.body, '# Limites');
  });

  testWidgets('falha ao salvar mantém o texto e mostra aviso até salvar de novo', (tester) async {
    final repo = MemoryRepository();
    await repo.upsertNote(const Note(id: 'n1', title: 'Cálculo'));
    await pumpApp(tester, repo, location: '/nota/n1');
    repo.failWrites = true;
    await tester.enterText(find.byKey(const Key('note-body')), 'derivadas parciais');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.byKey(const Key('save-error')), findsOneWidget);
    expect(find.text('Não foi possível salvar. Suas alterações continuam aqui.'), findsOneWidget);
    expect(find.text('derivadas parciais'), findsOneWidget);

    repo.failWrites = false;
    await tester.enterText(find.byKey(const Key('note-body')), 'derivadas parciais!');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.byKey(const Key('save-error')), findsNothing);
    expect((await repo.watchNotes().first).single.body, 'derivadas parciais!');
  });

  testWidgets('título duplicado mostra aviso específico', (tester) async {
    final repo = MemoryRepository();
    await repo.upsertNote(const Note(id: 'n1', title: 'Cálculo'));
    await repo.upsertNote(const Note(id: 'n2', title: 'Física'));
    await pumpApp(tester, repo, location: '/nota/n2');
    await tester.enterText(find.byKey(const Key('note-title')), '  cálculo ');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('Já existe uma nota com esse título.'), findsOneWidget);
  });

  testWidgets('link [[...]] inexistente cria a nota, abre e mostra o backlink', (tester) async {
    final repo = MemoryRepository();
    await repo.upsertNote(const Note(id: 'n1', title: 'Cálculo', body: 'Ver [[Álgebra]]'));
    await pumpApp(tester, repo, location: '/nota/n1');
    await tester.tap(find.byKey(const Key('toggle-preview')));
    await tester.pumpAndSettle();
    await tester.tapOnText(find.textRange.ofSubstring('Álgebra'));
    await tester.pumpAndSettle();
    final notes = await repo.watchNotes().first;
    expect(notes.map((n) => n.title), containsAll(['Cálculo', 'Álgebra']));
    final title = tester.widget<TextField>(find.byKey(const Key('note-title')));
    expect(title.controller!.text, 'Álgebra');
    expect(find.text('Mencionada em'), findsOneWidget);
    expect(find.text('Cálculo'), findsOneWidget);
  });
}
