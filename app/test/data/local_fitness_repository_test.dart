import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/local_fitness_repository.dart';
import 'package:organizacional/domain/workout.dart';
import 'package:organizacional/sync/fake_remote_source.dart';
import 'package:organizacional/sync/local_store.dart';
import 'package:organizacional/sync/sync_engine.dart';

WorkoutExercise _ex(String id, String wid, String name, {int pos = 0}) =>
    WorkoutExercise(id: id, workoutId: wid, name: name, position: pos);

void main() {
  final now = DateTime(2026, 9, 28, 10);
  final from = DateTime(2026, 9, 1);
  late LocalStore store;
  late LocalFirstFitnessRepository repo;

  setUp(() {
    store = LocalStore.inMemory();
    repo = LocalFirstFitnessRepository(store);
  });
  tearDown(() => store.close());

  Future<List<WorkoutSession>> sessions() => repo.watchSessions(from: from).first;

  test('upsertWorkout grava a ficha e apaga os exercícios que saíram', () async {
    await repo.upsertWorkout(
        Workout(id: 'a', name: 'A', exercises: [_ex('1', 'a', 'Supino'), _ex('2', 'a', 'Remada', pos: 1)]));
    await repo.upsertWorkout(Workout(id: 'a', name: 'A2', exercises: [_ex('2', 'a', 'Remada')]));
    final ws = await repo.watchWorkouts().first;
    expect(ws.single.name, 'A2');
    expect(ws.single.exercises.map((e) => e.id), ['2']);
    expect(await store.get('workout_exercises', '1'), isNull);
  });

  test('upsertWorkout regrava as posições dos exercícios como 0..n-1 e liga à ficha', () async {
    await repo.upsertWorkout(Workout(id: 'a', name: 'A', exercises: [
      _ex('1', 'x', 'Supino', pos: 7),
      _ex('2', 'x', 'Remada', pos: 3),
    ]));
    final e = (await repo.watchWorkouts().first).single.exercises;
    expect(e.map((x) => x.id), ['1', '2']);
    expect(e.map((x) => x.position), [0, 1]);
    expect(e.map((x) => x.workoutId), ['a', 'a']);
  });

  test('fichas saem ordenadas por posição e reorderWorkouts regrava 0..n-1', () async {
    await repo.upsertWorkout(const Workout(id: 'a', name: 'A', position: 0));
    await repo.upsertWorkout(const Workout(id: 'b', name: 'B', position: 1));
    final ws = await repo.watchWorkouts().first;
    await repo.reorderWorkouts([ws[1], ws[0]]);
    final after = await repo.watchWorkouts().first;
    expect(after.map((w) => w.id), ['b', 'a']);
    expect(after.map((w) => w.position), [0, 1]);
  });

  test('startSession usa o dia de início e logSet faz upsert pelo id', () async {
    const w = Workout(id: 'a', name: 'Treino A');
    await repo.upsertWorkout(w);
    final s = await repo.startSession(w, now);
    expect(s.day, DateTime(2026, 9, 28));
    expect(s.workoutName, 'Treino A');
    final log = SetLog(id: 'l', sessionId: s.id, exerciseName: 'Supino', setIndex: 1, reps: 10, doneAt: now);
    await repo.logSet(log);
    await repo.logSet(log.copyWith(reps: 12));
    final got = (await sessions()).single;
    expect(got.workoutId, 'a');
    expect(got.startedAt, now);
    expect(got.logs.single.reps, 12);
  });

  test('deleteSetLog e finishSession', () async {
    final s = await repo.startSession(const Workout(id: 'a', name: 'A'), now);
    await repo.logSet(SetLog(id: 'l', sessionId: s.id, exerciseName: 'X', setIndex: 1, doneAt: now));
    await repo.deleteSetLog('l');
    await repo.finishSession(s.id, now.add(const Duration(hours: 1)));
    final got = (await sessions()).single;
    expect(got.logs, isEmpty);
    expect(got.finishedAt, now.add(const Duration(hours: 1)));
    expect(got.workoutName, 'A');
  });

  test('séries da sessão saem na ordem em que foram feitas', () async {
    final s = await repo.startSession(const Workout(id: 'a', name: 'A'), now);
    await repo.logSet(SetLog(
        id: 'b', sessionId: s.id, exerciseName: 'X', setIndex: 2, doneAt: now.add(const Duration(minutes: 2))));
    await repo.logSet(SetLog(id: 'a', sessionId: s.id, exerciseName: 'X', setIndex: 1, doneAt: now));
    expect((await sessions()).single.logs.map((l) => l.id), ['a', 'b']);
  });

  test('watchSessions respeita from (por dia) e traz o mais recente primeiro', () async {
    const w = Workout(id: 'a', name: 'A');
    await repo.startSession(w, DateTime(2026, 8, 1, 9));
    await repo.startSession(w, DateTime(2026, 9, 20, 9));
    await repo.startSession(w, DateTime(2026, 9, 25, 9));
    final got = await repo.watchSessions(from: DateTime(2026, 9, 20, 15)).first;
    expect(got.map((s) => s.startedAt.day), [25, 20]);
  });

  test('apagar exercício mantém a série (exerciseId nulo, nome preservado)', () async {
    final w = Workout(id: 'a', name: 'A', exercises: [_ex('1', 'a', 'Supino')]);
    await repo.upsertWorkout(w);
    final s = await repo.startSession(w, now);
    await repo.logSet(
        SetLog(id: 'l', sessionId: s.id, exerciseId: '1', exerciseName: 'Supino', setIndex: 1, doneAt: now));
    await repo.upsertWorkout(w.copyWith(exercises: const []));
    final log = (await sessions()).single.logs.single;
    expect(log.exerciseId, isNull);
    expect(log.exerciseName, 'Supino');
  });

  test('apagar ficha mantém a sessão sem ficha; deleteSession leva as séries', () async {
    final w = Workout(id: 'a', name: 'A', exercises: [_ex('1', 'a', 'Supino')]);
    await repo.upsertWorkout(w);
    final s = await repo.startSession(w, now);
    await repo.logSet(
        SetLog(id: 'l', sessionId: s.id, exerciseId: '1', exerciseName: 'Supino', setIndex: 1, doneAt: now));
    await repo.deleteWorkout('a');
    expect(await repo.watchWorkouts().first, isEmpty);
    expect(await store.all('workout_exercises'), isEmpty);
    final got = (await sessions()).single;
    expect(got.workoutId, isNull);
    expect(got.workoutName, 'A');
    expect(got.logs.single.exerciseId, isNull);
    await repo.deleteSession(s.id);
    expect(await sessions(), isEmpty);
    expect(await store.all('set_logs'), isEmpty);
  });

  test('o stream emite o estado novo a cada escrita', () async {
    final seen = <int>[];
    final sub = repo.watchWorkouts().listen((l) => seen.add(l.length));
    await repo.upsertWorkout(const Workout(id: 'a', name: 'A'));
    await repo.upsertWorkout(const Workout(id: 'b', name: 'B', position: 1));
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(seen.first, 0);
    expect(seen.last, 2);
  });

  test('escrever não precisa de rede: tudo vai para a fila de envio', () async {
    final w = Workout(id: 'a', name: 'A', exercises: [_ex('1', 'a', 'Supino')]);
    await repo.upsertWorkout(w);
    final s = await repo.startSession(w, now);
    await repo.logSet(SetLog(id: 'l', sessionId: s.id, exerciseName: 'Supino', setIndex: 1, doneAt: now));
    expect(store.pendingOutbox().map((e) => e.tbl).toSet(),
        {'workouts', 'workout_exercises', 'workout_sessions', 'set_logs'});
  });

  group('marcar de novo a mesma série (sessão + exercício + número)', () {
    test('reaproveita o id do registro existente em vez de criar outro', () async {
      final w = Workout(id: 'a', name: 'A', exercises: [_ex('1', 'a', 'Supino')]);
      await repo.upsertWorkout(w);
      final s = await repo.startSession(w, now);
      SetLog log(String id, {int? reps}) => SetLog(
          id: id, sessionId: s.id, exerciseId: '1', exerciseName: 'Supino', setIndex: 1, reps: reps, doneAt: now);
      await repo.logSet(log('primeiro', reps: 8));
      await repo.logSet(log('segundo', reps: 10));
      final logs = (await sessions()).single.logs;
      expect(logs.map((l) => l.id), ['primeiro']);
      expect(logs.single.reps, 10);
      expect((await store.all('set_logs')).map((r) => r['id']), ['primeiro']);
      // Nada na fila com o id descartado: a nuvem nunca vê duas linhas para a mesma série.
      expect(store.pendingOutbox().where((e) => e.tbl == 'set_logs').map((e) => e.id).toSet(), {'primeiro'});
    });

    test('séries diferentes (outro número ou outro exercício) continuam separadas', () async {
      final w = Workout(id: 'a', name: 'A', exercises: [_ex('1', 'a', 'Supino'), _ex('2', 'a', 'Remada', pos: 1)]);
      await repo.upsertWorkout(w);
      final s = await repo.startSession(w, now);
      SetLog log(String id, String ex, int n) => SetLog(
          id: id, sessionId: s.id, exerciseId: ex, exerciseName: 'X', setIndex: n, doneAt: now);
      await repo.logSet(log('a', '1', 1));
      await repo.logSet(log('b', '1', 2));
      await repo.logSet(log('c', '2', 1));
      expect((await sessions()).single.logs.map((l) => l.id).toSet(), {'a', 'b', 'c'});
    });

    test('desmarcar e marcar de novo cria um registro novo', () async {
      final w = Workout(id: 'a', name: 'A', exercises: [_ex('1', 'a', 'Supino')]);
      await repo.upsertWorkout(w);
      final s = await repo.startSession(w, now);
      SetLog log(String id) =>
          SetLog(id: id, sessionId: s.id, exerciseId: '1', exerciseName: 'Supino', setIndex: 1, doneAt: now);
      await repo.logSet(log('um'));
      await repo.deleteSetLog('um');
      await repo.logSet(log('dois'));
      expect((await sessions()).single.logs.map((l) => l.id), ['dois']);
    });

    test('dois toques seguidos sem esperar não geram duas séries', () async {
      final w = Workout(id: 'a', name: 'A', exercises: [_ex('1', 'a', 'Supino')]);
      await repo.upsertWorkout(w);
      final s = await repo.startSession(w, now);
      SetLog log(String id) =>
          SetLog(id: id, sessionId: s.id, exerciseId: '1', exerciseName: 'Supino', setIndex: 1, doneAt: now);
      await Future.wait([repo.logSet(log('x')), repo.logSet(log('y'))]);
      expect((await sessions()).single.logs, hasLength(1));
    });

    test('chega à nuvem uma única vez, com a chave natural intacta', () async {
      final remote = FakeRemoteSource();
      final engine = SyncEngine(store, remote,
          tables: const ['workouts', 'workout_exercises', 'workout_sessions', 'set_logs'],
          autoFlush: false,
          flushInterval: null,
          refreshInterval: null);
      addTearDown(() async {
        await engine.dispose();
        await remote.close();
      });
      final w = Workout(id: 'a', name: 'A', exercises: [_ex('1', 'a', 'Supino')]);
      await repo.upsertWorkout(w);
      final s = await repo.startSession(w, now);
      SetLog log(String id) =>
          SetLog(id: id, sessionId: s.id, exerciseId: '1', exerciseName: 'Supino', setIndex: 1, doneAt: now);
      await repo.logSet(log('um'));
      await repo.logSet(log('dois'));
      await engine.flush();
      expect(remote.rows('set_logs').map((r) => r['id']), ['um']);
      expect(store.pendingNow, 0);
    });
  });
}
