import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/repository.dart';
import 'package:organizacional/notebook/core/notebook_core.dart';
import 'package:organizacional/notebook/data/memory_notebook_repository.dart';

import 'notebook_test_support.dart';

void main() {
  late MemoryNotebookRepository repo;
  setUp(() => repo = MemoryNotebookRepository());

  test('addPage acrescenta no fim, com fundo pautado e versão 0 por padrão', () async {
    final a = await repo.addPage('n1');
    final b = await repo.addPage('n1', background: PageBackground.grid);
    final other = await repo.addPage('n2');
    expect([a.idx, b.idx, other.idx], [0, 1, 0]);
    expect(a.background, PageBackground.lined);
    expect(b.background, PageBackground.grid);
    expect(a.version, 0);
    expect(a.data, '');
    expect((await repo.listPages('n1')).map((p) => p.id), [a.id, b.id]);
  });

  test('addPage com at insere nessa posição, reindexa e é idempotente para o mesmo id', () async {
    final a = await repo.addPage('n1');
    final b = await repo.addPage('n1');
    final mid = await repo.addPage('n1', at: 1, id: 'pg-mid');
    expect((await repo.listPages('n1')).map((p) => p.id), [a.id, 'pg-mid', b.id]);
    expect((await repo.listPages('n1')).map((p) => p.idx), [0, 1, 2]);
    final again = await repo.addPage('n1', at: 1, id: 'pg-mid');
    expect(again.id, mid.id);
    expect(await repo.listPages('n1'), hasLength(3));
    final end = await repo.addPage('n1', at: 99);
    expect(end.idx, 3);
  });

  test('savePage com withRecognizedText grava o texto reconhecido; sem isso não mexe nele', () async {
    final p = await repo.addPage('n1');
    final a = await repo.savePage(p.copyWith(data: enc(['a']), recognizedText: 'olá mundo', withRecognizedText: true));
    expect(a.recognizedText, 'olá mundo');
    expect((await repo.recognizedTextByNote())['n1'], 'olá mundo');
    // Um save só de tinta (outro aparelho sem reconhecimento) não apaga o texto do servidor.
    final b = await repo.savePage(a.copyWith(data: enc(['a', 'b']), recognizedText: ''));
    expect(b.recognizedText, 'olá mundo');
    // Texto vazio explícito (página esvaziada) limpa.
    final c = await repo.savePage(b.copyWith(recognizedText: '', withRecognizedText: true));
    expect(c.recognizedText, '');
  });

  test('em conflito o texto do aparelho não é gravado (vale o do documento mesclado, re-transcrito depois)', () async {
    final base = await repo.addPage('n1');
    await repo.savePage(base.copyWith(data: enc(['a1']), recognizedText: 'do outro aparelho', withRecognizedText: true));
    final merged = await repo.savePage(base.copyWith(data: enc(['b1']), recognizedText: 'meu', withRecognizedText: true));
    expect(idsOf(merged.data), {'a1', 'b1'});
    expect(merged.recognizedText, 'do outro aparelho');
  });

  test('conflito que não acrescenta nada à tinta deste aparelho: o texto é gravado', () async {
    final base = await repo.addPage('n1');
    await repo.savePage(base.copyWith(data: enc(['a1']))); // outro aparelho: só a1
    final merged = await repo.savePage(base.copyWith(data: enc(['a1', 'b1']), recognizedText: 'a1 b1', withRecognizedText: true));
    expect(idsOf(merged.data), {'a1', 'b1'});
    expect(merged.recognizedText, 'a1 b1');
  });

  test('savePage grava, sobe a versão e toca a nota', () async {
    final p = await repo.addPage('n1');
    final saved = await repo.savePage(p.copyWith(data: enc(['a'])));
    expect(saved.version, 1);
    expect(idsOf(saved.data), {'a'});
    expect(repo.touchedNoteIds, ['n1']);
    final again = await repo.savePage(saved.copyWith(data: enc(['a', 'b'])));
    expect(again.version, 2);
    expect(idsOf((await repo.listPages('n1')).single.data), {'a', 'b'});
  });

  test('conflito entre dois aparelhos mescla e não perde traços de nenhum', () async {
    final base = await repo.addPage('n1');
    // Os dois aparelhos abrem a mesma versão 0.
    final deviceA = base;
    final deviceB = base;
    await repo.savePage(deviceA.copyWith(data: enc(['a1', 'a2'])));
    // B ainda está na versão 0: o save é rejeitado, mesclado e regravado.
    final merged = await repo.savePage(deviceB.copyWith(data: enc(['b1'])));
    expect(idsOf(merged.data), {'a1', 'a2', 'b1'});
    expect(merged.version, 2);
    expect(idsOf((await repo.listPages('n1')).single.data), {'a1', 'a2', 'b1'});
  });

  test('conflito respeita tombstones: o que um aparelho apagou continua apagado', () async {
    final base = await repo.addPage('n1');
    final first = await repo.savePage(base.copyWith(data: enc(['a', 'b'])));
    // A apaga "a"; B (ainda na versão 1) desenha "c" sem saber.
    final erased = docOf(['a', 'b']).without(['a']);
    await repo.savePage(first.copyWith(data: encodePage(erased)));
    final merged = await repo.savePage(first.copyWith(data: enc(['a', 'b', 'c'])));
    expect(idsOf(merged.data), {'b', 'c'});
  });

  test('salvar de novo o mesmo conteúdo é idempotente', () async {
    final base = await repo.addPage('n1');
    await repo.savePage(base.copyWith(data: enc(['a'])));
    final merged = await repo.savePage(base.copyWith(data: enc(['a'])));
    expect(idsOf(merged.data), {'a'});
  });

  test('salvar página apagada em outro aparelho a recria no fim sem perder a tinta', () async {
    final a = await repo.addPage('n1');
    final b = await repo.addPage('n1');
    await repo.deletePage(a.id);
    final back = await repo.savePage(a.copyWith(data: enc(['x'])));
    final pages = await repo.listPages('n1');
    expect(pages.map((p) => p.id), [b.id, a.id]);
    expect(pages.map((p) => p.idx), [0, 1]);
    expect(idsOf(back.data), {'x'});
  });

  test('deletePage reindexa as páginas seguintes', () async {
    final p = [for (var i = 0; i < 3; i++) await repo.addPage('n1')];
    await repo.deletePage(p[0].id);
    final pages = await repo.listPages('n1');
    expect(pages.map((x) => x.id), [p[1].id, p[2].id]);
    expect(pages.map((x) => x.idx), [0, 1]);
  });

  test('duplicatePage insere a cópia logo depois, com id novo e a mesma tinta', () async {
    final p = [for (var i = 0; i < 3; i++) await repo.addPage('n1')];
    await repo.setBackground(p[0].id, PageBackground.dots);
    final withInk = await repo.savePage(p[0].copyWith(data: enc(['a'])));
    final copy = await repo.duplicatePage(withInk.id);
    final pages = await repo.listPages('n1');
    expect(pages.map((x) => x.id), [p[0].id, copy.id, p[1].id, p[2].id]);
    expect(pages.map((x) => x.idx), [0, 1, 2, 3]);
    expect(copy.id, isNot(p[0].id));
    expect(idsOf(copy.data), {'a'});
    expect(copy.background, PageBackground.dots);
    expect(copy.version, 0);
  });

  test('reorder aplica a nova ordem e rejeita ids que não são do caderno', () async {
    final p = [for (var i = 0; i < 3; i++) await repo.addPage('n1')];
    await repo.reorder('n1', [p[2].id, p[0].id, p[1].id]);
    expect((await repo.listPages('n1')).map((x) => x.id), [p[2].id, p[0].id, p[1].id]);
    expect(() => repo.reorder('n1', [p[0].id]), throwsA(isA<RepositoryException>()));
  });

  test('setBackground troca só o fundo', () async {
    final p = await repo.addPage('n1');
    await repo.setBackground(p.id, PageBackground.grid);
    final got = (await repo.listPages('n1')).single;
    expect(got.background, PageBackground.grid);
    expect(got.version, p.version);
  });

  test('firstPage devolve a de menor idx (ou null)', () async {
    expect(await repo.firstPage('n1'), isNull);
    final a = await repo.addPage('n1');
    await repo.addPage('n1');
    expect((await repo.firstPage('n1'))!.id, a.id);
  });

  test('watchPages emite a lista inicial e cada mudança', () async {
    final seen = <List<String>>[];
    final sub = repo.watchPages('n1').listen((l) => seen.add([for (final p in l) p.id]));
    await Future<void>.delayed(Duration.zero);
    final a = await repo.addPage('n1');
    final b = await repo.addPage('n1');
    await repo.deletePage(a.id);
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(seen.first, isEmpty);
    expect(seen.last, [b.id]);
    expect(seen.length, greaterThanOrEqualTo(4));
  });

  test('recognizedTextByNote junta o texto reconhecido das páginas de cada caderno (vazio é ignorado)', () async {
    final a = await repo.addPage('n1');
    final b = await repo.addPage('n1');
    await repo.addPage('n1');
    final c = await repo.addPage('n2');
    repo.setRecognizedText(a.id, 'fotossíntese');
    repo.setRecognizedText(b.id, 'clorofila');
    repo.setRecognizedText(c.id, 'derivadas');
    expect(await repo.recognizedTextByNote(), {'n1': 'fotossíntese\nclorofila', 'n2': 'derivadas'});
  });

  test('apagar a nota apaga as páginas (cascata)', () async {
    await repo.addPage('n1');
    repo.removeNote('n1');
    expect(await repo.listPages('n1'), isEmpty);
  });

  test('sem conexão toda escrita falha com RepositoryException e nada muda', () async {
    final p = await repo.addPage('n1');
    repo.failWrites = true;
    await expectLater(repo.savePage(p.copyWith(data: enc(['a']))), throwsA(isA<RepositoryException>()));
    await expectLater(repo.addPage('n1'), throwsA(isA<RepositoryException>()));
    repo.failWrites = false;
    expect((await repo.listPages('n1')).single.data, '');
  });

  test('savePage nunca troca o fundo de uma página que existe (fundo é do setBackground)', () async {
    final p = await repo.addPage('n1'); // lined
    await repo.setBackground(p.id, PageBackground.grid);
    final saved = await repo.savePage(p.copyWith(data: enc(['a']), background: PageBackground.lined));
    expect(saved.background, PageBackground.grid);
    expect((await repo.listPages('n1')).single.background, PageBackground.grid);
  });

  test('savePage de página apagada em outro aparelho recria com o fundo que ela tinha', () async {
    final p = await repo.addPage('n1', background: PageBackground.dots);
    await repo.deletePage(p.id);
    final saved = await repo.savePage(p.copyWith(data: enc(['a'])));
    expect(saved.background, PageBackground.dots);
  });
}
