import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/state/handwriting_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SlowStore implements IgnoredWordsStore {
  _SlowStore(this.stored);
  Set<String> stored;
  final gate = Completer<void>();
  final saved = <Set<String>>[];

  @override
  Future<Set<String>> load() async {
    await gate.future;
    return stored;
  }

  @override
  Future<void> save(Set<String> words) async => saved.add({...words});
}

ProviderContainer make(IgnoredWordsStore store) {
  final c = ProviderContainer(overrides: [ignoredWordsStoreProvider.overrideWithValue(store)]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('começa vazio e acrescentar guarda no aparelho', () async {
    final store = MemoryIgnoredWordsStore();
    final c = make(store);
    expect(c.read(ignoredWordsProvider), isEmpty);
    await c.read(ignoredWordsProvider.notifier).add('gatto');
    await c.read(ignoredWordsProvider.notifier).add('gatto');
    expect(c.read(ignoredWordsProvider), {'gatto'});
    expect(store.value, {'gatto'});
  });

  test('o que estava guardado volta, sem perder o que foi ignorado enquanto carregava', () async {
    final store = _SlowStore({'xpto'});
    final c = make(store);
    c.read(ignoredWordsProvider);
    await c.read(ignoredWordsProvider.notifier).add('lucas');
    store.gate.complete();
    await Future<void>.delayed(Duration.zero);
    expect(c.read(ignoredWordsProvider), {'xpto', 'lucas'});
  });

  test('SharedPreferences: grava e lê de volta', () async {
    SharedPreferences.setMockInitialValues({});
    const store = SharedPreferencesIgnoredWordsStore();
    await store.save({'b', 'a'});
    expect(await store.load(), {'a', 'b'});
  });
}
