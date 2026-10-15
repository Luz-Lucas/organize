// Custo do controller na thread da interface durante a escrita: nada de
// codificar a página inteira à toa, nem decodificar o eco do próprio save, nem
// regravar o cache da lista a cada eco.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/core/notebook_core.dart';
import 'package:organizacional/notebook/data/notebook_repository.dart';
import 'package:organizacional/notebook/data/memory_notebook_repository.dart';
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

class _CountingStore extends MemoryNotebookPendingStore {
  int saves = 0, clears = 0, cacheSaves = 0;

  @override
  Future<void> save(String noteId, Map<String, Object?> json) {
    saves++;
    return super.save(noteId, json);
  }

  @override
  Future<void> clear(String noteId) {
    clears++;
    return super.clear(noteId);
  }

  @override
  Future<void> savePagesCache(String noteId, Map<String, Object?> json) {
    cacheSaves++;
    return super.savePagesCache(noteId, json);
  }
}

void main() {
  late MemoryNotebookRepository repo;
  late _CountingStore store;
  late List<PageDoc> encoded;
  late NotebookController c;

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.pump(Duration.zero);
    }
  }

  Future<void> boot(WidgetTester t, {NotebookRepository? useRepo, Duration cacheMinInterval = const Duration(hours: 1)}) async {
    c = NotebookController(
      noteId: 'n1',
      repo: useRepo ?? repo,
      images: _NoImages(),
      pending: store,
      cacheMinInterval: cacheMinInterval,
      encoder: (doc) async {
        encoded.add(doc);
        return encodePage(doc);
      },
    );
    addTearDown(c.dispose);
    unawaited(c.start());
    await settle(t);
  }

  setUp(() async {
    repo = MemoryNotebookRepository();
    store = _CountingStore();
    encoded = [];
    await repo.addPage('n1');
  });

  testWidgets('cópia local e envio ao servidor reaproveitam a mesma codificação da página', (t) async {
    await boot(t);
    c.updatePage(c.currentPages.single.id, docOf(['a', 'b']));
    await t.pump(const Duration(milliseconds: 350)); // cópia local (300 ms)
    await settle(t);
    expect(store.saves, 1);
    expect(encoded, hasLength(1));
    await t.pump(const Duration(milliseconds: 1500)); // envio (1,5 s)
    await settle(t);
    expect(repo.saveCount, 1);
    expect(encoded, hasLength(1), reason: 'a página não mudou entre a cópia local e o envio');
  });

  testWidgets('flush() logo depois da cópia local não regrava a cópia nem recodifica', (t) async {
    await boot(t);
    c.updatePage(c.currentPages.single.id, docOf(['a']));
    await t.pump(const Duration(milliseconds: 350));
    await settle(t);
    final saves = store.saves;
    unawaited(c.flush());
    await settle(t);
    expect(store.saves, saves, reason: 'nada mudou desde a última gravação local');
    expect(encoded, hasLength(1));
  });

  testWidgets('cada edição codifica a página uma vez, mesmo com cópia local e envio', (t) async {
    await boot(t);
    final id = c.currentPages.single.id;
    for (var i = 1; i <= 3; i++) {
      c.updatePage(id, docOf([for (var k = 0; k < i; k++) 's$k']));
      await t.pump(const Duration(milliseconds: 350));
      await settle(t);
    }
    await t.pump(const Duration(milliseconds: 1600));
    await settle(t);
    expect(encoded, hasLength(3));
    expect(repo.saveCount, 1);
  });

  testWidgets('o eco do realtime do próprio save não é decodificado nem reemite as páginas', (t) async {
    await boot(t);
    final emissions = <int>[];
    c.pages.listen((l) => emissions.add(l.length));
    await settle(t);
    final id = c.currentPages.single.id;
    c.updatePage(id, docOf(['a', 'b', 'c']));
    final decodesBefore = PageCodecStats.decodes;
    final emitsBefore = emissions.length;
    await t.pump(const Duration(milliseconds: 1800));
    await settle(t);
    expect(repo.saveCount, 1);
    expect(PageCodecStats.decodes, decodesBefore, reason: 'o eco traz o mesmo dado que acabamos de enviar');
    expect(emissions.length, emitsBefore);
    expect({for (final s in c.currentPages.single.doc.strokes) s.id}, {'a', 'b', 'c'});
  });

  testWidgets('dado de outro aparelho continua sendo mesclado (e decodificado)', (t) async {
    await boot(t);
    final other = await repo.listPages('n1');
    final decodesBefore = PageCodecStats.decodes;
    await repo.savePage(other.single.copyWith(data: enc(['z']), version: other.single.version));
    await settle(t);
    expect(PageCodecStats.decodes, greaterThan(decodesBefore));
    expect({for (final s in c.currentPages.single.doc.strokes) s.id}, {'z'});
  });

  testWidgets('cache da lista de páginas: não regrava a cada eco, mas a última versão é gravada ao fechar', (t) async {
    await boot(t);
    final id = c.currentPages.single.id;
    final writes0 = store.cacheSaves;
    for (var i = 1; i <= 3; i++) {
      c.updatePage(id, docOf([for (var k = 0; k < i; k++) 's$k']));
      await t.pump(const Duration(milliseconds: 1800));
      await settle(t);
    }
    expect(repo.saveCount, 3);
    expect(store.cacheSaves - writes0, 0, reason: '3 saves em ~5 s: o cache não foi regravado a cada eco');
    c.dispose();
    await settle(t);
    expect(store.cacheSaves - writes0, 1, reason: 'a última lista é gravada ao fechar');
    final cache = await store.loadPagesCache('n1');
    final pages = (cache!['pages'] as List).cast<Map>();
    expect(idsOf(pages.single['data'] as String), {'s0', 's1', 's2'});
  });

  testWidgets('cache da lista: com intervalo zero grava a cada mudança (comportamento antigo)', (t) async {
    await boot(t, cacheMinInterval: Duration.zero);
    final id = c.currentPages.single.id;
    final writes0 = store.cacheSaves;
    c.updatePage(id, docOf(['a']));
    await t.pump(const Duration(milliseconds: 1800));
    await settle(t);
    c.updatePage(id, docOf(['a', 'b']));
    await t.pump(const Duration(milliseconds: 1800));
    await settle(t);
    expect(store.cacheSaves - writes0, 2);
  });

  testWidgets('ao fechar o caderno o controller pede para "tocar" a nota (updated_at) uma vez', (t) async {
    final inner = MemoryNotebookRepository();
    await inner.addPage('n1');
    final ctrl = ControlledRepo(inner);
    await boot(t, useRepo: ctrl);
    c.updatePage(c.currentPages.single.id, docOf(['a']));
    await t.pump(const Duration(milliseconds: 1800));
    await settle(t);
    expect(ctrl.touchCalls, 0);
    c.dispose();
    expect(ctrl.touchCalls, 1);
  });
}
