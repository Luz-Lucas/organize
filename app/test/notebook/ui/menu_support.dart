import 'package:flutter/material.dart' hide TextBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/ui/notebook_screen.dart';
import 'package:organizacional/ui/org_theme.dart';

import 'ui_support.dart';

/// Abre o menu "Ferramentas" (botão ⋯).
Future<void> openMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('nb-more')));
  await tester.pumpAndSettle();
}

bool menuIsOpen() => find.byKey(const ValueKey('nb-tools-menu')).evaluate().isNotEmpty;

/// Fecha o menu tocando fora dele (se estiver aberto).
Future<void> closeMenu(WidgetTester tester) async {
  if (!menuIsOpen()) return;
  await tester.tapAt(const Offset(8, 8));
  await tester.pumpAndSettle();
}

/// Toca [key] dentro do menu já aberto (rola até ele se preciso).
Future<void> tapInMenu(WidgetTester tester, String key) async {
  final f = find.byKey(ValueKey(key));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

/// Abre o menu, toca [key] e fecha o menu (se o toque não o fechou).
Future<void> tapMenu(WidgetTester tester, String key) async {
  await openMenu(tester);
  await tapInMenu(tester, key);
  await closeMenu(tester);
}

/// Como `pumpNotebook`, mas com favoritos injetáveis.
Future<void> pumpNotebookPrefs(
  WidgetTester tester,
  FakeSession session, {
  Size size = const Size(800, 1300),
  Map<String, dynamic> prefs = const {},
  Future<void> Function(Map<String, dynamic>)? onPrefsChanged,
}) async {
  await setSurface(tester, size);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildOrgTheme(orgThemes.first, googleFonts: false),
      home: NotebookScreen(
        noteId: 'n1',
        session: session,
        title: 'Meu caderno',
        prefs: prefs,
        onPrefsChanged: onPrefsChanged,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}
