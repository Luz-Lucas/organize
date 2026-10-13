import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/repository.dart';
import 'package:organizacional/notebook/core/notebook_core.dart';
import 'package:organizacional/notebook/data/notebook_page.dart';
import 'package:organizacional/notebook/data/notebook_repository.dart';
import 'package:organizacional/notebook/data/supabase_notebook_repository.dart';

import 'fake_postgrest.dart';
import 'notebook_test_support.dart';

void main() {
  late FakePostgrest server;
  late SupabaseNotebookRepository repo;
  setUp(() {
    server = FakePostgrest();
    repo = SupabaseNotebookRepository(server.client());
    server.notes['n1'] = {'id': 'n1', 'title': 'Caderno', 'kind': 'notebook'};
  });

  List<Sent> writes() => [for (final s in server.sent) if (s.method != 'GET') s];

  test('addPage insere no fim com idx = último + 1 e nunca usa on_conflict', () async {
    final a = await repo.addPage('n1', id: 'p-a');
    final b = await repo.addPage('n1', id: 'p-b', background: PageBackground.grid);
    expect([a.idx, b.idx], [0, 1]);
    expect(b.background, PageBackground.grid);
    expect(writes().map((s) => s.method).toSet(), {'POST'});
    expect(server.sent.every((s) => !s.query.containsKey('on_conflict')), isTrue);
    expect(writes().every((s) => !(s.prefer ?? '').contains('resolution=')), isTrue);
  });

  test('addPage com id que já existe devolve a existente sem inserir de novo', () async {
    await repo.addPage('n1', id: 'p-a');
    final before = writes().length;
    final again = await repo.addPage('n1', id: 'p-a');
    expect(again.id, 'p-a');
    expect(writes().length, before);
  });

  test('addPage at=1 desloca as seguintes sem violar a unique imediata', () async {
    await repo.addPage('n1', id: 'p-a');
    await repo.addPage('n1', id: 'p-b');
    await repo.addPage('n1', id: 'p-c', at: 1);
    final pages = await repo.listPages('n1');
    expect(pages.map((p) => p.id), ['p-a', 'p-c', 'p-b']);
    expect(pages.map((p) => p.idx), [0, 1, 2]);
  });

  test('savePage atualiza com version = v condicional, sobe a versão e toca a nota', () async {
    final p = await repo.addPage('n1', id: 'p-a');
    final saved = await repo.savePage(p.copyWith(data: enc(['a'])));
    expect(saved.version, 1);
    final patch = writes().where((s) => s.method == 'PATCH' && s.path.endsWith('/note_pages')).single;
    expect(patch.query['id'], 'eq.p-a');
    expect(patch.query['version'], 'eq.0');
    expect((patch.body as Map)['version'], 1);
    final touch = writes().where((s) => s.path.endsWith('/notes')).single;
    expect(touch.query['id'], 'eq.n1');
    expect((touch.body as Map).containsKey('updated_at'), isTrue);
  });

  test('conflito: 0 linhas afetadas -> relê, mescla e grava de novo sem perder traços', () async {
    final base = await repo.addPage('n1', id: 'p-a');
    // O outro aparelho grava a1/a2 (v0 -> v1) antes do nosso save.
    await SupabaseNotebookRepository(server.client()).savePage(base.copyWith(data: enc(['a1', 'a2'])));
    final merged = await repo.savePage(base.copyWith(data: enc(['b1'])));
    expect(idsOf(merged.data), {'a1', 'a2', 'b1'});
    expect(merged.version, 2);
    expect(idsOf(server.pages['p-a']!['data'] as String), {'a1', 'a2', 'b1'});
    final patches = writes().where((s) => s.method == 'PATCH' && s.path.endsWith('/note_pages')).toList();
    expect(patches.map((s) => s.query['version']), ['eq.0', 'eq.0', 'eq.1']);
  });

  test('conflito repetido (corrida no meio) continua tentando até conseguir', () async {
    final base = await repo.addPage('n1', id: 'p-a');
    var raced = 0;
    server.beforeRequest = (s) {
      // Antes de cada um dos 2 primeiros updates, outro aparelho grava mais um traço.
      if (s.method == 'PATCH' && s.path.endsWith('/note_pages') && raced < 2) {
        raced++;
        final row = server.pages['p-a']!;
        final cur = decodePage(row['data'] as String);
        row['data'] = encodePage(cur.withStroke(stroke('r$raced')));
        row['version'] = (row['version'] as int) + 1;
      }
    };
    final merged = await repo.savePage(base.copyWith(data: enc(['mine'])));
    expect(idsOf(merged.data), {'mine', 'r1', 'r2'});
    expect(idsOf(server.pages['p-a']!['data'] as String), {'mine', 'r1', 'r2'});
  });

  test('savePage de página apagada em outro aparelho recria no fim com a tinta', () async {
    final a = await repo.addPage('n1', id: 'p-a');
    await repo.addPage('n1', id: 'p-b');
    server.pages.remove('p-a');
    server.pages['p-b']!['idx'] = 0;
    final back = await repo.savePage(a.copyWith(data: enc(['x'])));
    expect(back.idx, 1);
    expect(idsOf(server.pages['p-a']!['data'] as String), {'x'});
  });

  test('o toque na nota que falha não derruba o salvamento', () async {
    final p = await repo.addPage('n1', id: 'p-a');
    server.failWhen = (s) => s.path.endsWith('/notes');
    final saved = await repo.savePage(p.copyWith(data: enc(['a'])));
    expect(saved.version, 1);
  });

  test('erro de servidor vira RepositoryException', () async {
    final p = await repo.addPage('n1', id: 'p-a');
    server.failWhen = (s) => s.method == 'PATCH';
    await expectLater(repo.savePage(p.copyWith(data: enc(['a']))), throwsA(isA<RepositoryException>()));
  });

  test('deletePage apaga e reindexa em ordem que nunca colide', () async {
    for (final id in ['p-a', 'p-b', 'p-c', 'p-d']) {
      await repo.addPage('n1', id: id);
    }
    await repo.deletePage('p-b');
    final pages = await repo.listPages('n1');
    expect(pages.map((p) => p.id), ['p-a', 'p-c', 'p-d']);
    expect(pages.map((p) => p.idx), [0, 1, 2]);
  });

  test('duplicatePage copia fundo e tinta logo depois da original', () async {
    final a = await repo.addPage('n1', id: 'p-a', background: PageBackground.dots);
    await repo.addPage('n1', id: 'p-b');
    await repo.savePage(a.copyWith(data: enc(['s1'])));
    final copy = await repo.duplicatePage('p-a');
    final pages = await repo.listPages('n1');
    expect(pages.map((p) => p.id), ['p-a', copy.id, 'p-b']);
    expect(copy.background, PageBackground.dots);
    expect(idsOf(pages[1].data), {'s1'});
    expect(pages[1].version, 0);
  });

  test('reorder troca posições (ciclo) sem violar a unique imediata', () async {
    for (final id in ['p-a', 'p-b', 'p-c']) {
      await repo.addPage('n1', id: id);
    }
    await repo.reorder('n1', ['p-c', 'p-a', 'p-b']);
    expect((await repo.listPages('n1')).map((p) => p.id), ['p-c', 'p-a', 'p-b']);
    await repo.reorder('n1', ['p-b', 'p-a', 'p-c']);
    expect((await repo.listPages('n1')).map((p) => p.id), ['p-b', 'p-a', 'p-c']);
    await expectLater(repo.reorder('n1', ['p-a']), throwsA(isA<RepositoryException>()));
  });

  test('setBackground e firstPage', () async {
    expect(await repo.firstPage('n1'), isNull);
    await repo.addPage('n1', id: 'p-a');
    await repo.addPage('n1', id: 'p-b');
    await repo.setBackground('p-b', PageBackground.grid);
    expect((await repo.firstPage('n1'))!.id, 'p-a');
    expect(server.pages['p-b']!['background'], 'grid');
  });

  test('savePage nunca grava o fundo: a troca feita por setBackground sobrevive a um save com fundo antigo', () async {
    final base = await repo.addPage('n1', id: 'p-a'); // lined
    await repo.setBackground('p-a', PageBackground.grid);
    final saved = await repo.savePage(base.copyWith(data: enc(['a']), background: PageBackground.lined));
    expect(server.pages['p-a']!['background'], 'grid');
    expect(saved.background, PageBackground.grid);
    final patch = writes().where((s) => s.method == 'PATCH' && s.path.endsWith('/note_pages')).last;
    expect((patch.body as Map).containsKey('background'), isFalse);
  });

  test('savePage de página apagada em outro aparelho recria com o fundo que tinha', () async {
    final base = await repo.addPage('n1', id: 'p-a', background: PageBackground.dots);
    await repo.deletePage('p-a');
    final saved = await repo.savePage(base.copyWith(data: enc(['a'])));
    expect(saved.background, PageBackground.dots);
    expect(idsOf(server.pages['p-a']!['data'] as String), {'a'});
  });

  test('erro 23514 (limite de 4 MB) vira falha permanente de página grande', () async {
    final p = await repo.addPage('n1', id: 'p-a');
    server.failStatus = 400;
    server.failCode = '23514';
    server.failWhen = (s) => s.method == 'PATCH' && s.path.endsWith('/note_pages');
    await expectLater(
      repo.savePage(p.copyWith(data: enc(['a']))),
      throwsA(isA<NotebookRepositoryException>().having((e) => e.kind, 'kind', NotebookErrorKind.pageTooLarge)),
    );
  });

  test('erros 23503 e 42501 viram "caderno excluído"; outros continuam transitórios', () async {
    final p = await repo.addPage('n1', id: 'p-a');
    for (final code in ['23503', '42501']) {
      server.failStatus = 409;
      server.failCode = code;
      server.failWhen = (s) => s.method == 'PATCH' && s.path.endsWith('/note_pages');
      await expectLater(
        repo.savePage(p.copyWith(data: enc(['a']))),
        throwsA(isA<NotebookRepositoryException>().having((e) => e.kind, 'kind', NotebookErrorKind.noteGone)),
        reason: code,
      );
    }
    server.failStatus = 500;
    server.failCode = 'XX000';
    await expectLater(
      repo.savePage(p.copyWith(data: enc(['a']))),
      throwsA(isA<NotebookRepositoryException>().having((e) => e.kind, 'kind', NotebookErrorKind.transient)),
    );
  });

  test('conflito com dado do servidor ilegível vira "formato mais novo" (não tenta de novo)', () async {
    final base = await repo.addPage('n1', id: 'p-a');
    server.pages['p-a']!['data'] = 'isto-nao-e-uma-pagina';
    server.pages['p-a']!['version'] = 5;
    await expectLater(
      repo.savePage(base.copyWith(data: enc(['a']))),
      throwsA(isA<NotebookRepositoryException>().having((e) => e.kind, 'kind', NotebookErrorKind.newerFormat)),
    );
  });

  test('recognizedTextByNote pede só páginas com texto e junta por caderno', () async {
    await repo.addPage('n1', id: 'p-a');
    await repo.addPage('n1', id: 'p-b');
    await repo.addPage('n2', id: 'p-c');
    server.pages['p-a']!['recognized_text'] = 'fotossíntese';
    server.pages['p-b']!['recognized_text'] = 'clorofila';
    final got = await repo.recognizedTextByNote();
    expect(got, {'n1': 'fotossíntese\nclorofila'});
    final get = server.sent.where((s) => s.method == 'GET').last;
    expect(get.query['recognized_text'], 'neq.');
  });

  test('NotebookPage.fromMap lê as colunas', () {
    final p = NotebookPage.fromMap({
      'id': 'x', 'note_id': 'n', 'idx': 2, 'background': 'dots', 'data': 'd', 'recognized_text': 'oi', 'version': 3,
      'updated_at': '2026-10-13T10:00:00Z',
    });
    expect([p.id, p.noteId, p.idx, p.background, p.data, p.recognizedText, p.version],
        ['x', 'n', 2, PageBackground.dots, 'd', 'oi', 3]);
    expect(p.updatedAt, isNotNull);
  });
}
