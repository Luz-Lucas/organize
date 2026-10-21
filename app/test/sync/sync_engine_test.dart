import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/sync/fake_remote_source.dart';
import 'package:organizacional/sync/local_store.dart';
import 'package:organizacional/sync/sync_engine.dart';

void main() {
  late DateTime clock;
  late LocalStore store;
  late FakeRemoteSource remote;
  late SyncEngine engine;

  DateTime now() => clock;

  SyncEngine makeEngine({
    LocalStore? withStore,
    bool autoFlush = false,
    List<String> tables = const ['tasks', 'notes', 'shopping_lists', 'shopping_items', 'user_settings'],
    List<String> readOnly = const [],
  }) =>
      SyncEngine(
        withStore ?? store,
        remote,
        tables: tables,
        readOnly: readOnly,
        now: now,
        autoFlush: autoFlush,
        flushDelay: Duration.zero,
        retryDelay: (_) => const Duration(milliseconds: 20),
        flushInterval: null,
        refreshInterval: null,
      );

  setUp(() {
    clock = DateTime.utc(2026, 10, 21, 12);
    store = LocalStore.inMemory(now: now);
    remote = FakeRemoteSource(now: now);
    engine = makeEngine();
  });

  tearDown(() async {
    await engine.dispose();
    await store.close();
    await remote.close();
  });

  Map<String, dynamic> task(String id, [String title = 't']) => {'id': id, 'title': title};

  Future<void> waitFor(bool Function() cond, {String? reason}) async {
    final end = DateTime.now().add(const Duration(seconds: 3));
    while (!cond()) {
      if (DateTime.now().isAfter(end)) fail('tempo esgotado esperando: ${reason ?? 'condição'}');
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  List<String> sends() => [
        for (final c in remote.calls)
          if (c.op != 'fetch') '${c.op} ${c.tbl} ${c.ids.join(',')}',
      ];

  group('carga e tempo real', () {
    test('start carrega todas as tabelas (inclusive as só de leitura) para o banco local', () async {
      remote.serverUpsert('tasks', {...task('a'), 'client_updated_at': '2026-10-21T10:00:00Z'});
      remote.serverUpsert('shopping_frequent', {'id': 'f1', 'name': 'Arroz'});
      engine = makeEngine(readOnly: const ['shopping_frequent']);
      await engine.start();

      expect(await store.all('tasks'), hasLength(1));
      expect(await store.all('shopping_frequent'), hasLength(1));
      expect(store.pendingNow, 0);
    });

    test('mudanças em tempo real chegam ao banco local sem gerar fila', () async {
      await engine.start();
      remote.serverUpsert('notes', {...task('n', 'da nuvem'), 'client_updated_at': '2026-10-21T11:00:00Z'});
      await pumpEventQueue();
      expect((await store.get('notes', 'n'))!['title'], 'da nuvem');

      remote.serverDelete('notes', 'n');
      await pumpEventQueue();
      expect(await store.get('notes', 'n'), isNull);
      expect(store.pendingNow, 0);
    });

    test('a carga completa remove o que sumiu da nuvem (sem pendência)', () async {
      await store.applyRemoteUpsert('tasks', {...task('velha'), 'client_updated_at': '2026-10-20T10:00:00Z'});
      await engine.start();
      expect(await store.get('tasks', 'velha'), isNull);
    });

    test('start sem rede não lança, marca offline e recarrega sozinho quando a rede volta', () async {
      remote.online = false;
      remote.serverUpsert('tasks', {...task('a'), 'client_updated_at': '2026-10-21T10:00:00Z'});
      await engine.start();
      expect(engine.currentState.online, isFalse);
      expect(await store.all('tasks'), isEmpty);

      remote.online = true;
      await waitFor(() => engine.currentState.online, reason: 'voltar online');
      expect(await store.all('tasks'), hasLength(1));
    });

    test('erro no canal de tempo real dispara uma recarga (eventos podem ter se perdido)', () async {
      await engine.start();
      remote.realtime = false;
      remote.serverUpsert('tasks', {...task('perdida'), 'client_updated_at': '2026-10-21T11:00:00Z'});
      await pumpEventQueue();
      expect(await store.get('tasks', 'perdida'), isNull);

      remote.failRealtime('tasks');
      await waitFor(() => remote.calls.where((c) => c.op == 'fetch').length >= 10, reason: 'recarga completa');
      await pumpEventQueue();
      expect(await store.get('tasks', 'perdida'), isNotNull);
    });

    test('refresh recarrega tudo (reconexão) e recupera o que o tempo real perdeu', () async {
      await engine.start();
      remote.realtime = false;
      remote.serverUpsert('tasks', {...task('x'), 'client_updated_at': '2026-10-21T11:00:00Z'});
      remote.serverUpsert('tasks', {...task('y'), 'client_updated_at': '2026-10-21T11:00:00Z'});
      await engine.refresh();
      expect(await store.all('tasks'), hasLength(2));
    });
  });

  group('envio', () {
    test('offline: fica na fila e o estado mostra pendente/offline; ao voltar, envia uma vez só', () async {
      await engine.start();
      remote.online = false;
      await store.put('tasks', task('a', 'feito offline'));
      await engine.flush();

      expect(store.pendingNow, 1);
      expect(engine.currentState.online, isFalse);
      expect(engine.currentState.pending, 1);
      expect(engine.currentState.lastError, isNotNull);
      expect((await store.get('tasks', 'a'))!['title'], 'feito offline'); // a tela continua vendo

      remote.online = true;
      await engine.flush();
      expect(store.pendingNow, 0);
      expect(engine.currentState.online, isTrue);
      expect(engine.currentState.lastError, isNull);
      expect(remote.row('tasks', 'a')!['title'], 'feito offline');
      expect(remote.calls.where((c) => c.op == 'upsert' && c.ids.contains('a')).length, 2); // 1 falha + 1 certo
      await engine.flush();
      expect(remote.calls.where((c) => c.op == 'upsert').length, 2); // nada reenviado
    });

    test('fecha o app e abre sem rede: a alteração está lá; com rede chega à nuvem uma vez', () async {
      final dir = await Directory.systemTemp.createTemp('sync_engine_test');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/u.db';

      // sessão 1: sem rede, grava e fecha
      final s1 = await LocalStore.open(path, now: now);
      remote.online = false;
      final e1 = makeEngine(withStore: s1);
      await e1.start();
      await s1.put('tasks', task('a', 'sobrevive'));
      await e1.flush();
      await e1.dispose();
      await s1.close();

      // sessão 2: abre sem rede, vê a alteração
      final s2 = await LocalStore.open(path, now: now);
      expect((await s2.get('tasks', 'a'))!['title'], 'sobrevive');
      final e2 = makeEngine(withStore: s2);
      await e2.start();
      expect(s2.pendingNow, 1);
      expect(remote.rows('tasks'), isEmpty);

      // a rede volta: envia uma vez só
      remote.online = true;
      remote.calls.clear();
      await e2.flush();
      expect(s2.pendingNow, 0);
      expect(remote.row('tasks', 'a')!['title'], 'sobrevive');
      expect(sends(), ['upsert tasks a']);
      await e2.dispose();
      await s2.close();
    });

    test('reenviar é idempotente: falha no meio e novo envio não duplica', () async {
      await store.put('tasks', task('a'));
      remote.failNext();
      await engine.flush();
      await engine.flush();
      expect(remote.rows('tasks'), hasLength(1));
      expect(store.pendingNow, 0);
    });

    test('ordem da fila: lista antes do item, ficha antes dos exercícios', () async {
      await store.put('shopping_lists', {'id': 'l1', 'name': 'Mercado'});
      await store.put('shopping_items', {'id': 'i1', 'list_id': 'l1'});
      await store.put('notes', task('n'));
      await store.put('shopping_items', {'id': 'i2', 'list_id': 'l1'});
      await engine.flush();
      expect(sends(), [
        'upsert shopping_lists l1',
        'upsert shopping_items i1',
        'upsert notes n',
        'upsert shopping_items i2',
      ]);
    });

    test('agrupa upserts consecutivos da mesma tabela numa chamada só', () async {
      await store.putMany('tasks', [task('a'), task('b'), task('c')]);
      await store.put('tasks', task('d'));
      await store.put('notes', task('n'));
      await store.put('tasks', task('e'));
      await engine.flush();
      expect(sends(), ['upsert tasks a,b,c,d', 'upsert notes n', 'upsert tasks e']);
    });

    test('agrupa deletes consecutivos da mesma tabela e respeita a ordem com os upserts', () async {
      remote.serverUpsert('tasks', {...task('a'), 'client_updated_at': '2026-10-21T10:00:00Z'});
      remote.serverUpsert('tasks', {...task('b'), 'client_updated_at': '2026-10-21T10:00:00Z'});
      await engine.start();
      remote.calls.clear();
      await store.removeMany('tasks', ['a', 'b']);
      await store.put('notes', task('n'));
      await store.remove('tasks', 'zzz');
      await engine.flush();
      expect(sends(), ['delete tasks a,b', 'upsert notes n', 'delete tasks zzz']);
      expect(remote.rows('tasks'), isEmpty);
    });

    test('a chave de user_settings é user_id', () async {
      await store.put('user_settings', {'user_id': 'u1', 'theme': 'dark'});
      await engine.flush();
      expect(sends(), ['upsert user_settings u1']);
      expect(remote.row('user_settings', 'u1')!['theme'], 'dark');
    });

    test('linhas de tabela só de leitura nunca são enviadas', () async {
      engine = makeEngine(readOnly: const ['shopping_frequent']);
      await store.put('shopping_frequent', {'id': 'f', 'name': 'x'});
      await store.put('tasks', task('a'));
      await engine.flush();
      expect(sends(), ['upsert tasks a']);
      expect(store.pendingNow, 0);
    });

    test('edição durante o envio não se perde', () async {
      await store.put('notes', {'id': 'n', 'title': 'v1'});
      remote.hold();
      final flushing = engine.flush();
      await pumpEventQueue();
      await store.put('notes', {'id': 'n', 'title': 'v2'});
      remote.release();
      await flushing;
      expect(store.pendingNow, 0);
      expect(remote.row('notes', 'n')!['title'], 'v2');
    });

    test('flush simultâneos não enviam duas vezes', () async {
      await store.put('tasks', task('a'));
      await Future.wait([engine.flush(), engine.flush(), engine.flush()]);
      expect(sends(), ['upsert tasks a']);
    });

    test('envio automático após cada escrita (autoFlush)', () async {
      engine = makeEngine(autoFlush: true);
      await engine.start();
      await store.put('tasks', task('auto'));
      await waitFor(() => remote.row('tasks', 'auto') != null, reason: 'envio automático');
      await waitFor(() => store.pendingNow == 0);
    });

    test('falha transitória é reenviada sozinha com espera, sem ação do usuário', () async {
      engine = makeEngine(autoFlush: true);
      await engine.start();
      remote.online = false;
      await store.put('tasks', task('a'));
      await waitFor(() => !engine.currentState.online, reason: 'detectar queda');
      remote.online = true;
      await waitFor(() => remote.row('tasks', 'a') != null, reason: 'reenvio sozinho');
      await waitFor(() => store.pendingNow == 0 && engine.currentState.online);
    });

    test('espera crescente: 1 s, 2 s, 4 s … até 60 s', () {
      expect([for (var i = 1; i <= 9; i++) SyncEngine.defaultRetryDelay(i).inSeconds], [1, 2, 4, 8, 16, 32, 60, 60, 60]);
      expect(SyncEngine.defaultRetryDelay(0), const Duration(seconds: 1));
    });

    test('dispose para de enviar', () async {
      engine = makeEngine(autoFlush: true);
      await engine.start();
      await engine.dispose();
      await store.put('tasks', task('a'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(remote.rows('tasks'), isEmpty);
    });
  });

  group('conflitos', () {
    test('alteração local pendente não é sobrescrita por versão mais velha da carga', () async {
      remote.serverUpsert('tasks', {...task('a', 'nuvem velha'), 'client_updated_at': '2026-10-21T08:00:00Z'});
      await engine.start();
      await store.put('tasks', task('a', 'local novo')); // 12:00
      await engine.refresh();
      expect((await store.get('tasks', 'a'))!['title'], 'local novo');
      expect(remote.row('tasks', 'a')!['title'], 'local novo'); // refresh também enviou
    });

    test('alteração pendente não é sobrescrita por evento de tempo real mais velho', () async {
      await engine.start();
      remote.online = false;
      await store.put('tasks', task('a', 'local'));
      remote.serverUpsert('tasks', {...task('a', 'outro aparelho'), 'client_updated_at': '2026-10-21T11:00:00Z'});
      await pumpEventQueue();
      expect((await store.get('tasks', 'a'))!['title'], 'local');
    });

    test('versão da nuvem mais nova que a pendência vence', () async {
      await engine.start();
      remote.online = false;
      await store.put('tasks', task('a', 'local')); // 12:00
      remote.serverUpsert('tasks', {...task('a', 'outro aparelho'), 'client_updated_at': '2026-10-21T13:00:00Z'});
      await pumpEventQueue();
      expect((await store.get('tasks', 'a'))!['title'], 'outro aparelho');
      expect(store.pendingNow, 0);
    });

    test('o servidor ignora o envio mais velho e a recarga corrige a cópia local', () async {
      remote.serverUpsert('tasks', {...task('a', 'mais novo'), 'client_updated_at': '2026-10-21T13:00:00Z'});
      await store.put('tasks', task('a', 'local velho')); // 12:00, aparelho ficou offline
      await engine.flush();
      expect(remote.row('tasks', 'a')!['title'], 'mais novo'); // gatilho do banco ignorou
      expect(store.pendingNow, 0);
      await engine.refresh();
      expect((await store.get('tasks', 'a'))!['title'], 'mais novo');
    });

    test('apagar local pendente não é desfeito por edição remota; apagar remoto vence edição pendente', () async {
      remote.serverUpsert('tasks', {...task('a'), 'client_updated_at': '2026-10-21T10:00:00Z'});
      remote.serverUpsert('tasks', {...task('b'), 'client_updated_at': '2026-10-21T10:00:00Z'});
      await engine.start();
      remote.online = false;
      await store.remove('tasks', 'a');
      await store.put('tasks', task('b', 'editada offline'));
      remote.serverUpsert('tasks', {...task('a', 'editada fora'), 'client_updated_at': '2026-10-21T13:00:00Z'});
      remote.serverDelete('tasks', 'b');
      await pumpEventQueue();
      expect(await store.get('tasks', 'a'), isNull);
      expect(await store.get('tasks', 'b'), isNull);

      remote.online = true;
      await engine.flush();
      expect(remote.row('tasks', 'a'), isNull); // o apagamento local chegou
      expect(remote.row('tasks', 'b'), isNull); // a edição descartada não ressuscitou a linha
    });
  });

  group('recusa permanente', () {
    test('sai da fila, a cópia local volta ao da nuvem e emite um aviso; a fila continua andando', () async {
      remote.serverUpsert('tasks', {...task('ok', 'v1'), 'client_updated_at': '2026-10-21T08:00:00Z'});
      await engine.start();
      remote.reject = (tbl, op, row) => row['title'] == 'proibido' ? 'viola a regra X' : null;
      final rejections = <SyncRejection>[];
      engine.rejections.listen(rejections.add);

      await store.put('tasks', task('ok', 'proibido')); // atualização recusada
      await store.put('tasks', task('novo', 'proibido')); // criação recusada
      await store.put('notes', task('n', 'passa')); // depois dela, tem que enviar
      await engine.flush();
      await pumpEventQueue();

      expect(store.pendingNow, 0);
      expect((await store.get('tasks', 'ok'))!['title'], 'v1'); // voltou ao da nuvem
      expect(await store.get('tasks', 'novo'), isNull); // não existe na nuvem
      expect(remote.row('notes', 'n'), isNotNull);
      expect(rejections.map((r) => '${r.tbl}/${r.id}/${r.message}'),
          ['tasks/ok/viola a regra X', 'tasks/novo/viola a regra X']);
      expect(engine.currentState.online, isTrue);
    });

    test('lote com uma linha ruim: as boas chegam, só a ruim é recusada', () async {
      await engine.start();
      remote.reject = (tbl, op, row) => row['id'] == 'ruim' ? 'recusada' : null;
      final rejections = <SyncRejection>[];
      engine.rejections.listen(rejections.add);
      await store.putMany('tasks', [task('a'), task('ruim'), task('c')]);
      await engine.flush();
      await pumpEventQueue();

      expect(remote.rows('tasks').map((r) => r['id']).toSet(), {'a', 'c'});
      expect(rejections.map((r) => r.id), ['ruim']);
      expect(await store.get('tasks', 'ruim'), isNull);
      expect(await store.get('tasks', 'a'), isNotNull);
      expect(store.pendingNow, 0);
    });

    test('apagar recusado: a linha volta', () async {
      remote.serverUpsert('tasks', {...task('a'), 'client_updated_at': '2026-10-21T08:00:00Z'});
      await engine.start();
      remote.reject = (tbl, op, row) => op == 'delete' ? 'sem permissão' : null;
      final rejections = <SyncRejection>[];
      engine.rejections.listen(rejections.add);
      await store.remove('tasks', 'a');
      expect(await store.get('tasks', 'a'), isNull);
      await engine.flush();
      await pumpEventQueue();
      expect(await store.get('tasks', 'a'), isNotNull);
      expect(rejections.single.message, 'sem permissão');
      expect(store.pendingNow, 0);
    });

    test('recusa não conta como queda de conexão', () async {
      await engine.start();
      remote.reject = (tbl, op, row) => 'não';
      await store.put('tasks', task('a'));
      await engine.flush();
      expect(engine.currentState.online, isTrue);
      expect(engine.currentState.lastError, isNull);
    });
  });

  group('estado', () {
    test('state emite o atual ao assinar e acompanha pendência/online', () async {
      final seen = <SyncState>[];
      final sub = engine.state.listen(seen.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();
      expect(seen.first, const SyncState(pending: 0, online: true, lastError: null));

      remote.online = false;
      await store.put('tasks', task('a'));
      await engine.flush();
      await pumpEventQueue();
      expect(seen.last.pending, 1);
      expect(seen.last.online, isFalse);

      remote.online = true;
      await engine.flush();
      await pumpEventQueue();
      expect(seen.last, const SyncState(pending: 0, online: true, lastError: null));
    });
  });
}
