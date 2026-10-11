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
}
