import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/alexa_repository.dart';
import 'package:organizacional/data/memory_alexa_repository.dart';
import 'package:organizacional/domain/alexa.dart';

void main() {
  test('runCommand devolve o resultado da ponte', () async {
    final repo = MemoryAlexaRepository();
    expect(await runCommand(repo, 'speak', {'text': 'oi'}), 'Feito.');
    expect(repo.sent.single.kind, 'speak');
  });

  test('runCommand com falha da ponte', () async {
    final repo = MemoryAlexaRepository(respondWith: CommandStatus.failed, respondResult: 'rotina não encontrada');
    expect(await runCommand(repo, 'routine', {}), 'Falhou: rotina não encontrada');
  });

  test('runCommand sem resposta dá timeout amigável', () async {
    final repo = MemoryAlexaRepository(respondWith: null);
    expect(await runCommand(repo, 'sync', {}, timeout: const Duration(milliseconds: 20)),
        'Sem resposta da ponte da Alexa.');
  });

  test('watchWakePlans ordena por horário e reflete mudanças', () async {
    const late = WakePlan(id: 'b', label: 'B', days: [1], hour: 9, minute: 0, echoDeviceId: 'E');
    const early = WakePlan(id: 'a', label: 'A', days: [1], hour: 6, minute: 30, echoDeviceId: 'E');
    final repo = MemoryAlexaRepository(plans: const [late]);
    await repo.upsertWakePlan(early);
    expect((await repo.watchWakePlans().first).map((p) => p.id), ['a', 'b']);
    await repo.deleteWakePlan('a');
    expect((await repo.watchWakePlans().first).map((p) => p.id), ['b']);
  });
}
