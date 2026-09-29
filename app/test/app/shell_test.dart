import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_repository.dart';

import '../helpers.dart';

void main() {
  testWidgets('tela larga usa NavigationRail e navega', (tester) async {
    await pumpApp(tester, MemoryRepository(), size: const Size(1000, 800));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(find.text('Tarefas'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Tarefas'), findsOneWidget);
  });

  testWidgets('tela de celular usa NavigationBar inferior', (tester) async {
    await pumpApp(tester, MemoryRepository(), size: const Size(400, 800));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    await tester.tap(find.text('Espaços'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Espaços'), findsOneWidget);
  });
}
