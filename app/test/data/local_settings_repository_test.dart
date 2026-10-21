import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/local_settings_repository.dart';
import 'package:organizacional/sync/local_store.dart';

void main() {
  late LocalStore store;
  late LocalFirstSettingsRepository repo;

  setUp(() {
    store = LocalStore.inMemory();
    repo = LocalFirstSettingsRepository(store, 'u1');
  });
  tearDown(() => store.close());

  test('sem linha emite o padrão e depois cada gravação, na hora', () async {
    final seen = <String>[];
    final sub = repo.watchSettings().listen((s) => seen.add(s.theme));
    await Future<void>.delayed(Duration.zero);
    await repo.setTheme('coral');
    await Future<void>.delayed(Duration.zero);
    expect(seen, ['violeta', 'coral']);
    await sub.cancel();
  });

  test('cada escrita grava só as suas colunas na fila (upsert parcial por user_id)', () async {
    await repo.setTheme('coral');
    await repo.setRequireHome(false);
    final queue = store.pendingOutbox();
    expect(queue.every((e) => e.tbl == 'user_settings' && e.id == 'u1'), isTrue);
    // as duas escritas seguidas viram um item só, com as duas colunas (e o carimbo)
    expect(queue, hasLength(1));
    expect(queue.single.data!.keys.toSet(), {'user_id', 'theme', 'require_home', 'client_updated_at'});
    final s = await repo.watchSettings().first;
    expect([s.theme, s.requireHome], ['coral', false]);
  });

  test('ocultar dois dispositivos seguidos mantém os dois e não mexe no tema', () async {
    await repo.setTheme('coral');
    await Future.wait([repo.setDeviceHidden('a', true), repo.setDeviceHidden('b', true)]);
    var s = await repo.watchSettings().first;
    expect(s.hiddenAlexaDevices.toSet(), {'a', 'b'});
    expect(s.theme, 'coral');
    await repo.setDeviceHidden('a', false);
    s = await repo.watchSettings().first;
    expect(s.hiddenAlexaDevices, ['b']);
  });

  test('casa: setHome, setRequireHome e clearHome gravam só os seus campos', () async {
    await repo.setTheme('coral');
    await repo.setHome(-19.93, -43.94);
    var s = await repo.watchSettings().first;
    expect([s.homeLat, s.homeLon, s.theme, s.requireHome], [-19.93, -43.94, 'coral', true]);
    await repo.setRequireHome(false);
    await repo.clearHome();
    s = await repo.watchSettings().first;
    expect([s.hasHome, s.requireHome, s.theme], [false, false, 'coral']);
  });

  test('caderno, lembretes e não perturbe', () async {
    await repo.setNotebookPrefs({'v': 1, 'compact': false});
    await repo.setRemindersPhone(false);
    await repo.setRemindersAlexa(false);
    await repo.setReminderEcho('ABC');
    await repo.setDnd(enabled: false, start: 22 * 60, end: 7 * 60);
    var s = await repo.watchSettings().first;
    expect(s.notebookPrefs, {'v': 1, 'compact': false});
    expect([s.remindersPhone, s.remindersAlexa, s.reminderEcho, s.dndEnabled, s.dndStart, s.dndEnd],
        [false, false, 'ABC', false, 22 * 60, 7 * 60]);
    await repo.setDnd(start: 23 * 60);
    await repo.setReminderEcho(null);
    s = await repo.watchSettings().first;
    expect([s.dndEnabled, s.dndStart, s.dndEnd, s.reminderEcho], [false, 23 * 60, 7 * 60, null]);
  });

  test('ignora a linha de outro usuário e o que chega da nuvem aparece', () async {
    await store.applyRemoteUpsert('user_settings', {'user_id': 'outro', 'theme': 'musgo'});
    expect((await repo.watchSettings().first).theme, 'violeta');
    await store.applyRemoteUpsert('user_settings', {'user_id': 'u1', 'theme': 'safira', 'dnd_start': '22:00:00'});
    final s = await repo.watchSettings().first;
    expect([s.theme, s.dndStart], ['safira', 22 * 60]);
  });
}
