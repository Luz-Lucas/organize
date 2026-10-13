
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/data/memory_notebook_repository.dart';
import 'package:organizacional/notebook/state/notebook_pending_store.dart';
import 'package:organizacional/notebook/state/notebook_providers.dart';

import '../data/fake_image_store.dart';
import '../data/notebook_test_support.dart';

Map<String, Object?> _queue(String pageId, List<String> ink) => {
      'v': 1,
      'pages': {
        pageId: {'data': enc(ink), 'version': 0, 'bg': 'lined'},
      },
      'ops': <Object?>[],
    };

void main() {
  late MemoryNotebookRepository repo;
  late MemoryNotebookPendingStore store;
  late ProviderContainer container;

  setUp(() {
    repo = MemoryNotebookRepository();
    store = MemoryNotebookPendingStore();
    container = ProviderContainer(overrides: [
      notebookRepositoryProvider.overrideWithValue(repo),
      notebookPendingStoreProvider.overrideWithValue(store),
      notebookImageStoreFactoryProvider.overrideWithValue((_) => FakeNotebookImageStore()),
    ]);
  });
  tearDown(() => container.dispose());

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('ao iniciar o app envia a fila de todos os cadernos, sem abrir nenhum', (t) async {
    final a = await repo.addPage('n1');
    final b = await repo.addPage('n2');
    await store.save('n1', _queue(a.id, ['a1']));
    await store.save('n2', _queue(b.id, ['b1']));
    container.listen(notebookStartupSyncProvider, (_, _) {});
    await settle(t);
    expect(idsOf((await repo.listPages('n1')).single.data), {'a1'});
    expect(idsOf((await repo.listPages('n2')).single.data), {'b1'});
    expect(await store.load('n1'), isNull);
    expect(await store.load('n2'), isNull);
    await t.pump(const Duration(seconds: 5));
    expect(container.exists(notebookControllerProvider('n1')), isFalse, reason: 'os controllers são descartados depois de enviar');
  });

  testWidgets('sem fila guardada não faz nada', (t) async {
    container.listen(notebookStartupSyncProvider, (_, _) {});
    await settle(t);
    expect(repo.saveCount, 0);
    expect(container.exists(notebookControllerProvider('n1')), isFalse);
  });

  testWidgets('sem rede, a fila continua guardada e é enviada quando a rede volta', (t) async {
    final a = await repo.addPage('n1');
    await store.save('n1', _queue(a.id, ['a1']));
    repo.failWrites = true;
    container.listen(notebookStartupSyncProvider, (_, _) {});
    await settle(t);
    expect(await store.load('n1'), isNotNull);
    repo.failWrites = false;
    await t.pump(const Duration(seconds: 70));
    await settle(t);
    expect(idsOf((await repo.listPages('n1')).single.data), {'a1'});
    expect(await store.load('n1'), isNull);
    await t.pump(const Duration(seconds: 5));
  });
}
