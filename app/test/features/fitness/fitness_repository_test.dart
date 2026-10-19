import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/fitness_repository.dart';
import 'package:organizacional/data/repository.dart';
import 'package:organizacional/domain/workout.dart';

WorkoutExercise _ex(String id, String wid, String name, {int pos = 0}) =>
    WorkoutExercise(id: id, workoutId: wid, name: name, position: pos);

void main() {
  final now = DateTime(2026, 9, 28, 10);

  test('upsertWorkout grava a ficha e apaga os exercícios que saíram', () async {
    final repo = MemoryFitnessRepository();
    await repo.upsertWorkout(Workout(id: 'a', name: 'A', exercises: [_ex('1', 'a', 'Supino'), _ex('2', 'a', 'Remada', pos: 1)]));
    await repo.upsertWorkout(Workout(id: 'a', name: 'A2', exercises: [_ex('2', 'a', 'Remada')]));
    final ws = await repo.watchWorkouts().first;
    expect(ws.single.name, 'A2');
    expect(ws.single.exercises.map((e) => e.id), ['2']);
  });

  test('fichas saem ordenadas por posição e reorderWorkouts regrava 0..n-1', () async {
    final repo = MemoryFitnessRepository();
    await repo.upsertWorkout(const Workout(id: 'a', name: 'A', position: 0));
    await repo.upsertWorkout(const Workout(id: 'b', name: 'B', position: 1));
    final ws = await repo.watchWorkouts().first;
    await repo.reorderWorkouts([ws[1], ws[0]]);
    final after = await repo.watchWorkouts().first;
    expect(after.map((w) => w.id), ['b', 'a']);
    expect(after.map((w) => w.position), [0, 1]);
  });

  test('startSession usa o dia de início e logSet faz upsert pelo id', () async {
    final repo = MemoryFitnessRepository();
    const w = Workout(id: 'a', name: 'Treino A');
    await repo.upsertWorkout(w);
    final s = await repo.startSession(w, now);
    expect(s.day, DateTime(2026, 9, 28));
    expect(s.workoutName, 'Treino A');
    final log = SetLog(id: 'l', sessionId: s.id, exerciseName: 'Supino', setIndex: 1, reps: 10, doneAt: now);
    await repo.logSet(log);
    await repo.logSet(log.copyWith(reps: 12));
    final got = (await repo.watchSessions(from: DateTime(2026, 9, 1)).first).single;
    expect(got.logs.single.reps, 12);
  });

  test('deleteSetLog e finishSession', () async {
    final repo = MemoryFitnessRepository();
    final s = await repo.startSession(const Workout(id: 'a', name: 'A'), now);
    await repo.logSet(SetLog(id: 'l', sessionId: s.id, exerciseName: 'X', setIndex: 1, doneAt: now));
    await repo.deleteSetLog('l');
    await repo.finishSession(s.id, now.add(const Duration(hours: 1)));
    final got = (await repo.watchSessions(from: DateTime(2026, 9, 1)).first).single;
    expect(got.logs, isEmpty);
    expect(got.finishedAt, now.add(const Duration(hours: 1)));
  });

  test('watchSessions respeita from (por dia) e traz o mais recente primeiro', () async {
    final repo = MemoryFitnessRepository();
    const w = Workout(id: 'a', name: 'A');
    await repo.startSession(w, DateTime(2026, 8, 1, 9));
    await repo.startSession(w, DateTime(2026, 9, 20, 9));
    await repo.startSession(w, DateTime(2026, 9, 25, 9));
    final got = await repo.watchSessions(from: DateTime(2026, 9, 20, 15)).first;
    expect(got.map((s) => s.startedAt.day), [25, 20]);
  });

  test('apagar exercício mantém a série (exerciseId nulo, nome preservado)', () async {
    final repo = MemoryFitnessRepository();
    final w = Workout(id: 'a', name: 'A', exercises: [_ex('1', 'a', 'Supino')]);
    await repo.upsertWorkout(w);
    final s = await repo.startSession(w, now);
    await repo.logSet(SetLog(id: 'l', sessionId: s.id, exerciseId: '1', exerciseName: 'Supino', setIndex: 1, doneAt: now));
    await repo.upsertWorkout(w.copyWith(exercises: const []));
    final log = (await repo.watchSessions(from: DateTime(2026, 9, 1)).first).single.logs.single;
    expect(log.exerciseId, isNull);
    expect(log.exerciseName, 'Supino');
  });

  test('apagar ficha mantém a sessão sem ficha; deleteSession leva as séries', () async {
    final repo = MemoryFitnessRepository();
    final w = Workout(id: 'a', name: 'A', exercises: [_ex('1', 'a', 'Supino')]);
    await repo.upsertWorkout(w);
    final s = await repo.startSession(w, now);
    await repo.logSet(SetLog(id: 'l', sessionId: s.id, exerciseId: '1', exerciseName: 'Supino', setIndex: 1, doneAt: now));
    await repo.deleteWorkout('a');
    expect(await repo.watchWorkouts().first, isEmpty);
    final got = (await repo.watchSessions(from: DateTime(2026, 9, 1)).first).single;
    expect(got.workoutId, isNull);
    expect(got.logs.single.exerciseId, isNull);
    await repo.deleteSession(s.id);
    expect(await repo.watchSessions(from: DateTime(2026, 9, 1)).first, isEmpty);
  });

  test('failWrites faz toda escrita falhar', () async {
    final repo = MemoryFitnessRepository()..failWrites = true;
    expect(() => repo.upsertWorkout(const Workout(id: 'a', name: 'A')), throwsA(isA<RepositoryException>()));
    expect(() => repo.startSession(const Workout(id: 'a', name: 'A'), now), throwsA(isA<RepositoryException>()));
  });

  test('o stream emite de novo a cada escrita', () async {
    final repo = MemoryFitnessRepository();
    final seen = <int>[];
    final sub = repo.watchWorkouts().listen((l) => seen.add(l.length));
    await repo.upsertWorkout(const Workout(id: 'a', name: 'A'));
    await repo.upsertWorkout(const Workout(id: 'b', name: 'B', position: 1));
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(seen, [0, 1, 2]);
  });
}
