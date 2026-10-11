import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/data/memory_settings_repository.dart';
import 'package:organizacional/domain/user_settings.dart';
import 'package:organizacional/ui/org_theme.dart';

import '../helpers.dart';

void main() {
  testWidgets('mostra os 10 temas e trocar para coral salva e muda o tema', (tester) async {
    final settings = MemorySettingsRepository();
    await pumpApp(tester, MemoryRepository(),
        location: '/ajustes', settings: settings, size: const Size(1000, 1400));
    for (final id in themeIds) {
      expect(find.byKey(ValueKey('theme-$id')), findsOneWidget, reason: id);
    }
    expect(Theme.of(tester.element(find.byType(Scaffold).first)).colorScheme.primary,
        orgThemeById('violeta').accentDeep);

    await tester.tap(find.byKey(const ValueKey('theme-coral')));
    await tester.pumpAndSettle();

    expect((await settings.watchSettings().first).theme, 'coral');
    expect(Theme.of(tester.element(find.byType(Scaffold).first)).colorScheme.primary,
        orgThemeById('coral').accentDeep);
  });

  testWidgets('tema salvo inexistente abre em Violeta', (tester) async {
    final settings = MemorySettingsRepository(initial: UserSettings.fromMap({'theme': 'neon'}));
    await pumpApp(tester, MemoryRepository(), settings: settings);
    expect(Theme.of(tester.element(find.byType(Scaffold).first)).colorScheme.primary,
        orgThemeById('violeta').accentDeep);
  });

  testWidgets('falha ao salvar o tema mostra aviso e mantém o tema atual', (tester) async {
    final settings = MemorySettingsRepository(failWrites: true);
    await pumpApp(tester, MemoryRepository(),
        location: '/ajustes', settings: settings, size: const Size(1000, 1400));
    await tester.tap(find.byKey(const ValueKey('theme-coral')));
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível salvar o tema.'), findsOneWidget);
    expect(Theme.of(tester.element(find.byType(Scaffold).first)).colorScheme.primary,
        orgThemeById('violeta').accentDeep);
  });
}
