import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/app/providers.dart';
import 'package:organizacional/data/memory_repository.dart';

void main() {
  test('eventsFromProvider descarta a assinatura quando ninguém mais observa (autoDispose)',
      () async {
    final repo = MemoryRepository();
    final container = ProviderContainer(overrides: [repositoryProvider.overrideWithValue(repo)]);
    addTearDown(container.dispose);

    final date = DateTime(2026, 9, 28);
    final provider = eventsFromProvider(date);
    final sub = container.listen(provider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    expect(container.exists(provider), isTrue);

    sub.close();
    // autoDispose derruba o provider assim que fica sem ouvintes.
    await Future<void>.delayed(Duration.zero);
    expect(container.exists(provider), isFalse);
  });
}
