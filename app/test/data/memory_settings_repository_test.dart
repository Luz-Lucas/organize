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
    await repo.setHome(-19.93, -43.94);
    var s = await repo.watchSettings().first;
    expect([s.homeLat, s.homeLon, s.theme, s.requireHome, s.homeRadiusM], [-19.93, -43.94, 'coral', true, 50]);
    await repo.setRequireHome(false);
    s = await repo.watchSettings().first;
    expect([s.requireHome, s.homeLat], [false, -19.93]);
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

  test('setNotebookPrefs grava só os favoritos do caderno', () async {
    final repo = MemorySettingsRepository(initial: const UserSettings(theme: 'coral'));
    await repo.setNotebookPrefs({'v': 1, 'compact': false});
    final s = await repo.watchSettings().first;
    expect([s.notebookPrefs, s.theme], [{'v': 1, 'compact': false}, 'coral']);
    repo.failWrites = true;
    await expectLater(repo.setNotebookPrefs({'v': 1}), throwsA(isA<RepositoryException>()));
  });

  test('lembretes: chaves, Echo e não perturbe gravam só as suas colunas', () async {
    final repo = MemorySettingsRepository(initial: const UserSettings(theme: 'coral'));
    await repo.setRemindersPhone(false);
    await repo.setRemindersAlexa(false);
    await repo.setReminderEcho('ABC');
    await repo.setDnd(enabled: false, start: 22 * 60, end: 7 * 60);
    var s = await repo.watchSettings().first;
    expect([s.remindersPhone, s.remindersAlexa, s.reminderEcho, s.dndEnabled, s.dndStart, s.dndEnd, s.theme],
        [false, false, 'ABC', false, 22 * 60, 7 * 60, 'coral']);
    await repo.setDnd(start: 23 * 60);
    await repo.setReminderEcho(null);
    s = await repo.watchSettings().first;
    expect([s.dndEnabled, s.dndStart, s.dndEnd, s.reminderEcho], [false, 23 * 60, 7 * 60, null]);
    repo.failWrites = true;
    await expectLater(repo.setRemindersPhone(true), throwsA(isA<RepositoryException>()));
  });
}
