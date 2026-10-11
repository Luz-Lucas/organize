import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/ui/org_widgets.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/note.dart';
import 'package:organizacional/domain/space.dart';

import '../helpers.dart';

const _desktopPaths = ['/', '/agenda', '/tarefas', '/notas', '/noticias', '/casa', '/ajustes'];

void main() {
  testWidgets('tela larga mostra a barra lateral com os 7 itens e a árvore de notas',
      (tester) async {
    final repo = MemoryRepository();
    await repo.upsertSpace(const Space(id: 's1', name: 'Cálculo I', kind: SpaceKind.materia));
    await repo.upsertNote(const Note(id: 'n1', title: 'Redes'));
    await pumpApp(tester, repo, size: const Size(1000, 800));
    expect(find.byType(NavigationBar), findsNothing);
    for (final p in _desktopPaths) {
      expect(find.byKey(ValueKey('nav-$p')), findsOneWidget, reason: p);
    }
    expect(find.byKey(const Key('notes-search')), findsOneWidget);
    expect(find.byKey(const ValueKey('tree-space-s1')), findsOneWidget);
    expect(find.byKey(const ValueKey('tree-note-n1')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav-/tarefas')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(PageHeader, 'Tarefas'), findsOneWidget);
  });

  testWidgets('recolher esconde rótulos e a árvore; expandir traz de volta', (tester) async {
    await pumpApp(tester, MemoryRepository(), size: const Size(1000, 800));
    expect(find.text('Organizacional'), findsOneWidget);
    expect(find.text('Agenda'), findsOneWidget);
    expect(find.byKey(const Key('notes-search')), findsOneWidget);

    await tester.tap(find.byKey(const Key('sidebar-collapse')));
    await tester.pumpAndSettle();
    expect(find.text('Organizacional'), findsNothing);
    expect(find.text('Agenda'), findsNothing);
    expect(find.byKey(const Key('notes-search')), findsNothing);
    // Os itens continuam clicáveis, só com ícones.
    await tester.tap(find.byKey(const ValueKey('nav-/tarefas')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(PageHeader, 'Tarefas'), findsOneWidget);

    await tester.tap(find.byKey(const Key('sidebar-collapse')));
    await tester.pumpAndSettle();
    expect(find.text('Organizacional'), findsOneWidget);
  });

  testWidgets('celular mostra 5 destinos e Mais abre Notícias, Casa e Ajustes', (tester) async {
    await pumpApp(tester, MemoryRepository(), size: const Size(400, 800));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(5));
    for (final label in ['Início', 'Agenda', 'Tarefas', 'Notas', 'Mais']) {
      expect(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
          findsOneWidget,
          reason: label);
    }
    await tester.tap(find.byKey(const ValueKey('nav-/mais')));
    await tester.pumpAndSettle();
    expect(find.text('Notícias'), findsOneWidget);
    expect(find.text('Casa'), findsOneWidget);
    expect(find.text('Ajustes'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('more-/ajustes')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('theme-violeta')), findsOneWidget);
  });

  testWidgets('Notas no celular abre a árvore de notas em tela cheia', (tester) async {
    await pumpApp(tester, MemoryRepository(), size: const Size(400, 800));
    await tester.tap(find.byKey(const ValueKey('nav-/notas')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notes-search')), findsOneWidget);
    expect(find.byKey(const Key('tree-new-note')), findsOneWidget);
  });
}
