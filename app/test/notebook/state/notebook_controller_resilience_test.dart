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
import 'controlled_repo.dart';

class _NoImages implements NotebookImageStore {
  @override
  Future<String> upload(Uint8List bytes, String ext) async => 'p.$ext';
  @override
  Future<ImageProvider> load(String path) async => throw UnimplementedError();
}

const _debounce = Duration(milliseconds: 1500);

void main() {
  late MemoryNotebookRepository mem;
  late ControlledRepo repo;
  late MemoryNotebookPendingStore pending;
  late List<NotebookController> made;
  late List<bool> pendingFlags;

  NotebookController make({
    String noteId = 'n1',
    int pageWarn = 3000000,
    int pageMax = 4000000,
  }) {
    final c = NotebookController(
      noteId: noteId,
      repo: repo,
      images: _NoImages(),
      pending: pending,
      onPendingChanged: pendingFlags.add,
      pageWarnLength: pageWarn,
      pageMaxLength: pageMax,
    );
    made.add(c);
    return c;
  }

  setUp(() {
    mem = MemoryNotebookRepository();
    repo = ControlledRepo(mem);
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
    for (var i = 0; i < 8; i++) {
      await t.pump(Duration.zero);
    }
  }

  Future<NotebookController> started(
    WidgetTester t, {
    String noteId = 'n1',
    int pages = 1,
    int pageWarn = 3000000,
    int pageMax = 4000000,
  }) async {
    for (var i = 0; i < pages; i++) {
      await mem.addPage(noteId);
    }
    final c = make(noteId: noteId, pageWarn: pageWarn, pageMax: pageMax);
    unawaited(c.start());
    await settle(t);
    return c;
  }

  List<String> pageIds(NotebookController c) => [for (final p in c.currentPages) p.id];
  Set<String> shown(NotebookController c, int i) => {for (final s in c.currentPages[i].doc.strokes) s.id};

  group('lista antiga do servidor depois de operações de estrutura', () {
    testWidgets('apagar com o realtime atrasado: a página apagada não volta', (t) async {
      repo.liveRealtime = false;
      final c = await started(t, pages: 2);
      final ids = pageIds(c);
      c.deletePage(ids[0]);
      await settle(t);
      expect(await mem.listPages('n1'), hasLength(1));
      expect(pageIds(c), [ids[1]]);
      await repo.pushRealtime('n1'); // o realtime finalmente chega
      await settle(t);
      expect(pageIds(c), [ids[1]]);
    });

    testWidgets('um evento antigo que chega depois do apagar não ressuscita a página', (t) async {
      repo.liveRealtime = false;
      final c = await started(t, pages: 2);
      final stale = await mem.listPages('n1');
      final ids = pageIds(c);
      c.deletePage(ids[0]);
      await settle(t);
      repo.emitRaw(stale);
      await settle(t);
      expect(pageIds(c), [ids[1]]);
    });

    testWidgets('página nova não some enquanto o realtime não chega', (t) async {
      repo.liveRealtime = false;
      final c = await started(t);
      c.addPage();
      await settle(t);
      expect(await mem.listPages('n1'), hasLength(2));
      expect(c.currentPages, hasLength(2));
      final ids = pageIds(c);
      repo.emitRaw([(await mem.listPages('n1')).first]); // evento antigo, sem a nova
      await settle(t);
      expect(pageIds(c), ids);
      await repo.pushRealtime('n1');
      await settle(t);
      expect(pageIds(c), ids);
    });

    testWidgets('trocar o fundo não volta ao antigo com o realtime atrasado', (t) async {
      repo.liveRealtime = false;
      final c = await started(t);
      final stale = await mem.listPages('n1');
      c.setBackground(c.currentPages.single.id, PageBackground.grid);
      await settle(t);
      repo.emitRaw(stale);
      await settle(t);
      expect(c.currentPages.single.background, PageBackground.grid);
    });

    testWidgets('escrever na página nova antes do realtime chegar grava nela', (t) async {
      repo.liveRealtime = false;
      final c = await started(t);
      c.addPage();
      await settle(t);
      final fresh = pageIds(c)[1];
      c.updatePage(fresh, docOf(['n']));
      await t.pump(_debounce);
      await settle(t);
      final pages = await mem.listPages('n1');
      expect(idsOf(pages[1].data), {'n'});
      expect(shown(c, 1), {'n'});
    });
  });

  group('o stream do repositório morre e é reaberto', () {
    testWidgets('consulta inicial que falha: assina de novo com espera crescente', (t) async {
      await mem.addPage('n1');
      repo.watchFailuresLeft = 2;
      final c = make();
      unawaited(c.start());
      await settle(t);
      expect(repo.watchCalls, 1);
      expect(c.currentPages, isEmpty);
      expect(c.status, SaveStatus.offline);
      await t.pump(const Duration(seconds: 4));
      expect(repo.watchCalls, 1);
      await t.pump(const Duration(seconds: 1)); // 5 s: 1ª nova tentativa (falha de novo)
      await settle(t);
      expect(repo.watchCalls, 2);
      await t.pump(const Duration(seconds: 9));
      expect(repo.watchCalls, 2);
      await t.pump(const Duration(seconds: 1)); // +10 s: 2ª nova tentativa (funciona)
      await settle(t);
      expect(repo.watchCalls, 3);
      expect(c.currentPages, hasLength(1));
      expect(c.status, SaveStatus.saved);
    });

    testWidgets('stream que fecha sem erro também é reaberto', (t) async {
      repo.liveRealtime = false;
      final c = await started(t);
      expect(repo.watchCalls, 1);
      repo.closeStreams();
      await settle(t);
      await t.pump(const Duration(seconds: 5));
      await settle(t);
      expect(repo.watchCalls, 2);
      // E o novo stream funciona: o que chega é mesclado.
      final p = (await mem.listPages('n1')).single;
      await mem.savePage(p.copyWith(data: enc(['theirs'])));
      await repo.pushRealtime('n1');
      await settle(t);
      expect(shown(c, 0), {'theirs'});
    });

    testWidgets('abrir offline mostra o cache, deixa escrever e sincroniza quando a rede volta', (t) async {
      // 1ª sessão, online: lê e grava tinta (o cache da lista fica no aparelho).
      final first = await started(t);
      first.updatePage(first.currentPages.single.id, docOf(['s1']));
      await first.flush();
      await settle(t);
      first.dispose();
      made.remove(first);

      // 2ª sessão, sem rede nenhuma.
      repo.watchFailuresLeft = 1000;
      mem.failWrites = true;
      final c = make();
      unawaited(c.start());
      await settle(t);
      expect(c.currentPages, hasLength(1), reason: 'o cache aparece sem rede');
      expect(shown(c, 0), {'s1'});
      c.updatePage(c.currentPages.single.id, docOf(['s1', 's2']));
      await t.pump(_debounce);
      await settle(t);
      expect(c.status, SaveStatus.offline);
      expect(await pending.load('n1'), isNotNull);

      // A rede volta.
      repo.watchFailuresLeft = 0;
      mem.failWrites = false;
      await t.pump(const Duration(seconds: 70));
      await settle(t);
      expect(c.status, SaveStatus.saved);
      expect(idsOf((await mem.listPages('n1')).single.data), {'s1', 's2'});
      expect(await pending.load('n1'), isNull);
    });
  });

  group('matar o app não perde a tinta', () {
    testWidgets('updatePage grava a cópia local em até 300 ms, bem antes do envio ao servidor', (t) async {
      final c = await started(t);
      c.updatePage(c.currentPages.single.id, docOf(['s1']));
      await t.pump(const Duration(milliseconds: 300));
      await settle(t);
      final saved = await pending.load('n1');
      expect(saved, isNotNull);
      expect((saved!['pages'] as Map).values.single, containsPair('data', enc(['s1'])));
      expect(mem.saveCount, 0);
      await t.pump(_debounce);
      await settle(t);
      expect(mem.saveCount, 1);
    });

    testWidgets('a cópia local só some depois que o servidor confirma', (t) async {
      final c = await started(t);
      final gate = repo.saveGate = Completer<void>();
      c.updatePage(c.currentPages.single.id, docOf(['s1']));
      unawaited(c.flush());
      await settle(t);
      expect(repo.savedVersions, isNotEmpty, reason: 'a gravação está em voo');
      expect(await pending.load('n1'), isNotNull);
      gate.complete();
      repo.saveGate = null;
      await settle(t);
      expect(await pending.load('n1'), isNull);
      expect(c.status, SaveStatus.saved);
    });

    testWidgets('escrita contínua: salva no servidor pelo menos a cada 10 s', (t) async {
      final c = await started(t);
      final id = c.currentPages.single.id;
      final ids = <String>[];
      final saveCounts = <int>[];
      for (var i = 0; i < 14; i++) {
        ids.add('s$i');
        c.updatePage(id, docOf(ids));
        await t.pump(const Duration(seconds: 1));
        saveCounts.add(mem.saveCount);
      }
      expect(saveCounts[8], 0, reason: 'com 9 s de escrita contínua ainda não houve pausa para o debounce');
      expect(saveCounts[10], greaterThanOrEqualTo(1), reason: 'passou de 10 s: o limite de espera salvou');
      expect(idsOf((await mem.listPages('n1')).single.data), isNotEmpty);
      await t.pump(_debounce);
      await settle(t);
      expect(idsOf((await mem.listPages('n1')).single.data), ids.toSet());
    });
  });

  group('a versão do servidor só vem do resultado do savePage', () {
    testWidgets('realtime sem data (página grande): relê a linha completa e mescla, sem perder nada', (t) async {
      repo.stripData = true;
      final c = await started(t);
      final id = c.currentPages.single.id;
      c.updatePage(id, docOf(['mine']));
      final p = (await mem.listPages('n1')).single;
      await mem.savePage(p.copyWith(data: enc(['theirs']))); // outro aparelho; o evento chega sem data
      await settle(t);
      expect(repo.listPagesCalls, greaterThan(0), reason: 'releu a linha completa');
      expect(shown(c, 0), {'mine', 'theirs'});
      await t.pump(_debounce);
      await settle(t);
      expect(idsOf((await mem.listPages('n1')).single.data), {'mine', 'theirs'});
    });

    testWidgets('o realtime atualiza o conteúdo, mas o save usa a versão do último savePage', (t) async {
      final c = await started(t);
      final id = c.currentPages.single.id;
      final p = (await mem.listPages('n1')).single;
      await mem.savePage(p.copyWith(data: enc(['theirs']))); // servidor na versão 1
      await settle(t);
      expect(shown(c, 0), {'theirs'}, reason: 'o conteúdo chegou');
      c.updatePage(id, c.currentPages.single.doc.withStroke(stroke('mine')));
      await t.pump(_debounce);
      await settle(t);
      expect(repo.savedVersions, [0], reason: 'a versão do where vem do que o controller gravou, não do realtime');
      expect(idsOf((await mem.listPages('n1')).single.data), {'theirs', 'mine'});
      c.updatePage(id, c.currentPages.single.doc.withStroke(stroke('mine2')));
      await t.pump(_debounce);
      await settle(t);
      expect(repo.savedVersions.last, 2, reason: 'agora a versão é a do resultado do savePage');
    });

    testWidgets('dado ilegível no realtime trava a página (só leitura) e não regrava por cima', (t) async {
      final c = await started(t);
      final id = c.currentPages.single.id;
      c.updatePage(id, docOf(['mine']));
      final p = (await mem.listPages('n1')).single;
      await mem.savePage(p.copyWith(data: 'dado-de-uma-versao-futura'));
      await settle(t);
      expect(c.currentPages.single.notice, PageNotice.newerVersion);
      await c.flush().timeout(const Duration(seconds: 5)); // não pode entrar em laço
      await t.pump(_debounce);
      await settle(t);
      expect((await mem.listPages('n1')).single.data, 'dado-de-uma-versao-futura');
      expect(pendingFlags.last, isFalse);
      final before = c.currentPages.single.doc;
      c.updatePage(id, docOf(['depois']));
      expect(c.currentPages.single.doc, before, reason: 'página travada ignora edições');
    });

    testWidgets('página ilegível já na abertura, com tinta guardada: termina, avisa e preserva a tinta', (t) async {
      final page = await mem.addPage('n1');
      await mem.savePage(page.copyWith(data: 'dado-de-uma-versao-futura'));
      await pending.save('n1', {
        'v': 1,
        'pages': {
          page.id: {'data': enc(['guardada']), 'version': 0, 'bg': 'lined'},
        },
        'ops': <Object?>[],
      });
      final c = make();
      unawaited(c.start());
      await settle(t);
      await t.pump(_debounce);
      await settle(t);
      expect(c.currentPages.single.notice, PageNotice.newerVersion);
      expect(c.status, SaveStatus.saved);
      expect(mem.saveCount, 1, reason: 'só o savePage que o teste fez; o controller não regravou');
      expect((await mem.listPages('n1')).single.data, 'dado-de-uma-versao-futura');
      final kept = await pending.load('n1');
      expect(kept, isNotNull, reason: 'a tinta guardada não é jogada fora');
    });

    testWidgets('savePage que acusa formato mais novo trava a página sem tentar de novo', (t) async {
      final c = await started(t);
      final id = c.currentPages.single.id;
      repo.saveError = (_) => const NotebookRepositoryException('versão nova', kind: NotebookErrorKind.newerFormat);
      c.updatePage(id, docOf(['x']));
      await t.pump(_debounce);
      await settle(t);
      await t.pump(const Duration(seconds: 120));
      expect(repo.saveAttemptsFor(id), 1);
      expect(c.currentPages.single.notice, PageNotice.newerVersion);
    });
  });

  group('erros permanentes e tamanho', () {
    testWidgets('página grande demais (23514): avisa, segue salvando as outras e não reenvia em laço', (t) async {
      final c = await started(t, pages: 2);
      final ids = pageIds(c);
      repo.saveError = (p) => p.id == ids[0]
          ? const NotebookRepositoryException('check', kind: NotebookErrorKind.pageTooLarge, code: '23514')
          : null;
      c.updatePage(ids[0], docOf(['a']));
      c.updatePage(ids[1], docOf(['b']));
      await t.pump(_debounce);
      await settle(t);
      expect(c.status, SaveStatus.problem);
      expect(c.currentPages[0].notice, PageNotice.tooLarge);
      expect(idsOf((await mem.listPages('n1'))[1].data), {'b'}, reason: 'a outra página foi salva');
      expect(await pending.load('n1'), isNotNull, reason: 'a tinta da página recusada continua guardada no aparelho');
      await t.pump(const Duration(seconds: 150));
      await settle(t);
      expect(repo.saveAttemptsFor(ids[0]), 1, reason: 'não reenvia o mesmo conteúdo');
      expect(pendingFlags.last, isFalse, reason: 'não mantém o controller vivo à toa');
    });

    testWidgets('depois que a página diminui, ela é enviada de novo e o aviso some', (t) async {
      final c = await started(t);
      final id = c.currentPages.single.id;
      repo.saveError = (_) => const NotebookRepositoryException('check', kind: NotebookErrorKind.pageTooLarge, code: '23514');
      c.updatePage(id, docOf(['a', 'b']));
      await t.pump(_debounce);
      await settle(t);
      expect(c.currentPages.single.notice, PageNotice.tooLarge);
      repo.saveError = null;
      c.updatePage(id, docOf(['a'])); // o usuário apagou parte
      await t.pump(_debounce);
      await settle(t);
      expect(c.currentPages.single.notice, PageNotice.none);
      expect(c.status, SaveStatus.saved);
      expect(idsOf((await mem.listPages('n1')).single.data), {'a'});
      expect(await pending.load('n1'), isNull);
    });

    testWidgets('caderno excluído em outro aparelho (23503/42501): avisa e para de tentar', (t) async {
      final c = await started(t);
      final id = c.currentPages.single.id;
      repo.saveError = (_) => const NotebookRepositoryException('fk', kind: NotebookErrorKind.noteGone, code: '23503');
      c.updatePage(id, docOf(['a']));
      await t.pump(_debounce);
      await settle(t);
      expect(c.status, SaveStatus.noteDeleted);
      await t.pump(const Duration(seconds: 150));
      await settle(t);
      expect(repo.saveAttemptsFor(id), 1);
      expect(pendingFlags.last, isFalse);
      expect(c.status, SaveStatus.noteDeleted);
    });

    testWidgets('perto do limite (3 MB) avisa, mas ainda salva', (t) async {
      final warn = enc(['a']).length + 1;
      final c = await started(t, pageWarn: warn, pageMax: warn * 100);
      final id = c.currentPages.single.id;
      c.updatePage(id, docOf(['a']));
      await t.pump(_debounce);
      await settle(t);
      expect(c.currentPages.single.notice, PageNotice.none);
      c.updatePage(id, docOf(['a', 'b', 'c', 'd', 'e', 'f']));
      await t.pump(_debounce);
      await settle(t);
      expect(c.currentPages.single.notice, PageNotice.nearLimit);
      expect(c.status, SaveStatus.saved);
      expect(idsOf((await mem.listPages('n1')).single.data), hasLength(6));
    });

    testWidgets('passou do limite de 4 MB: nem tenta enviar e avisa', (t) async {
      final max = enc(['a']).length + 1;
      final c = await started(t, pageWarn: max - 1, pageMax: max);
      final id = c.currentPages.single.id;
      c.updatePage(id, docOf(['a', 'b', 'c', 'd', 'e', 'f']));
      await t.pump(_debounce);
      await settle(t);
      expect(repo.saveAttemptsFor(id), 0);
      expect(c.currentPages.single.notice, PageNotice.tooLarge);
      expect(c.status, SaveStatus.problem);
    });
  });
}
