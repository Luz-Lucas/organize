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

  test('shared_preferences: lista os cadernos com pendência (e só eles)', () async {
    SharedPreferences.setMockInitialValues({'outra.chave': 'x'});
    const store = SharedPreferencesNotebookPendingStore();
    expect(await store.pendingNoteIds(), isEmpty);
    await store.save('n1', {'v': 1});
    await store.save('n2', {'v': 1});
    await store.savePagesCache('n3', {'pages': []});
    expect((await store.pendingNoteIds())..sort(), ['n1', 'n2']);
    await store.clear('n1');
    expect(await store.pendingNoteIds(), ['n2']);
  });

  test('shared_preferences: cache da lista de páginas por caderno, separado da fila', () async {
    const store = SharedPreferencesNotebookPendingStore();
    expect(await store.loadPagesCache('n1'), isNull);
    await store.savePagesCache('n1', {'pages': [{'id': 'p'}]});
    expect(await store.loadPagesCache('n1'), {'pages': [{'id': 'p'}]});
    expect(await store.load('n1'), isNull);
    await store.clear('n1'); // limpar a fila não apaga o cache
    expect(await store.loadPagesCache('n1'), isNotNull);
    await store.clearPagesCache('n1');
    expect(await store.loadPagesCache('n1'), isNull);
  });

  test('em memória: pendingNoteIds e cache têm o mesmo contrato', () async {
    final store = MemoryNotebookPendingStore();
    await store.save('n1', {'a': 1});
    await store.savePagesCache('n2', {'pages': []});
    expect(await store.pendingNoteIds(), ['n1']);
    expect(await store.loadPagesCache('n2'), {'pages': []});
    await store.clearPagesCache('n2');
    expect(await store.loadPagesCache('n2'), isNull);
  });

  test('shared_preferences: JSON grande é codificado fora da thread principal e volta igual', () async {
    const store = SharedPreferencesNotebookPendingStore();
    final big = List.generate(40000, (i) => 'abcdefghij${i % 7}').join(); // ~400 KB
    final payload = {
      'v': 1,
      'pages': {
        'p1': {'data': big, 'version': 3, 'bg': 'lined'},
      },
      'ops': <Object?>[],
    };
    final before = SharedPreferencesNotebookPendingStore.isolateEncodes;
    await store.save('n1', payload);
    expect(SharedPreferencesNotebookPendingStore.isolateEncodes, before + 1);
    expect(await store.load('n1'), payload);
    // pequeno continua na thread (subir um isolate custaria mais que codificar)
    await store.save('n2', {'v': 1, 'pages': {'p': 'x'}});
    expect(SharedPreferencesNotebookPendingStore.isolateEncodes, before + 1);
  });
}
