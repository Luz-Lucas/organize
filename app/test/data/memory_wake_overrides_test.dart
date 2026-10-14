import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_alexa_repository.dart';
import 'package:organizacional/data/repository.dart';
import 'package:organizacional/domain/alexa.dart';
import 'package:organizacional/domain/wake_override.dart';

void main() {
  const plan = WakePlan(id: 'p1', label: 'A', days: [1], hour: 7, minute: 0, echoDeviceId: 'E');
  final d = DateTime(2026, 9, 29);

  test('setOverride grava, substitui a mesma data e o stream reflete', () async {
    final repo = MemoryAlexaRepository(plans: const [plan]);
    expect(await repo.watchOverrides().first, isEmpty);
    await repo.setOverride(WakeOverride.skip('p1', d));
    await repo.setOverride(WakeOverride.at('p1', d, 6, 30)); // mesma data: substitui
    await repo.setOverride(WakeOverride.skip('p1', DateTime(2026, 10, 1)));
    final list = await repo.watchOverrides().first;
    expect(list.map((o) => (o.dateKey, o.skip, o.hour, o.minute)), [
      ('2026-09-29', false, 6, 30),
      ('2026-10-01', true, null, null),
    ]);
  });

  test('clearOverride apaga só aquela data e é idempotente', () async {
    final repo = MemoryAlexaRepository(plans: const [plan]);
    await repo.setOverride(WakeOverride.skip('p1', d));
    await repo.setOverride(WakeOverride.skip('p1', DateTime(2026, 10, 1)));
    await repo.clearOverride('p1', d);
    await repo.clearOverride('p1', d);
    expect((await repo.watchOverrides().first).map((o) => o.dateKey), ['2026-10-01']);
  });

  test('apagar o despertar apaga suas exceções (como a cascata do banco)', () async {
    final repo = MemoryAlexaRepository(plans: const [plan]);
    await repo.setOverride(WakeOverride.skip('p1', d));
    await repo.deleteWakePlan('p1');
    expect(await repo.watchOverrides().first, isEmpty);
  });

  test('escritas falham como RepositoryException quando a conexão cai', () async {
    final repo = MemoryAlexaRepository(plans: const [plan])..failWrites = true;
    await expectLater(repo.setOverride(WakeOverride.skip('p1', d)), throwsA(isA<RepositoryException>()));
    await expectLater(repo.clearOverride('p1', d), throwsA(isA<RepositoryException>()));
  });
}
