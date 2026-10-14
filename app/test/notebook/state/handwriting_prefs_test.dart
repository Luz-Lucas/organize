import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/state/handwriting_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SlowStore implements HandwritingPrefsStore {
  _SlowStore(this.stored);
  HandwritingPrefs stored;
  final gate = Completer<void>();
  final saved = <HandwritingPrefs>[];

  @override
  Future<HandwritingPrefs> load() async {
    await gate.future;
    return stored;
  }

  @override
  Future<void> save(HandwritingPrefs prefs) async => saved.add(prefs);
}

ProviderContainer makeContainer(HandwritingPrefsStore store) {
  final c = ProviderContainer(overrides: [handwritingPrefsStoreProvider.overrideWithValue(store)]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('padrão: as três chaves ligadas', () {
    final c = makeContainer(MemoryHandwritingPrefsStore());
    final p = c.read(handwritingPrefsProvider);
    expect(p.recognize, isTrue);
    expect(p.spellCheck, isTrue);
    expect(p.gestures, isTrue);
    expect(c.read(recognizeWritingEnabledProvider), isTrue);
    expect(c.read(spellCheckEnabledProvider), isTrue);
    expect(c.read(editGesturesEnabledProvider), isTrue);
  });

  test('desligar uma chave muda só ela, avisa quem escuta e grava no aparelho', () async {
    final store = MemoryHandwritingPrefsStore();
    final c = makeContainer(store);
    final seen = <bool>[];
    c.listen(spellCheckEnabledProvider, (_, v) => seen.add(v));
    await c.read(handwritingPrefsProvider.notifier).setSpellCheck(false);
    expect(c.read(spellCheckEnabledProvider), isFalse);
    expect(c.read(recognizeWritingEnabledProvider), isTrue);
    expect(c.read(editGesturesEnabledProvider), isTrue);
    expect(seen, [false]);
    expect((await store.load()).spellCheck, isFalse);
    await c.read(handwritingPrefsProvider.notifier).setRecognize(false);
    await c.read(handwritingPrefsProvider.notifier).setGestures(false);
    final saved = await store.load();
    expect([saved.recognize, saved.spellCheck, saved.gestures], [false, false, false]);
  });

  test('carrega o que estava guardado', () async {
    final store = MemoryHandwritingPrefsStore()
      ..value = const HandwritingPrefs(recognize: false, spellCheck: true, gestures: false);
    final c = makeContainer(store);
    c.listen(handwritingPrefsProvider, (_, _) {});
    await pumpEventQueue();
    final p = c.read(handwritingPrefsProvider);
    expect([p.recognize, p.spellCheck, p.gestures], [false, true, false]);
  });

  test('escolha feita antes de terminar de carregar não é sobrescrita pelo valor antigo', () async {
    final store = _SlowStore(const HandwritingPrefs(recognize: true, spellCheck: true, gestures: true));
    final c = makeContainer(store);
    c.listen(handwritingPrefsProvider, (_, _) {});
    await c.read(handwritingPrefsProvider.notifier).setGestures(false);
    store.gate.complete();
    await pumpEventQueue();
    expect(c.read(editGesturesEnabledProvider), isFalse);
  });

  test('erro ao carregar mantém os padrões', () async {
    final c = makeContainer(_BrokenStore());
    c.listen(handwritingPrefsProvider, (_, _) {});
    await pumpEventQueue();
    expect(c.read(recognizeWritingEnabledProvider), isTrue);
  });

  test('SharedPreferences: ida e volta, e padrão quando vazio', () async {
    SharedPreferences.setMockInitialValues({});
    const store = SharedPreferencesHandwritingPrefsStore();
    var p = await store.load();
    expect([p.recognize, p.spellCheck, p.gestures], [true, true, true]);
    await store.save(const HandwritingPrefs(recognize: false, spellCheck: true, gestures: false));
    p = await store.load();
    expect([p.recognize, p.spellCheck, p.gestures], [false, true, false]);
  });
}

class _BrokenStore implements HandwritingPrefsStore {
  @override
  Future<HandwritingPrefs> load() async => throw StateError('sem disco');
  @override
  Future<void> save(HandwritingPrefs prefs) async => throw StateError('sem disco');
}
