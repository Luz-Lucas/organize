import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/sync/fake_remote_source.dart';
import 'package:organizacional/sync/sync_session.dart';

void main() {
  late Directory dir;
  late FakeRemoteSource remote;
  final sessions = <SyncSession>[];

  setUp(() {
    dir = Directory.systemTemp.createTempSync('sync-session');
    remote = FakeRemoteSource();
  });
  tearDown(() async {
    for (final s in sessions) {
      await s.close(erase: false);
    }
    sessions.clear();
    await remote.close();
    dir.deleteSync(recursive: true);
  });

  Future<SyncSession> open(String user, {Duration readyTimeout = const Duration(seconds: 5)}) async {
    final s = await SyncSession.open(
      userId: user,
      supportDir: dir,
      remote: remote,
      readyTimeout: readyTimeout,
      retryDelay: (_) => const Duration(milliseconds: 50),
      flushDelay: const Duration(milliseconds: 5),
      flushInterval: null,
      refreshInterval: null,
    );
    sessions.add(s);
    return s;
  }

  Future<void> until(bool Function() cond) async {
    for (var i = 0; i < 200 && !cond(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(cond(), isTrue, reason: 'condição não ficou verdadeira a tempo');
  }

  test('abre <apoio>/sync/<usuário>.db, carrega a nuvem e só então fica pronto', () async {
    remote.serverUpsert('shopping_lists', {'id': 'l1', 'name': 'Mercado'});
    final s = await open('u1');
    expect(File('${dir.path}/sync/u1.db').existsSync(), isTrue);
    await s.ready;
    expect((await s.store.all('shopping_lists')).single['id'], 'l1');
    expect(remote.calls.where((c) => c.op == 'fetch').map((c) => c.tbl), containsAll(syncTables));
  });

  test('shopping_frequent é só leitura: recebida, nunca enviada', () async {
    remote.serverUpsert('shopping_frequent', {'id': 'f1', 'name': 'Leite'});
    final s = await open('u1');
    await s.ready;
    expect(await s.store.all('shopping_frequent'), hasLength(1));
    await s.store.put('shopping_frequent', {'id': 'f2', 'name': 'x'});
    await s.engine.flush();
    expect(remote.calls.where((c) => c.op == 'upsert' && c.tbl == 'shopping_frequent'), isEmpty);
  });

  test('sem rede, ready libera depois do prazo e o que já está no aparelho continua', () async {
    final first = await open('u1');
    await first.ready;
    await first.store.put('tasks', {'id': 't1', 'title': 'offline'});
    await first.close(erase: false);
    sessions.clear();

    remote.online = false;
    final again = await open('u1', readyTimeout: const Duration(milliseconds: 100));
    await again.ready.timeout(const Duration(seconds: 2));
    expect((await again.store.all('tasks')).single['id'], 't1');
  });

  test('ready libera na hora quando já há listas de compras no aparelho (segunda abertura offline)', () async {
    final first = await open('u1');
    await first.ready;
    await first.store.put('shopping_lists', {'id': 'l1', 'name': 'Mercado'});
    await first.close(erase: false);
    sessions.clear();
    remote.online = false;
    final again = await open('u1');
    await again.ready.timeout(const Duration(milliseconds: 500));
  });

  test('escrever offline, fechar, reabrir e voltar a rede: chega uma vez só', () async {
    final first = await open('u1');
    await first.ready;
    remote.online = false;
    await first.store.put('tasks', {'id': 't1', 'title': 'feita offline'});
    await first.store.put('set_logs', {'id': 'sl1', 'reps': 8});
    await first.close(erase: false);
    sessions.clear();

    final again = await open('u1', readyTimeout: const Duration(milliseconds: 50));
    expect(again.store.pendingNow, 2);
    remote.online = true;
    await until(() => remote.row('tasks', 't1') != null && remote.row('set_logs', 'sl1') != null);
    await until(() => again.store.pendingNow == 0);
    expect(remote.calls.where((c) => c.op == 'upsert' && c.tbl == 'tasks'), hasLength(1));
    expect(remote.calls.where((c) => c.op == 'upsert' && c.tbl == 'set_logs'), hasLength(1));
  });

  test('close(erase: true) apaga o arquivo (e -wal/-shm); close(erase: false) mantém', () async {
    final s = await open('u1');
    await s.ready;
    await s.store.put('tasks', {'id': 't1', 'title': 'x'});
    await s.close(erase: true);
    sessions.clear();
    expect(Directory('${dir.path}/sync').listSync().where((f) => f.path.contains('u1.db')), isEmpty);
  });

  test('troca de conta: abrir outra conta apaga o banco que sobrou da anterior e não vaza dados', () async {
    final a = await open('ana');
    await a.ready;
    await a.store.put('tasks', {'id': 't-ana', 'title': 'da Ana'});
    await a.close(erase: false); // o app morreu sem apagar
    sessions.clear();
    remote = FakeRemoteSource();

    final b = await open('beto');
    await b.ready;
    expect(await b.store.all('tasks'), isEmpty);
    final files = Directory('${dir.path}/sync').listSync().map((f) => f.uri.pathSegments.last).toList();
    expect(files.where((f) => f.startsWith('ana.db')), isEmpty);
    expect(files, contains('beto.db'));
  });

  test('rejeição do servidor sai em engine.rejections', () async {
    final s = await open('u1');
    await s.ready;
    remote.reject = (tbl, op, row) => 'violates check constraint';
    final got = s.engine.rejections.first;
    await s.store.put('tasks', {'id': 't1', 'title': 'x'});
    expect((await got.timeout(const Duration(seconds: 2))).message, contains('check constraint'));
  });

  test('onResume traz o que mudou na nuvem sem tempo real e reemite o que o segundo plano gravou', () async {
    remote.realtime = false;
    final s = await open('u1');
    await s.ready;
    remote.serverUpsert('tasks', {'id': 'novo', 'title': 'de outro aparelho'});
    await s.onResume();
    expect((await s.store.all('tasks')).map((r) => r['id']), ['novo']);
  });

  test('voltar online depois de falha de envio recarrega a nuvem (eventos perdidos enquanto offline)', () async {
    remote.realtime = false;
    final s = await open('u1');
    await s.ready;
    remote.online = false;
    await s.store.put('tasks', {'id': 't1', 'title': 'x'});
    await until(() => !s.engine.currentState.online);
    remote.serverUpsert('tasks', {'id': 'de-fora', 'title': 'y'});
    remote.online = true;
    await until(() => s.store.pendingNow == 0);
    await until(() => remote.calls.where((c) => c.op == 'fetch').length > syncTables.length + 1);
    await until(() => s.store.pendingNow == 0);
    expect((await s.store.all('tasks')).map((r) => r['id']).toSet(), {'t1', 'de-fora'});
  });

  test('fechar com um envio preso na rede não trava nem estoura erro quando a rede solta', () async {
    final s = await open('u1');
    await s.ready;
    remote.hold();
    await s.store.put('tasks', {'id': 't1', 'title': 'x'});
    await Future<void>.delayed(const Duration(milliseconds: 50)); // o envio começou e está preso
    await s.close(erase: true, timeout: const Duration(milliseconds: 100));
    sessions.clear();
    remote.release();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(Directory('${dir.path}/sync').listSync().where((f) => f.path.contains('u1.db')), isEmpty);
  });
}
