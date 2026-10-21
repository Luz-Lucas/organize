import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/app/local_overrides.dart';
import 'package:organizacional/app/providers.dart';
import 'package:organizacional/data/local_fitness_repository.dart';
import 'package:organizacional/data/local_repository.dart';
import 'package:organizacional/data/memory_alexa_repository.dart';
import 'package:organizacional/domain/task_item.dart';
import 'package:organizacional/domain/workout.dart';
import 'package:organizacional/sync/fake_remote_source.dart';
import 'package:organizacional/sync/local_store.dart';
import 'package:organizacional/sync/sync_engine.dart';
import 'package:organizacional/sync/sync_session.dart';

import '../helpers.dart';

void main() {
  group('fluxo completo (arquivo de verdade)', () {
    late Directory dir;
    late FakeRemoteSource remote;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('flow');
      remote = FakeRemoteSource();
    });
    tearDown(() async {
      await remote.close();
      dir.deleteSync(recursive: true);
    });

    Future<SyncSession> open(String user) => SyncSession.open(
          userId: user,
          supportDir: dir,
          remote: remote,
          readyTimeout: const Duration(milliseconds: 50),
          retryDelay: (_) => const Duration(milliseconds: 40),
          flushDelay: const Duration(milliseconds: 5),
          flushInterval: null,
          refreshInterval: null,
          externalCheckInterval: null,
        );

    Future<void> until(bool Function() cond) async {
      for (var i = 0; i < 300 && !cond(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(cond(), isTrue, reason: 'não chegou a tempo');
    }

    test('offline: escreve tarefa e marca a série duas vezes, fecha, reabre, volta a rede: chega uma vez só', () async {
      var s = await open('u1');
      await s.ready;
      remote.online = false;
      final repo = LocalFirstRepository(s.store);
      final fit = LocalFirstFitnessRepository(s.store);
      await repo.upsertTask(const TaskItem(id: 't1', title: 'Relatório'));
      const w = Workout(id: 'w1', name: 'A', exercises: [WorkoutExercise(id: 'e1', workoutId: 'w1', name: 'Supino')]);
      await fit.upsertWorkout(w);
      final session = await fit.startSession(w, DateTime(2026, 10, 21, 7));
      final log = SetLog(
          id: 'l1', sessionId: session.id, exerciseId: 'e1', exerciseName: 'Supino', setIndex: 1, reps: 8, doneAt: DateTime(2026, 10, 21, 7, 5));
      await fit.logSet(log);
      await fit.logSet(SetLog(
          id: 'outro', sessionId: session.id, exerciseId: 'e1', exerciseName: 'Supino', setIndex: 1, reps: 9, doneAt: DateTime(2026, 10, 21, 7, 6)));
      await s.close(erase: false); // fechou o app sem rede
      expect(remote.rows('tasks'), isEmpty);

      s = await open('u1'); // abriu de novo, ainda sem rede
      await s.ready;
      expect((await LocalFirstRepository(s.store).watchTasks().first).single.title, 'Relatório');
      expect((await LocalFirstFitnessRepository(s.store).watchSessions(from: DateTime(2026, 10, 1)).first).single.logs,
          hasLength(1),
          reason: 'a mesma série marcada de novo reaproveita o registro');
      remote.online = true;
      await until(() => s.store.pendingNow == 0);
      expect(remote.rows('tasks').single['id'], 't1');
      expect(remote.rows('set_logs'), hasLength(1));
      expect(remote.calls.where((c) => c.op == 'upsert' && c.tbl == 'tasks'), hasLength(1));
      expect(remote.calls.where((c) => c.op == 'upsert' && c.tbl == 'set_logs').expand((c) => c.ids), hasLength(1));
      await s.close(erase: false);
    });

    test('sair da conta apaga o banco; outra conta entra sem ver nada da anterior', () async {
      var s = await open('ana');
      await s.ready;
      await LocalFirstRepository(s.store).upsertTask(const TaskItem(id: 'segredo', title: 'da Ana'));
      await s.close(erase: true);
      expect(File('${dir.path}/sync/ana.db').existsSync(), isFalse);

      remote = FakeRemoteSource(); // a nuvem do Beto é outra
      s = await open('beto');
      await s.ready;
      expect(await LocalFirstRepository(s.store).watchTasks().first, isEmpty);
      await s.close(erase: false);
    });
  });

  group('telas com o banco local', () {
    late LocalStore store;
    late FakeRemoteSource remote;
    late SyncEngine engine;

    setUp(() {
      store = LocalStore.inMemory();
      remote = FakeRemoteSource();
      engine = SyncEngine(store, remote,
          tables: syncTables,
          readOnly: syncReadOnlyTables,
          retryDelay: (_) => const Duration(seconds: 1),
          flushDelay: const Duration(milliseconds: 50),
          flushInterval: null,
          refreshInterval: null);
    });
    tearDown(() async {
      await engine.dispose();
      await store.close();
      await remote.close();
    });

    testWidgets('tarefa criada offline aparece na hora, o ícone avisa depois de 4 s e some quando sobe',
        (tester) async {
      unawaited(engine.start()); // dentro do relógio falso do teste: os timers do envio andam com o pump
      remote.online = false;
      await pumpApp(
        tester,
        LocalFirstRepository(store),
        location: '/tarefas',
        repositoryOverrides: localFirstOverridesFor(
          userId: 'u1',
          store: store,
          engine: engine,
          ready: Future.value(),
          onlineAlexa: MemoryAlexaRepository(),
        ),
      );
      await tester.enterText(find.byKey(const Key('quick-add-todo')), 'Estudar offline');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Estudar offline'), findsWidgets, reason: 'aparece sem esperar a rede');
      expect(remote.rows('tasks'), isEmpty);
      expect(find.byKey(const Key('sync-status-icon')), findsNothing);

      await tester.pump(const Duration(seconds: 5));
      expect(find.byKey(const Key('sync-status-icon')), findsOneWidget);
      await tester.tap(find.byKey(const Key('sync-status-icon')));
      await tester.pumpAndSettle();
      expect(find.text('1 alteração aguardando envio'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      remote.online = true;
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(remote.rows('tasks'), hasLength(1));
      expect(find.byKey(const Key('sync-status-icon')), findsNothing);
    });

    testWidgets('"Tentar agora" do detalhe envia a fila sem esperar a próxima tentativa', (tester) async {
      unawaited(engine.start());
      remote.online = false;
      await pumpApp(
        tester,
        LocalFirstRepository(store),
        location: '/tarefas',
        repositoryOverrides: localFirstOverridesFor(
          userId: 'u1',
          store: store,
          engine: engine,
          ready: Future.value(),
          onlineAlexa: MemoryAlexaRepository(),
        ),
      );
      await tester.enterText(find.byKey(const Key('quick-add-todo')), 'Mandar já');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 5));
      remote.online = true;
      await tester.tap(find.byKey(const Key('sync-status-icon')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sync-retry')));
      await tester.pumpAndSettle();
      expect(remote.rows('tasks'), hasLength(1));
      expect(store.pendingNow, 0);
    });

    testWidgets('recusa do servidor vira o ícone de erro (detalhe "Não foi possível salvar") e a tarefa some da tela',
        (tester) async {
      unawaited(engine.start()); // dentro do relógio falso do teste: os timers do envio andam com o pump
      remote.reject = (tbl, op, row) => tbl == 'tasks' ? 'new row violates row-level security policy' : null;
      await pumpApp(
        tester,
        LocalFirstRepository(store),
        location: '/tarefas',
        repositoryOverrides: localFirstOverridesFor(
          userId: 'u1',
          store: store,
          engine: engine,
          ready: Future.value(),
          onlineAlexa: MemoryAlexaRepository(),
        ),
      );
      await tester.enterText(find.byKey(const Key('quick-add-todo')), 'Vai ser recusada');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byKey(const Key('sync-status-icon')), findsOneWidget);
      await tester.tap(find.byKey(const Key('sync-status-icon')));
      await tester.pumpAndSettle();
      expect(find.text('Não foi possível salvar: sem permissão'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sync-status-icon')), findsNothing);
      expect(find.text('Vai ser recusada'), findsNothing);
      expect(store.pendingNow, 0);
    });

    testWidgets('trocar de conta recria os provedores: nada da conta anterior aparece', (tester) async {
      final other = LocalStore.inMemory();
      addTearDown(other.close);
      await LocalFirstRepository(store).upsertTask(const TaskItem(id: 'a', title: 'Tarefa da Ana'));
      Widget scope(String user, LocalStore s) => ProviderScope(
            key: ValueKey(user),
            overrides: [
              repositoryProvider.overrideWithValue(LocalFirstRepository(s)),
              googleFontsEnabledProvider.overrideWithValue(false),
            ],
            child: Consumer(
              builder: (context, ref, _) => Directionality(
                textDirection: TextDirection.ltr,
                child: Text(ref.watch(tasksProvider).value?.map((t) => t.title).join(',') ?? 'carregando'),
              ),
            ),
          );
      await tester.pumpWidget(scope('ana', store));
      await tester.pump();
      expect(find.text('Tarefa da Ana'), findsOneWidget);
      await tester.pumpWidget(scope('beto', other));
      await tester.pump();
      expect(find.text('Tarefa da Ana'), findsNothing);
      expect(find.text(''), findsOneWidget);
    });
  });
}
