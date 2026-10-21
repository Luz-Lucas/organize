import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/local_alexa_repository.dart';
import 'package:organizacional/data/memory_alexa_repository.dart';
import 'package:organizacional/domain/alexa.dart';
import 'package:organizacional/domain/wake_override.dart';
import 'package:organizacional/sync/local_store.dart';

void main() {
  const plan = WakePlan(id: 'p1', label: 'A', days: [1], hour: 7, minute: 0, echoDeviceId: 'E');
  const plan2 = WakePlan(id: 'p2', label: 'B', days: [2], hour: 6, minute: 30, echoDeviceId: 'E');
  final d = DateTime(2026, 9, 29);

  late LocalStore store;
  late MemoryAlexaRepository online;
  late LocalFirstAlexaRepository repo;

  setUp(() {
    store = LocalStore.inMemory();
    online = MemoryAlexaRepository(
      devices: const [AlexaDevice(id: 'E', name: 'Echo', kind: 'echo', operations: [])],
    );
    repo = LocalFirstAlexaRepository(store, online);
  });
  tearDown(() => store.close());

  test('despertares: grava na hora, ordena por horário e apaga', () async {
    await repo.upsertWakePlan(plan);
    await repo.upsertWakePlan(plan2);
    expect((await repo.watchWakePlans().first).map((p) => p.id), ['p2', 'p1']);
    expect(store.pendingOutbox().map((e) => e.tbl).toSet(), {'wake_plans'});
    await repo.deleteWakePlan('p2');
    expect((await repo.watchWakePlans().first).map((p) => p.id), ['p1']);
  });

  test('exceções: a mesma data substitui e a chave local é plano|data', () async {
    await repo.upsertWakePlan(plan);
    await repo.setOverride(WakeOverride.skip('p1', d));
    await repo.setOverride(WakeOverride.at('p1', d, 6, 30));
    await repo.setOverride(WakeOverride.skip('p1', DateTime(2026, 10, 1)));
    final list = await repo.watchOverrides().first;
    expect(list.map((o) => (o.dateKey, o.skip, o.hour, o.minute)), [
      ('2026-09-29', false, 6, 30),
      ('2026-10-01', true, null, null),
    ]);
    expect(await store.get('wake_overrides', 'p1|2026-09-29'), isNotNull);
  });

  test('clearOverride apaga só aquela data e é idempotente', () async {
    await repo.upsertWakePlan(plan);
    await repo.setOverride(WakeOverride.skip('p1', d));
    await repo.setOverride(WakeOverride.skip('p1', DateTime(2026, 10, 1)));
    await repo.clearOverride('p1', d);
    await repo.clearOverride('p1', d);
    expect((await repo.watchOverrides().first).map((o) => o.dateKey), ['2026-10-01']);
  });

  test('apagar o despertar leva as exceções dele (como a cascata do banco), exceções antes do plano na fila', () async {
    await repo.upsertWakePlan(plan);
    await repo.upsertWakePlan(plan2);
    await repo.setOverride(WakeOverride.skip('p1', d));
    await repo.setOverride(WakeOverride.skip('p2', d));
    store.ackOutbox(store.pendingOutbox());
    await repo.deleteWakePlan('p1');
    expect((await repo.watchOverrides().first).map((o) => o.planId), ['p2']);
    final queue = store.pendingOutbox();
    expect([for (final e in queue) '${e.tbl}:${e.id}'], ['wake_overrides:p1|2026-09-29', 'wake_plans:p1']);
  });

  test('dispositivos, rotinas, status e comandos continuam no repositório online', () async {
    expect((await repo.watchDevices().first).single.id, 'E');
    final out = await repo.sendCommand('ping', const {});
    expect(online.sent.single.kind, 'ping');
    expect(out, isNotEmpty);
  });
}
