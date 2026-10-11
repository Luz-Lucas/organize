import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/app/providers.dart';
import 'package:organizacional/app_icon/app_icon.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/data/memory_settings_repository.dart';
import 'package:organizacional/domain/user_settings.dart';

import '../helpers.dart';

class FakeIconService implements AppIconService {
  FakeIconService({this.currentId, this.failSet = false});
  String? currentId;
  final bool failSet;
  final sets = <String>[];

  @override
  Future<String?> current() async => currentId;

  @override
  Future<void> set(String themeId) async {
    sets.add(themeId);
    if (failSet) throw Exception('falha no canal');
    currentId = themeId;
  }
}

ProviderContainer _container(MemorySettingsRepository settings, AppIconService icon) {
  final c = ProviderContainer(overrides: [
    settingsRepositoryProvider.overrideWithValue(settings),
    appIconServiceProvider.overrideWithValue(icon),
  ]);
  addTearDown(c.dispose);
  c.listen(appIconSyncProvider, (_, _) {});
  return c;
}

void main() {
  test('mudar o tema de violeta para coral chama set(coral) uma vez', () async {
    final settings = MemorySettingsRepository();
    final icon = FakeIconService(currentId: 'violeta');
    _container(settings, icon);
    await pumpEventQueue();
    expect(icon.sets, isEmpty);

    await settings.setTheme('coral');
    await pumpEventQueue();
    expect(icon.sets, ['coral']);

    // Outro ajuste que não muda o tema não chama de novo.
    await settings.setDeviceHidden('d1', true);
    await pumpEventQueue();
    expect(icon.sets, ['coral']);
  });

  test('iniciar com ícone coral e tema coral não chama set', () async {
    final settings = MemorySettingsRepository(initial: UserSettings.fromMap({'theme': 'coral'}));
    final icon = FakeIconService(currentId: 'coral');
    _container(settings, icon);
    await pumpEventQueue();
    expect(icon.sets, isEmpty);
  });

  test('ao iniciar com ícone diferente do tema, ajusta uma vez', () async {
    final settings = MemorySettingsRepository(initial: UserSettings.fromMap({'theme': 'cacto'}));
    final icon = FakeIconService(currentId: 'violeta');
    _container(settings, icon);
    await pumpEventQueue();
    expect(icon.sets, ['cacto']);
  });

  test('set lançando exceção é ignorado e o app segue funcionando', () async {
    final settings = MemorySettingsRepository();
    final icon = FakeIconService(currentId: 'violeta', failSet: true);
    _container(settings, icon);
    await settings.setTheme('coral');
    await pumpEventQueue();
    expect(icon.sets, ['coral']);
    await settings.setTheme('bronze');
    await pumpEventQueue();
    expect(icon.sets, ['coral', 'bronze']);
  });

  test('NoopAppIconService não faz nada', () async {
    const noop = NoopAppIconService();
    expect(await noop.current(), isNull);
    await noop.set('coral');
  });

  testWidgets('pumpApp usa NoopAppIconService por padrão', (tester) async {
    await pumpApp(tester, MemoryRepository());
    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    expect(container.read(appIconServiceProvider), isA<NoopAppIconService>());
  });

  testWidgets('Ajustes não mostra a nota do ícone fora do Android', (tester) async {
    await pumpApp(tester, MemoryRepository(), location: '/ajustes', size: const Size(1000, 1400));
    expect(find.textContaining('O ícone do app muda junto com o tema'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('Ajustes mostra a nota do ícone no Android', (tester) async {
    await pumpApp(tester, MemoryRepository(), location: '/ajustes', size: const Size(1000, 1400));
    expect(find.textContaining('O ícone do app muda junto com o tema'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
