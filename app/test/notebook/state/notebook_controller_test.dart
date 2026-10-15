import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/core/notebook_core.dart';
import 'package:organizacional/notebook/data/memory_notebook_repository.dart';
import 'package:organizacional/notebook/data/notebook_repository.dart';
import 'package:organizacional/notebook/state/notebook_controller.dart';
import 'package:organizacional/notebook/state/notebook_pending_store.dart';
import 'package:organizacional/notebook/ui/notebook_session.dart';

import '../data/notebook_test_support.dart';

class _NoImages implements NotebookImageStore {
  @override
  Future<String> upload(Uint8List bytes, String ext) async => 'p.$ext';
  @override
  Future<ImageProvider> load(String path) async => throw UnimplementedError();
}

const _debounce = Duration(milliseconds: 1500);

void main() {
  late MemoryNotebookRepository repo;
  late MemoryNotebookPendingStore pending;
  late List<NotebookController> made;
  late List<bool> pendingFlags;

  NotebookController make({
    String noteId = 'n1',
    NotebookRepository? useRepo,
    NotebookPendingStore? usePending,
  }) {
    final c = NotebookController(
      noteId: noteId,
      repo: useRepo ?? repo,
      images: _NoImages(),
      pending: usePending ?? pending,
      onPendingChanged: pendingFlags.add,
    );
    made.add(c);
    return c;
  }

  setUp(() {
    repo = MemoryNotebookRepository();
    pending = MemoryNotebookPendingStore();
    made = [];
    pendingFlags = [];
  });
  tearDown(() {
    for (final c in made) {
      c.dispose();
    }
  });

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.pump(Duration.zero);
    }
  }

  Future<NotebookController> started(WidgetTester t, {String noteId = 'n1', int pages = 1}) async {
    for (var i = 0; i < pages; i++) {
      await repo.addPage(noteId);
    }
    final c = make(noteId: noteId);
    unawaited(c.start());
    await settle(t);
    return c;
  }

  List<Set<String>> idsPerPage(NotebookController c) => [
        for (final p in c.currentPages) {for (final s in p.doc.strokes) s.id},
      ];

  testWidgets('emite as páginas do repositório (idx, fundo e tinta) e começa "salvo"', (t) async {
    final p = await repo.addPage('n1', background: PageBackground.grid);
    await repo.savePage(p.copyWith(data: enc(['a'])));
    await repo.addPage('n1');
    final c = make();
    final seen = <List<NotebookPageState>>[];
    c.pages.listen(seen.add);
    unawaited(c.start());
    await settle(t);
    expect(seen, isNotEmpty);
    final pages = seen.last;
    expect(pages.map((x) => x.idx), [0, 1]);
    expect(pages[0].background, PageBackground.grid);
    expect({for (final s in pages[0].doc.strokes) s.id}, {'a'});
    expect(pages[1].doc.isEmpty, isTrue);
    expect(c.status, SaveStatus.saved);
  });

  testWidgets('pages repete o último valor para quem passa a escutar depois', (t) async {
    final c = await started(t);
    final first = <int>[];
    final second = <int>[];
    final a = c.pages.listen((l) => first.add(l.length));
    await settle(t);
    final b = c.pages.listen((l) => second.add(l.length)); // 2ª escuta no mesmo stream
    await settle(t);
    expect(first, [1]);
    expect(second, [1]);
    c.addPage();
    await settle(t);
    expect(first.last, 2);
    expect(second.last, 2);
    unawaited(a.cancel());
    unawaited(b.cancel());
  });

  testWidgets('debounce: vários gestos viram uma só gravação 1,5 s depois do último', (t) async {
    final c = await started(t);
    final statuses = <SaveStatus>[];
    c.statusChanges.listen(statuses.add);
    c.updatePage(c.currentPages[0].id, docOf(['s1']));
    expect(c.status, SaveStatus.saving);
    await t.pump(const Duration(milliseconds: 1000));
    c.updatePage(c.currentPages[0].id, docOf(['s1', 's2']));
    await t.pump(const Duration(milliseconds: 1000)); // 2 s desde o 1º gesto, 1 s desde o último
    expect(repo.saveCount, 0);
    expect(c.status, SaveStatus.saving);
    await t.pump(const Duration(milliseconds: 600));
    await settle(t);
    expect(repo.saveCount, 1);
    expect(idsOf((await repo.listPages('n1')).single.data), {'s1', 's2'});
    expect(c.status, SaveStatus.saved);
    expect(statuses, [SaveStatus.saving, SaveStatus.saved]);
    expect(repo.touchedNoteIds, ['n1']);
  });

  testWidgets('flush() grava na hora, sem esperar o debounce', (t) async {
    final c = await started(t);
    c.updatePage(c.currentPages[0].id, docOf(['s1']));
    unawaited(c.flush());
    await settle(t);
    expect(repo.saveCount, 1);
    expect(c.status, SaveStatus.saved);
    await t.pump(_debounce);
    await settle(t);
    expect(repo.saveCount, 1); // o timer cancelado não grava de novo
  });

  testWidgets('editar durante uma gravação em andamento regrava depois, sem perder nada', (t) async {
    final c = await started(t);
    c.updatePage(c.currentPages[0].id, docOf(['s1']));
    unawaited(c.flush());
    c.updatePage(c.currentPages[0].id, docOf(['s1', 's2'])); // chegou com a gravação em voo
    await settle(t);
    await t.pump(_debounce);
    await settle(t);
    expect(idsOf((await repo.listPages('n1')).single.data), {'s1', 's2'});
    expect(c.status, SaveStatus.saved);
  });

  testWidgets('dois aparelhos desenhando ao mesmo tempo: nenhum traço se perde e os dois convergem', (t) async {
    final a = await started(t);
    final b = make();
    unawaited(b.start());
    await settle(t);
    // Os dois partem da mesma página vazia (versão 0) e desenham coisas diferentes.
    a.updatePage(a.currentPages[0].id, docOf(['a1', 'a2']));
    b.updatePage(b.currentPages[0].id, docOf(['b1']));
    await t.pump(_debounce);
    await settle(t);
    final want = {'a1', 'a2', 'b1'};
    expect(idsOf((await repo.listPages('n1')).single.data), want);
    expect(idsPerPage(a), [want]);
    expect(idsPerPage(b), [want]);
    expect(a.status, SaveStatus.saved);
    expect(b.status, SaveStatus.saved);
  });

  testWidgets('um aparelho apaga o traço e o outro (sem saber) continua desenhando: o apagado não volta', (t) async {
    final a = await started(t);
    a.updatePage(a.currentPages[0].id, docOf(['x', 'y']));
    await a.flush();
    final b = make();
    unawaited(b.start());
    await settle(t);
    expect(idsPerPage(b), [
      {'x', 'y'}
    ]);
    // A apaga x; B, que ainda não recebeu, acrescenta z.
    repo.failWrites = false;
    a.updatePage(a.currentPages[0].id, a.currentPages.single.doc.without(['x']));
    b.updatePage(b.currentPages[0].id, b.currentPages.single.doc.withStroke(stroke('z')));
    await a.flush();
    await b.flush();
    await settle(t);
    expect(idsOf((await repo.listPages('n1')).single.data), {'y', 'z'});
    expect(idsPerPage(a), [
      {'y', 'z'}
    ]);
    expect(idsPerPage(b), [
      {'y', 'z'}
    ]);
  });

  testWidgets('offline: avisa "sem conexão", guarda no aparelho e envia quando a rede volta', (t) async {
    final c = await started(t);
    repo.failWrites = true;
    c.updatePage(c.currentPages[0].id, docOf(['s1']));
    await t.pump(_debounce);
    await settle(t);
    expect(c.status, SaveStatus.offline);
    expect(repo.saveCount, 0);
    final saved = await pending.load('n1');
    expect(saved, isNotNull); // "salvo no aparelho"
    // Continua desenhando offline: segue offline e atualiza a cópia local.
    c.updatePage(c.currentPages[0].id, docOf(['s1', 's2']));
    expect(c.status, SaveStatus.offline);
    // Volta a rede: a próxima tentativa automática envia tudo.
    repo.failWrites = false;
    await t.pump(const Duration(seconds: 70));
    await settle(t);
    expect(c.status, SaveStatus.saved);
    expect(idsOf((await repo.listPages('n1')).single.data), {'s1', 's2'});
    expect(await pending.load('n1'), isNull);
    expect(pendingFlags.first, isTrue);
    expect(pendingFlags.last, isFalse);
  });

  testWidgets('as tentativas offline espaçam (recuo) e não martelam o servidor', (t) async {
    final c = await started(t);
    repo.failWrites = true;
    c.updatePage(c.currentPages[0].id, docOf(['s1']));
    await t.pump(_debounce);
    await settle(t);
    var attempts = 0;
    repo.onWriteAttempt = () => attempts++;
    await t.pump(const Duration(seconds: 120));
    await settle(t);
    expect(attempts, inInclusiveRange(2, 8));
    c.dispose(); // cancela o timer de nova tentativa antes do fim do teste
    made.remove(c);
  });

  testWidgets('fechar o app offline e reabrir: a tinta guardada no aparelho é enviada', (t) async {
    final c = await started(t);
    repo.failWrites = true;
    c.updatePage(c.currentPages[0].id, docOf(['s1']));
    await t.pump(_debounce);
    await settle(t);
    c.dispose();
    made.remove(c);
    // Reabre (outra instância, mesmo armazenamento local), agora com rede.
    repo.failWrites = false;
    final again = make();
    unawaited(again.start());
    await settle(t);
    await settle(t);
    expect(idsOf((await repo.listPages('n1')).single.data), {'s1'});
    expect(idsPerPage(again), [
      {'s1'}
    ]);
    expect(await pending.load('n1'), isNull);
    expect(again.status, SaveStatus.saved);
  });

  testWidgets('descartar o controller com alterações pendentes guarda tudo no aparelho', (t) async {
    final c = await started(t);
    c.updatePage(c.currentPages[0].id, docOf(['s1']));
    c.dispose();
    made.remove(c);
    await settle(t);
    final saved = await pending.load('n1');
    expect(saved, isNotNull);
    expect(repo.saveCount, 0);
  });

  testWidgets('nova página offline aparece na hora e é criada no servidor quando volta a rede', (t) async {
    final c = await started(t);
    repo.failWrites = true;
    c.addPage(background: PageBackground.dots);
    await settle(t);
    expect(c.currentPages, hasLength(2));
    expect(c.currentPages[1].background, PageBackground.dots);
    expect(c.status, SaveStatus.offline);
    c.updatePage(c.currentPages[1].id, docOf(['n']));
    repo.failWrites = false;
    await t.pump(const Duration(seconds: 70));
    await settle(t);
    final pages = await repo.listPages('n1');
    expect(pages, hasLength(2));
    expect(pages[1].background, PageBackground.dots);
    expect(idsOf(pages[1].data), {'n'});
    expect(c.status, SaveStatus.saved);
  });

  testWidgets('addPage online cria no servidor e emite de novo', (t) async {
    final c = await started(t);
    final emissions = <int>[];
    c.pages.listen((l) => emissions.add(l.length));
    await settle(t);
    c.addPage();
    await settle(t);
    expect((await repo.listPages('n1')), hasLength(2));
    expect(emissions.last, 2);
  });

  testWidgets('deletePage some na hora, reindexa e apaga no servidor', (t) async {
    final c = await started(t, pages: 3);
    c.updatePage(c.currentPages[2].id, docOf(['last']));
    await c.flush();
    c.deletePage(c.currentPages[0].id);
    expect(c.currentPages, hasLength(2));
    expect(c.currentPages.map((p) => p.idx), [0, 1]);
    await settle(t);
    final pages = await repo.listPages('n1');
    expect(pages.map((p) => p.idx), [0, 1]);
    expect(idsOf(pages[1].data), {'last'});
    expect(idsPerPage(c)[1], {'last'});
  });

  testWidgets('duplicatePage copia fundo e tinta logo depois, inclusive o que ainda não foi salvo', (t) async {
    final c = await started(t, pages: 2);
    c.setBackground(c.currentPages[0].id, PageBackground.grid);
    c.updatePage(c.currentPages[0].id, docOf(['s1']));
    c.duplicatePage(c.currentPages[0].id);
    expect(c.currentPages, hasLength(3));
    expect(c.currentPages[1].background, PageBackground.grid);
    expect({for (final s in c.currentPages[1].doc.strokes) s.id}, {'s1'});
    await settle(t);
    await t.pump(_debounce);
    await settle(t);
    final pages = await repo.listPages('n1');
    expect(pages, hasLength(3));
    expect(pages.map((p) => p.background).take(2), [PageBackground.grid, PageBackground.grid]);
    expect(idsOf(pages[0].data), {'s1'});
    expect(idsOf(pages[1].data), {'s1'});
    expect(pages[2].data, '');
    expect(c.status, SaveStatus.saved);
  });

  testWidgets('addPage com conteúdo inicial (página de PDF) cria a página e grava o conteúdo', (t) async {
    final c = await started(t);
    const bg = ImageBox(id: 'pdf1', x: 0, y: 0, w: 1000, h: 1414, path: 'u/n/p1.jpg', background: true);
    c.addPage(background: PageBackground.blank, initial: PageDoc.empty.withImage(bg));
    expect(c.currentPages, hasLength(2));
    expect(c.currentPages[1].doc.images.single.background, isTrue);
    await settle(t);
    await t.pump(_debounce);
    await settle(t);
    final pages = await repo.listPages('n1');
    expect(pages, hasLength(2));
    expect(pages[1].background, PageBackground.blank);
    final img = decodePage(pages[1].data).images.single;
    expect(img.path, 'u/n/p1.jpg');
    expect(img.background, isTrue);
    expect(c.status, SaveStatus.saved);
  });

  testWidgets('setBackground grava só o fundo (sem reenviar a tinta)', (t) async {
    final c = await started(t);
    c.setBackground(c.currentPages[0].id, PageBackground.dots);
    await settle(t);
    expect((await repo.listPages('n1')).single.background, PageBackground.dots);
    expect(repo.saveCount, 0);
    expect(c.currentPages.single.background, PageBackground.dots);
  });

  testWidgets('página criada ou editada em outro aparelho chega e é mesclada ao que está na tela', (t) async {
    final c = await started(t);
    c.updatePage(c.currentPages[0].id, docOf(['mine']));
    final other = (await repo.listPages('n1')).single;
    await repo.savePage(other.copyWith(data: enc(['theirs'])));
    await repo.addPage('n1');
    await settle(t);
    expect(idsPerPage(c), [
      {'mine', 'theirs'},
      <String>{},
    ]);
    // E o que estava pendente ainda é enviado, já mesclado.
    await t.pump(_debounce);
    await settle(t);
    expect(idsOf((await repo.listPages('n1')).first.data), {'mine', 'theirs'});
  });

  testWidgets('página apagada em outro aparelho some, mas se havia tinta nova ela é preservada', (t) async {
    final c = await started(t, pages: 2);
    final first = (await repo.listPages('n1')).first;
    await repo.deletePage(first.id);
    await settle(t);
    expect(c.currentPages, hasLength(1));

    final second = await started(t, noteId: 'n2', pages: 2);
    final target = (await repo.listPages('n2')).first;
    second.updatePage(second.currentPages[0].id, docOf(['precious']));
    await repo.deletePage(target.id);
    await settle(t);
    await second.flush();
    await settle(t);
    final left = await repo.listPages('n2');
    expect(left.any((p) => idsOf(p.data).contains('precious')), isTrue);
  });

  testWidgets('as operações usam o id: apagar uma página antes não desloca a tinta das outras', (t) async {
    final c = await started(t, pages: 3);
    final ids = [for (final p in c.currentPages) p.id];
    c.updatePage(ids[2], docOf(['c']));
    c.deletePage(ids[0]);
    c.updatePage(ids[1], docOf(['b'])); // o índice 1 agora seria outra página; o id não muda
    await settle(t);
    await t.pump(_debounce);
    await settle(t);
    expect(c.currentPages.map((p) => p.id), [ids[1], ids[2]]);
    expect(idsPerPage(c), [
      {'b'},
      {'c'},
    ]);
    final pages = await repo.listPages('n1');
    expect(pages.map((p) => p.id), [ids[1], ids[2]]);
    expect(pages.map((p) => idsOf(p.data)), [
      {'b'},
      {'c'},
    ]);
  });

  testWidgets('página inserida por outro aparelho no meio mantém ids, ordem e tinta de cada uma', (t) async {
    final c = await started(t, pages: 2);
    final ids = [for (final p in c.currentPages) p.id];
    c.updatePage(ids[0], docOf(['a']));
    c.updatePage(ids[1], docOf(['b']));
    await t.pump(_debounce);
    await settle(t);
    final inserted = await repo.addPage('n1', at: 1);
    await settle(t);
    expect(c.currentPages.map((p) => p.id), [ids[0], inserted.id, ids[1]]);
    expect(idsPerPage(c), [
      {'a'},
      <String>{},
      {'b'},
    ]);
    c.updatePage(ids[1], docOf(['b', 'b2']));
    await t.pump(_debounce);
    await settle(t);
    expect((await repo.listPages('n1')).map((p) => idsOf(p.data)), [
      {'a'},
      <String>{},
      {'b', 'b2'},
    ]);
  });

  testWidgets('imagens vêm do store injetado', (t) async {
    final c = await started(t);
    expect(await c.images.upload(Uint8List(1), 'png'), 'p.png');
  });

  testWidgets('updatePage/deletePage com id desconhecido é ignorado', (t) async {
    final c = await started(t);
    c.updatePage('nao-existe', docOf(['x']));
    c.deletePage('nao-existe');
    c.setBackground('nao-existe', PageBackground.blank);
    c.duplicatePage('nao-existe');
    await settle(t);
    expect(c.currentPages, hasLength(1));
    expect(c.status, SaveStatus.saved);
  });
}
