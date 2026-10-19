import 'package:flutter/material.dart' hide TextBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/note.dart';
import 'package:organizacional/features/notes/note_screen.dart';
import 'package:organizacional/notebook/data/memory_notebook_repository.dart';

import '../../helpers.dart';

/// No uso real o caderno é aberto a partir da aba Notas: o shell (barra de baixo) fica
/// por baixo da rota de tela cheia do caderno. Abrir a nota vinculada dali não pode
/// quebrar (tela vazia por chave duplicada do shell).
void main() {
  testWidgets('Notas do caderno abre a nota vindo da aba Notas (shell por baixo)', (tester) async {
    final repo = MemoryRepository();
    final nb = MemoryNotebookRepository();
    await repo.upsertNote(const Note(id: 'c1', title: 'Cálculo', kind: NoteKind.notebook));
    await nb.addPage('c1');
    await pumpApp(tester, repo, notebookRepo: nb, size: const Size(800, 1300), location: '/notas');
    final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
    router.push('/caderno/c1');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nb-open-notes')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(NoteScreen), findsOneWidget);
    expect(find.text('Notas — Cálculo'), findsWidgets);
    // Voltar leva de novo ao caderno.
    final r2 = GoRouter.of(tester.element(find.byType(NoteScreen)));
    r2.pop();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(NoteScreen), findsNothing);
  });

  testWidgets('na nota do caderno, "Mencionada em" abre outra nota sem quebrar', (tester) async {
    final repo = MemoryRepository();
    final nb = MemoryNotebookRepository();
    await repo.upsertNote(const Note(id: 'c1', title: 'Cálculo', kind: NoteKind.notebook));
    await repo.upsertNote(const Note(id: 'n1', title: 'Notas — Cálculo'));
    await repo.upsertNote(const Note(id: 'n2', title: 'Resumo', body: 'ver [[Notas — Cálculo]]'));
    await nb.addPage('c1');
    await pumpApp(tester, repo, notebookRepo: nb, size: const Size(800, 1300), location: '/notas');
    final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
    router.push('/caderno/c1');
    await tester.pumpAndSettle();
    router.push('/caderno-nota/n1');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.widgetWithText(ListTile, 'Resumo'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.widgetWithText(ListTile, 'Resumo'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Resumo'), findsWidgets);
  });
}
