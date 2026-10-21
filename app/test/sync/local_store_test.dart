import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/sync/local_store.dart';

void main() {
  late DateTime clock;
  late LocalStore store;

  setUp(() {
    clock = DateTime.utc(2026, 10, 21, 12);
    store = LocalStore.inMemory(now: () => clock);
  });
  tearDown(() => store.close());

  Map<String, dynamic> task(String id, [String title = 't']) => {'id': id, 'title': title};

  group('escrita local', () {
    test('put grava a linha e carimba client_updated_at em UTC', () async {
      await store.put('tasks', task('a'));
      final row = await store.get('tasks', 'a');
      expect(row, {'id': 'a', 'title': 't', 'client_updated_at': '2026-10-21T12:00:00.000Z'});
      expect(await store.all('tasks'), hasLength(1));
      expect(await store.get('tasks', 'zzz'), isNull);
    });

    test('put mescla sobre a linha existente (campos ausentes, como created_at, continuam)', () async {
      await store.put('tasks', {'id': 'a', 'title': 'um', 'created_at': '2026-01-01T00:00:00Z'});
      await store.put('tasks', {'id': 'a', 'title': 'dois'});
      final row = (await store.get('tasks', 'a'))!;
      expect(row['title'], 'dois');
      expect(row['created_at'], '2026-01-01T00:00:00Z');
    });

    test('cada put da mesma linha avança client_updated_at, mesmo com o relógio parado', () async {
      await store.put('tasks', task('a'));
      final first = DateTime.parse((await store.get('tasks', 'a'))!['client_updated_at'] as String);
      await store.put('tasks', task('a', 'outro'));
      final second = DateTime.parse((await store.get('tasks', 'a'))!['client_updated_at'] as String);
      expect(second.isAfter(first), isTrue);
    });

    test('relógio atrasado não faz a linha andar para trás', () async {
      await store.put('tasks', task('a'));
      clock = DateTime.utc(2026, 10, 21, 11);
      await store.put('tasks', task('a', 'x'));
      final ts = DateTime.parse((await store.get('tasks', 'a'))!['client_updated_at'] as String);
      expect(ts.isAfter(DateTime.utc(2026, 10, 21, 12)), isTrue);
    });

    test('putMany e removeMany', () async {
      await store.putMany('tasks', [task('a'), task('b'), task('c')]);
      expect(await store.all('tasks'), hasLength(3));
      await store.removeMany('tasks', ['a', 'c']);
      expect((await store.all('tasks')).map((r) => r['id']), ['b']);
    });

    test('remove apaga a linha', () async {
      await store.put('tasks', task('a'));
      await store.remove('tasks', 'a');
      expect(await store.get('tasks', 'a'), isNull);
    });

    test('tabelas são independentes', () async {
      await store.put('tasks', task('a'));
      await store.put('notes', task('a', 'nota'));
      expect((await store.get('notes', 'a'))!['title'], 'nota');
      expect((await store.get('tasks', 'a'))!['title'], 't');
    });

    test('user_settings usa user_id como chave', () async {
      await store.put('user_settings', {'user_id': 'u1', 'theme': 'dark'});
      expect((await store.get('user_settings', 'u1'))!['theme'], 'dark');
      await store.put('user_settings', {'user_id': 'u1', 'theme': 'light'});
      expect(await store.all('user_settings'), hasLength(1));
      expect(store.pendingNow, 1);
    });

    test('chaves configuráveis', () async {
      final s = LocalStore.inMemory(now: () => clock, keys: {'coisas': 'codigo'});
      addTearDown(s.close);
      await s.put('coisas', {'codigo': 'k1', 'v': 1});
      expect((await s.get('coisas', 'k1'))!['v'], 1);
    });

    test('linha sem chave é erro de programação', () async {
      expect(() => store.put('tasks', {'title': 'sem id'}), throwsArgumentError);
    });

    test('a leitura devolve cópias (mexer no mapa não altera o banco)', () async {
      await store.put('tasks', {'id': 'a', 'tags': ['x']});
      final row = (await store.get('tasks', 'a'))!;
      row['title'] = 'mudou';
      expect((await store.get('tasks', 'a'))!.containsKey('title'), isFalse);
    });
  });

  group('watch', () {
    test('emite o estado atual ao assinar e a cada mudança da tabela', () async {
      final emitted = <List<String>>[];
      final sub = store.watch('tasks').listen((rows) => emitted.add(rows.map((r) => r['id'] as String).toList()));
      addTearDown(sub.cancel);
      await pumpEventQueue();
      expect(emitted, [<String>[]]);

      await store.put('tasks', task('a'));
      await pumpEventQueue();
      await store.put('notes', task('n'));
      await pumpEventQueue();
      await store.remove('tasks', 'a');
      await pumpEventQueue();
      expect(emitted, [<String>[], ['a'], <String>[]]);
    });

    test('putMany gera uma emissão só', () async {
      var count = 0;
      final sub = store.watch('tasks').listen((_) => count++);
      addTearDown(sub.cancel);
      await pumpEventQueue();
      count = 0;
      await store.putMany('tasks', [task('a'), task('b'), task('c')]);
      await pumpEventQueue();
      expect(count, 1);
    });

    test('dois ouvintes recebem o mesmo estado', () async {
      await store.put('tasks', task('a'));
      final first = await store.watch('tasks').first;
      final second = await store.watch('tasks').first;
      expect(first, hasLength(1));
      expect(second, hasLength(1));
    });

    test('watchPending acompanha o tamanho da fila', () async {
      final seen = <int>[];
      final sub = store.watchPending().listen(seen.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();
      await store.put('tasks', task('a'));
      await pumpEventQueue();
      await store.put('notes', task('b'));
      await pumpEventQueue();
      expect(seen, [0, 1, 2]);
    });
  });

  group('fila de envio', () {
    test('put enfileira upsert e remove enfileira delete, em ordem', () async {
      await store.put('shopping_lists', {'id': 'l1'});
      await store.put('shopping_items', {'id': 'i1', 'list_id': 'l1'});
      await store.remove('tasks', 'x');
      final q = store.pendingOutbox();
      expect(q.map((e) => '${e.op.name}:${e.tbl}:${e.id}'), [
        'upsert:shopping_lists:l1',
        'upsert:shopping_items:i1',
        'delete:tasks:x',
      ]);
      expect(q.first.data!['client_updated_at'], '2026-10-21T12:00:00.000Z');
    });

    test('edições seguidas da mesma linha viram um item só', () async {
      await store.put('notes', {'id': 'n', 'title': 'a', 'body': 'x'});
      await store.put('notes', {'id': 'n', 'title': 'ab'});
      await store.put('notes', {'id': 'n', 'title': 'abc'});
      final q = store.pendingOutbox();
      expect(q, hasLength(1));
      expect(q.single.data!['title'], 'abc');
      expect(q.single.data!['body'], 'x');
    });

    test('não junta edições quando há outro item depois (preserva a ordem pai/filho)', () async {
      await store.put('shopping_items', {'id': 'i', 'list_id': 'l1'});
      await store.put('shopping_lists', {'id': 'l2'});
      await store.put('shopping_items', {'id': 'i', 'list_id': 'l2'});
      final q = store.pendingOutbox();
      expect(q.map((e) => e.tbl), ['shopping_items', 'shopping_lists', 'shopping_items']);
    });

    test('apagar descarta os upserts pendentes da linha e enfileira delete', () async {
      await store.put('tasks', task('a'));
      await store.put('tasks', task('b'));
      await store.remove('tasks', 'a');
      final q = store.pendingOutbox();
      expect(q.map((e) => '${e.op.name}:${e.id}'), ['upsert:b', 'delete:a']);
    });

    test('ack remove o item enviado, mas mantém se foi editado durante o envio', () async {
      await store.put('notes', {'id': 'n', 'title': 'a'});
      final sent = store.pendingOutbox().single;
      await store.put('notes', {'id': 'n', 'title': 'editado no meio do envio'});
      store.ackOutbox([sent]);
      expect(store.pendingOutbox(), hasLength(1));
      final again = store.pendingOutbox().single;
      store.ackOutbox([again]);
      expect(store.pendingOutbox(), isEmpty);
      expect(store.pendingNow, 0);
    });

    test('markOutboxFailed conta tentativas e guarda o último erro', () async {
      await store.put('tasks', task('a'));
      final e = store.pendingOutbox().single;
      store.markOutboxFailed([e], 'sem rede');
      store.markOutboxFailed([store.pendingOutbox().single], 'sem rede 2');
      final after = store.pendingOutbox().single;
      expect(after.attempts, 2);
      expect(after.lastError, 'sem rede 2');
    });
  });

  group('dados remotos', () {
    Map<String, dynamic> remote(String id, String title, String ts) =>
        {'id': id, 'title': title, 'client_updated_at': ts};

    test('sem pendência, o remoto substitui', () async {
      await store.applyRemoteUpsert('tasks', remote('a', 'nuvem', '2026-10-21T10:00:00Z'));
      expect((await store.get('tasks', 'a'))!['title'], 'nuvem');
      expect(store.pendingNow, 0);
    });

    test('pendência mais nova ou igual vence o remoto', () async {
      await store.put('tasks', task('a', 'local')); // 12:00
      final applied = await store.applyRemoteUpsert('tasks', remote('a', 'velho', '2026-10-21T11:59:59Z'));
      expect(applied, isFalse);
      expect((await store.get('tasks', 'a'))!['title'], 'local');
      expect(store.pendingNow, 1);
      // o eco do próprio envio (mesmo carimbo, com offset e microssegundos do Postgres) também não regride
      final echo = (await store.get('tasks', 'a'))!['client_updated_at'] as String;
      final pgFormat = '${echo.replaceFirst('Z', '').replaceFirst('.000', '.000000')}+00:00';
      await store.applyRemoteUpsert('tasks', remote('a', 'eco', pgFormat));
      expect((await store.get('tasks', 'a'))!['title'], 'local');
    });

    test('remoto mais novo que a pendência substitui e descarta a pendência', () async {
      await store.put('tasks', task('a', 'local')); // 12:00
      final applied = await store.applyRemoteUpsert('tasks', remote('a', 'nuvem', '2026-10-21T12:30:00Z'));
      expect(applied, isTrue);
      expect((await store.get('tasks', 'a'))!['title'], 'nuvem');
      expect(store.pendingNow, 0);
    });

    test('apagamento pendente local vence qualquer upsert remoto', () async {
      await store.put('tasks', task('a'));
      await store.remove('tasks', 'a');
      final applied = await store.applyRemoteUpsert('tasks', remote('a', 'nuvem', '2030-01-01T00:00:00Z'));
      expect(applied, isFalse);
      expect(await store.get('tasks', 'a'), isNull);
    });

    test('eco atrasado mais velho que a cópia local (sem pendência) não regride a linha', () async {
      await store.applyRemoteUpsert('tasks', remote('a', 'v2', '2026-10-21T10:02:00Z'));
      final applied = await store.applyRemoteUpsert('tasks', remote('a', 'v1', '2026-10-21T10:01:00Z'));
      expect(applied, isFalse);
      expect((await store.get('tasks', 'a'))!['title'], 'v2');
    });

    test('remoto sem client_updated_at é aceito quando não há pendência', () async {
      await store.applyRemoteUpsert('tasks', {'id': 'a', 'title': 'sem carimbo'});
      expect((await store.get('tasks', 'a'))!['title'], 'sem carimbo');
    });

    test('apagamento remoto apaga e descarta upserts pendentes (apagar ganha)', () async {
      await store.put('tasks', task('a'));
      await store.put('tasks', task('b'));
      await store.applyRemoteDelete('tasks', 'a');
      expect(await store.get('tasks', 'a'), isNull);
      expect(store.pendingOutbox().map((e) => e.id), ['b']);
    });

    test('apagamento remoto não derruba o delete pendente nem emite fila nova', () async {
      await store.applyRemoteUpsert('tasks', remote('a', 'x', '2026-10-21T10:00:00Z'));
      await store.remove('tasks', 'a');
      await store.applyRemoteDelete('tasks', 'a');
      expect(store.pendingOutbox().map((e) => '${e.op.name}:${e.id}'), ['delete:a']);
    });

    test('remoto aplicado não gera fila e acorda os watchers', () async {
      final seen = <int>[];
      final sub = store.watch('tasks').listen((r) => seen.add(r.length));
      addTearDown(sub.cancel);
      await pumpEventQueue();
      await store.applyRemoteUpsert('tasks', remote('a', 'x', '2026-10-21T10:00:00Z'));
      await pumpEventQueue();
      expect(seen, [0, 1]);
      expect(store.pendingNow, 0);
    });

    test('snapshot: substitui, remove o que sumiu da nuvem e preserva pendências e escritas recentes', () async {
      await store.applyRemoteUpsert('tasks', remote('velha', 'x', '2026-10-21T09:00:00Z')); // sumiu da nuvem
      await store.applyRemoteUpsert('tasks', remote('fica', 'antes', '2026-10-21T09:00:00Z'));
      await store.put('tasks', task('pendente', 'local')); // 12:00, na fila
      final startedAt = DateTime.utc(2026, 10, 21, 11); // a carga começou antes da escrita local

      await store.applyRemoteSnapshot(
        'tasks',
        [remote('fica', 'depois', '2026-10-21T09:30:00Z'), remote('nova', 'n', '2026-10-21T09:31:00Z')],
        startedAt: startedAt,
      );

      final byId = {for (final r in await store.all('tasks')) r['id']: r['title']};
      expect(byId, {'fica': 'depois', 'nova': 'n', 'pendente': 'local'});
    });

    test('snapshot não apaga linha gravada localmente depois do início da carga, mesmo já enviada', () async {
      clock = DateTime.utc(2026, 10, 21, 12);
      await store.put('tasks', task('recente'));
      store.ackOutbox(store.pendingOutbox()); // já foi para a nuvem, mas a carga (antiga) não a viu
      await store.applyRemoteSnapshot('tasks', const [], startedAt: DateTime.utc(2026, 10, 21, 11, 59));
      expect(await store.get('tasks', 'recente'), isNotNull);
    });

    test('snapshot: apagamento pendente local impede a linha de voltar', () async {
      await store.applyRemoteUpsert('tasks', remote('a', 'x', '2026-10-21T09:00:00Z'));
      await store.remove('tasks', 'a');
      await store.applyRemoteSnapshot('tasks', [remote('a', 'x', '2026-10-21T09:00:00Z')],
          startedAt: DateTime.utc(2026, 10, 21, 12, 1));
      expect(await store.get('tasks', 'a'), isNull);
    });

    test('snapshot é autoritativo quando a cópia local é antiga: remoto mais velho também vale', () async {
      // a nuvem ignorou nossa edição (servidor tinha algo mais novo) -> a carga corrige a cópia local
      await store.applyRemoteUpsert('tasks', remote('a', 'novo', '2026-10-21T10:00:00Z'));
      await store.applyRemoteSnapshot('tasks', [remote('a', 'servidor', '2026-10-21T09:00:00Z')],
          startedAt: DateTime.utc(2026, 10, 21, 12));
      expect((await store.get('tasks', 'a'))!['title'], 'servidor');
    });

    test('restoreFromRemote reescreve (ou apaga) uma linha só', () async {
      await store.put('tasks', task('a', 'rejeitada'));
      store.ackOutbox(store.pendingOutbox());
      await store.restoreFromRemote('tasks', 'a', remote('a', 'da nuvem', '2026-10-21T08:00:00Z'));
      expect((await store.get('tasks', 'a'))!['title'], 'da nuvem');
      await store.restoreFromRemote('tasks', 'a', null);
      expect(await store.get('tasks', 'a'), isNull);
    });
  });

  group('ciclo de vida', () {
    test('wipe apaga linhas e fila e avisa os watchers', () async {
      await store.put('tasks', task('a'));
      final lengths = <int>[];
      final sub = store.watch('tasks').listen((r) => lengths.add(r.length));
      addTearDown(sub.cancel);
      await pumpEventQueue();
      await store.wipe();
      await pumpEventQueue();
      expect(lengths, [1, 0]);
      expect(await store.all('tasks'), isEmpty);
      expect(store.pendingNow, 0);
    });

    test('arquivo: reabrir mantém linhas e fila', () async {
      final dir = await Directory.systemTemp.createTemp('local_store_test');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/u1.db';

      final a = await LocalStore.open(path, now: () => clock);
      await a.put('tasks', task('a', 'salvo'));
      await a.remove('tasks', 'b');
      await a.close();

      final b = await LocalStore.open(path, now: () => clock);
      addTearDown(b.close);
      expect((await b.get('tasks', 'a'))!['title'], 'salvo');
      expect(b.pendingOutbox().map((e) => '${e.op.name}:${e.id}'), ['upsert:a', 'delete:b']);
      expect(b.pendingNow, 2);
    });

    test('open cria pastas que faltam', () async {
      final dir = await Directory.systemTemp.createTemp('local_store_test');
      addTearDown(() => dir.delete(recursive: true));
      final s = await LocalStore.open('${dir.path}/sync/deep/u.db');
      await s.put('tasks', task('a'));
      await s.close();
      expect(File('${dir.path}/sync/deep/u.db').existsSync(), isTrue);
    });
  });
}
