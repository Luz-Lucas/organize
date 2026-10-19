import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/ui/org_widgets.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/note.dart';
import 'package:organizacional/domain/space.dart';
import 'package:organizacional/features/fitness/fitness_screen.dart';
import 'package:organizacional/features/shopping/shopping_screen.dart';

import '../helpers.dart';

const _desktopPaths = [
  '/',
  '/agenda',
  '/tarefas',
  '/notas',
  '/academia',
  '/compras',
  '/noticias',
  '/casa',
  '/ajustes',
];

void main() {
  testWidgets('tela larga mostra a barra lateral com os 9 itens e a árvore de notas',
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
    expect(find.text('Organize'), findsOneWidget);
    expect(find.text('Agenda'), findsOneWidget);
    expect(find.byKey(const Key('notes-search')), findsOneWidget);

    await tester.tap(find.byKey(const Key('sidebar-collapse')));
    await tester.pumpAndSettle();
    expect(find.text('Organize'), findsNothing);
    expect(find.text('Agenda'), findsNothing);
    expect(find.byKey(const Key('notes-search')), findsNothing);
    // Os itens continuam clicáveis, só com ícones.
    await tester.tap(find.byKey(const ValueKey('nav-/tarefas')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(PageHeader, 'Tarefas'), findsOneWidget);

    await tester.tap(find.byKey(const Key('sidebar-collapse')));
    await tester.pumpAndSettle();
    expect(find.text('Organize'), findsOneWidget);
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

  testWidgets('celular: Mais lista Academia e Compras no topo e abre as telas', (tester) async {
    await pumpApp(tester, MemoryRepository(), size: const Size(400, 800), location: '/mais');
    final academia = tester.getTopLeft(find.byKey(const ValueKey('more-/academia'))).dy;
    final compras = tester.getTopLeft(find.byKey(const ValueKey('more-/compras'))).dy;
    expect(academia, lessThan(compras));
    expect(compras, lessThan(tester.getTopLeft(find.byKey(const ValueKey('more-/noticias'))).dy));
    expect(find.byIcon(Icons.fitness_center), findsOneWidget);
    expect(find.byIcon(Icons.shopping_cart_outlined), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('more-/academia')));
    await tester.pumpAndSettle();
    expect(find.byType(FitnessScreen), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav-/mais')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('more-/compras')));
    await tester.pumpAndSettle();
    expect(find.byType(ShoppingScreen), findsOneWidget);
  });

  testWidgets('celular: Academia e Compras acendem o item Mais da barra', (tester) async {
    for (final path in ['/academia', '/compras']) {
      await pumpApp(tester, MemoryRepository(), size: const Size(400, 800), location: path);
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.selectedIndex, 4, reason: path);
    }
  });

  testWidgets('tela larga: a barra lateral abre Academia e Compras e marca o item ativo', (tester) async {
    await pumpApp(tester, MemoryRepository(), size: const Size(1000, 800));
    await tester.tap(find.byKey(const ValueKey('nav-/academia')));
    await tester.pumpAndSettle();
    expect(find.byType(FitnessScreen), findsOneWidget);
    expect(find.byIcon(Icons.fitness_center), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('nav-/compras')));
    await tester.pumpAndSettle();
    expect(find.byType(ShoppingScreen), findsOneWidget);
  });

  testWidgets('Notas no celular abre a árvore de notas em tela cheia', (tester) async {
    await pumpApp(tester, MemoryRepository(), size: const Size(400, 800));
    await tester.tap(find.byKey(const ValueKey('nav-/notas')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notes-search')), findsOneWidget);
    expect(find.byKey(const Key('tree-new-note')), findsOneWidget);
  });
}
