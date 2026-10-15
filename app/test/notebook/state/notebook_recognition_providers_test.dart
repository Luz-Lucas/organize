import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/data/memory_notebook_repository.dart';
import 'package:organizacional/notebook/intelligence/model_manager.dart';
import 'package:organizacional/notebook/state/handwriting_providers.dart';
import 'package:organizacional/notebook/state/notebook_providers.dart';

import '../data/fake_image_store.dart';
import '../data/notebook_test_support.dart';
import '../intelligence/fake_recognizer.dart';

void main() {
  late MemoryNotebookRepository repo;
  late FakeInkRecognizer rec;
  late MemoryHandwritingPrefsStore prefs;
  late ProviderContainer container;

  setUp(() {
    repo = MemoryNotebookRepository();
    rec = FakeInkRecognizer(resolve: (s) => ['visto ${s.length}']);
    prefs = MemoryHandwritingPrefsStore();
    container = ProviderContainer(overrides: [
      notebookRepositoryProvider.overrideWithValue(repo),
      notebookImageStoreFactoryProvider.overrideWithValue((_) => FakeNotebookImageStore()),
      inkRecognizerProvider.overrideWithValue(rec),
      handwritingPrefsStoreProvider.overrideWithValue(prefs),
    ]);
  });
  tearDown(() => container.dispose());

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('o controller do provider usa o reconhecedor e a chave "Reconhecer escrita"', (t) async {
    await repo.addPage('n1');
    final sub = container.listen(notebookControllerProvider('n1'), (_, _) {});
    final c = sub.read();
    await settle(t);
    c.updatePage(c.currentPages.first.id, docOf(['a', 'b']));
    await t.pump(const Duration(seconds: 6));
    await settle(t);
    expect((await repo.listPages('n1')).single.recognizedText, 'visto 2');
    sub.close();
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('com a chave desligada o provider não reconhece', (t) async {
    container.listen(handwritingPrefsProvider, (_, _) {});
    await container.read(handwritingPrefsProvider.notifier).setRecognize(false);
    await repo.addPage('n1');
    final sub = container.listen(notebookControllerProvider('n1'), (_, _) {});
    final c = sub.read();
    await settle(t);
    c.updatePage(c.currentPages.first.id, docOf(['a']));
    await t.pump(const Duration(seconds: 6));
    await settle(t);
    expect(rec.calls, isEmpty);
    expect(idsOf((await repo.listPages('n1')).single.data), {'a'});
    sub.close();
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('ao sair do caderno transcreve na hora (sem esperar os 3 s) e grava tinta e texto juntos', (t) async {
    await repo.addPage('n1');
    final sub = container.listen(notebookControllerProvider('n1'), (_, _) {});
    final c = sub.read();
    await settle(t);
    c.updatePage(c.currentPages.first.id, docOf(['a']));
    await t.pump(const Duration(milliseconds: 300));
    expect(repo.saveCount, 0);
    sub.close(); // a tela fechou antes do debounce e dos 3 s
    await t.pump(const Duration(milliseconds: 500));
    await settle(t);
    final page = (await repo.listPages('n1')).single;
    expect(idsOf(page.data), {'a'});
    expect(page.recognizedText, 'visto 1');
    expect(repo.saveCount, 1, reason: 'tinta e texto no mesmo savePage');
    await t.pump(const Duration(seconds: 5));
    expect(container.exists(notebookControllerProvider('n1')), isFalse, reason: 'tudo gravado: descartado');
  });
}
