import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_settings_repository.dart';
import 'package:organizacional/data/repository.dart';
import 'package:organizacional/domain/user_settings.dart';

void main() {
  test('emite o padrão e depois cada salvamento', () async {
    final repo = MemorySettingsRepository();
    final seen = <String>[];
    final sub = repo.watchSettings().listen((s) => seen.add(s.theme));
    await Future<void>.delayed(Duration.zero);
    await repo.saveSettings(const UserSettings(theme: 'coral'));
    await Future<void>.delayed(Duration.zero);
    expect(seen, ['violeta', 'coral']);
    await sub.cancel();
  });

  test('failWrites lança RepositoryException e não altera o valor', () async {
    final repo = MemorySettingsRepository(failWrites: true);
    await expectLater(
        repo.saveSettings(const UserSettings(theme: 'coral')), throwsA(isA<RepositoryException>()));
    expect((await repo.watchSettings().first).theme, 'violeta');
  });

  test('ocultar dois dispositivos seguidos mantém os dois e não mexe no tema', () async {
    final repo = MemorySettingsRepository(initial: const UserSettings(theme: 'coral'));
    await Future.wait([repo.setDeviceHidden('a', true), repo.setDeviceHidden('b', true)]);
    final s = await repo.watchSettings().first;
    expect(s.hiddenAlexaDevices.toSet(), {'a', 'b'});
    expect(s.theme, 'coral');
    await repo.setDeviceHidden('a', false);
    expect((await repo.watchSettings().first).hiddenAlexaDevices, ['b']);
    await repo.setTheme('musgo');
    final t = await repo.watchSettings().first;
    expect([t.theme, t.hiddenAlexaDevices], ['musgo', ['b']]);
  });

  test('casa: setHome, setRequireHome e clearHome gravam só os seus campos', () async {
    final repo = MemorySettingsRepository(initial: const UserSettings(theme: 'coral'));
    await repo.setHome(-19.9167, -45.7);
    var s = await repo.watchSettings().first;
    expect([s.homeLat, s.homeLon, s.theme, s.requireHome, s.homeRadiusM], [-19.9167, -45.7, 'coral', true, 50]);
    await repo.setRequireHome(false);
    s = await repo.watchSettings().first;
    expect([s.requireHome, s.homeLat], [false, -19.9167]);
    await repo.clearHome();
    s = await repo.watchSettings().first;
    expect([s.hasHome, s.requireHome, s.theme], [false, false, 'coral']);
  });

  test('casa: com failWrites as três escritas lançam e nada muda', () async {
    final repo = MemorySettingsRepository(failWrites: true);
    await expectLater(repo.setHome(1, 2), throwsA(isA<RepositoryException>()));
    await expectLater(repo.clearHome(), throwsA(isA<RepositoryException>()));
    await expectLater(repo.setRequireHome(false), throwsA(isA<RepositoryException>()));
    final s = await repo.watchSettings().first;
    expect([s.hasHome, s.requireHome], [false, true]);
  });
}
