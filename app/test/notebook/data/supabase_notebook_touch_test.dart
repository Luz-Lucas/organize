// `notes.updated_at` é emitido pelo realtime para todas as telas que listam notas.
// Tocar a cada save (1,5 s) faz o app inteiro reconstruir durante a escrita;
// o repositório toca no máximo a cada 60 s e uma vez ao sair do caderno.
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/data/supabase_notebook_repository.dart';

import 'fake_postgrest.dart';
import 'notebook_test_support.dart';

void main() {
  late FakePostgrest server;
  late SupabaseNotebookRepository repo;
  late DateTime now;

  setUp(() {
    server = FakePostgrest();
    now = DateTime.utc(2026, 10, 13, 10);
    repo = SupabaseNotebookRepository(server.client(), now: () => now);
    server.notes['n1'] = {'id': 'n1', 'title': 'Caderno', 'kind': 'notebook'};
    server.notes['n2'] = {'id': 'n2', 'title': 'Outro', 'kind': 'notebook'};
  });

  int touches([String note = 'n1']) =>
      server.sent.where((s) => s.method == 'PATCH' && s.path.endsWith('/notes') && s.query['id'] == 'eq.$note').length;

  test('o 1º save toca a nota; os seguintes dentro de 60 s não', () async {
    final p = await repo.addPage('n1', id: 'p-a');
    var page = await repo.savePage(p.copyWith(data: enc(['a'])));
    expect(touches(), 1);
    for (var i = 0; i < 5; i++) {
      now = now.add(const Duration(seconds: 2));
      page = await repo.savePage(page.copyWith(data: enc(['a', for (var k = 0; k <= i; k++) 'b$k'])));
    }
    expect(touches(), 1, reason: '5 saves em 10 s: só o primeiro toca');
  });

  test('depois de 60 s o próximo save volta a tocar', () async {
    final p = await repo.addPage('n1', id: 'p-a');
    var page = await repo.savePage(p.copyWith(data: enc(['a'])));
    now = now.add(const Duration(seconds: 61));
    page = await repo.savePage(page.copyWith(data: enc(['a', 'b'])));
    expect(touches(), 2);
  });

  test('o limite é por caderno', () async {
    final a = await repo.addPage('n1', id: 'p-a');
    final b = await repo.addPage('n2', id: 'p-b');
    await repo.savePage(a.copyWith(data: enc(['a'])));
    await repo.savePage(b.copyWith(data: enc(['b'])));
    expect(touches('n1'), 1);
    expect(touches('n2'), 1);
  });

  test('touchNote toca de verdade só se algum toque foi adiado', () async {
    final p = await repo.addPage('n1', id: 'p-a');
    var page = await repo.savePage(p.copyWith(data: enc(['a'])));
    await repo.touchNote('n1');
    expect(touches(), 1, reason: 'nada adiado: não repete');
    now = now.add(const Duration(seconds: 3));
    page = await repo.savePage(page.copyWith(data: enc(['a', 'b'])));
    expect(touches(), 1);
    await repo.touchNote('n1');
    expect(touches(), 2, reason: 'ao sair, o toque adiado acontece');
    await repo.touchNote('n1');
    expect(touches(), 2);
  });

  test('um toque que falhou não marca o caderno como tocado', () async {
    final p = await repo.addPage('n1', id: 'p-a');
    server.failWhen = (s) => s.path.endsWith('/notes');
    var page = await repo.savePage(p.copyWith(data: enc(['a'])));
    server.failWhen = null;
    now = now.add(const Duration(seconds: 2));
    page = await repo.savePage(page.copyWith(data: enc(['a', 'b'])));
    expect(touches(), 2, reason: 'a falha não conta como toque: o save seguinte tenta de novo');
  });
}
