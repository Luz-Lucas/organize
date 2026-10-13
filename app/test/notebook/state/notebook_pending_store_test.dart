import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/state/notebook_pending_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('shared_preferences: salva, lê e limpa por nota', () async {
    const store = SharedPreferencesNotebookPendingStore();
    expect(await store.load('n1'), isNull);
    await store.save('n1', {'v': 1, 'pages': {'p': 'x'}});
    await store.save('n2', {'v': 1});
    expect(await store.load('n1'), {'v': 1, 'pages': {'p': 'x'}});
    await store.clear('n1');
    expect(await store.load('n1'), isNull);
    expect(await store.load('n2'), {'v': 1});
  });

  test('JSON corrompido é ignorado e removido', () async {
    SharedPreferences.setMockInitialValues({'notebook.pending.n1': '{não é json'});
    const store = SharedPreferencesNotebookPendingStore();
    expect(await store.load('n1'), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('notebook.pending.n1'), isFalse);
  });

  test('em memória: mesmo contrato', () async {
    final store = MemoryNotebookPendingStore();
    await store.save('n1', {'a': 1});
    expect(await store.load('n1'), {'a': 1});
    await store.clear('n1');
    expect(await store.load('n1'), isNull);
  });
}
