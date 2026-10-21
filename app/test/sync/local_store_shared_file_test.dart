import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/sync/local_store.dart';

/// O app e o isolate de segundo plano abrem o mesmo arquivo SQLite, cada um com a sua conexão.
void main() {
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('shared-store');
    path = '${dir.path}/sync/u1.db';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 20));

  test('duas conexões ao mesmo arquivo: cada uma vê a escrita da outra', () async {
    final app = await LocalStore.open(path);
    final background = await LocalStore.open(path);
    await app.put('tasks', {'id': 'a', 'title': 'do app'});
    await background.put('tasks', {'id': 'b', 'title': 'do segundo plano'});
    expect((await app.all('tasks')).map((r) => r['id']).toSet(), {'a', 'b'});
    expect((await background.all('tasks')).map((r) => r['id']).toSet(), {'a', 'b'});
    expect(app.pendingNow, 2);
    await app.close();
    await background.close();
  });

  test('checkExternalChanges reemite os streams do app quando outra conexão gravou', () async {
    final app = await LocalStore.open(path);
    final seen = <int>[];
    final sub = app.watch('tasks').listen((rows) => seen.add(rows.length));
    final pending = <int>[];
    final psub = app.watchPending().listen(pending.add);
    await tick();
    expect(app.checkExternalChanges(), isFalse, reason: 'nada mudou fora');

    final background = await LocalStore.open(path);
    await background.put('tasks', {'id': 'b', 'title': 'x'});
    await background.close();

    expect(app.checkExternalChanges(), isTrue);
    await tick();
    expect(seen, [0, 1]);
    expect(pending, [0, 1]);
    expect(app.checkExternalChanges(), isFalse, reason: 'já viu essa mudança');
    await sub.cancel();
    await psub.cancel();
    await app.close();
  });

  test('escritas concorrentes de outro isolate não se perdem nem dão "database is locked"', () async {
    final app = await LocalStore.open(path);
    final other = Isolate.run(() async {
      final store = await LocalStore.open(path);
      for (var i = 0; i < 40; i++) {
        await store.put('tasks', {'id': 'bg$i', 'title': 'segundo plano $i'});
      }
      await store.close();
    });
    for (var i = 0; i < 40; i++) {
      await app.put('tasks', {'id': 'app$i', 'title': 'app $i'});
      await Future<void>.delayed(Duration.zero);
    }
    await other;
    final ids = (await app.all('tasks')).map((r) => r['id']).toSet();
    expect(ids, hasLength(80));
    expect(app.pendingNow, 80);
    await app.close();
  });
}
