import 'dart:async';

import '../domain/agenda.dart';
import '../domain/ids.dart';
import '../domain/workout.dart';
import 'repository.dart';

abstract interface class FitnessRepository {
  /// Fichas por posição, já com os exercícios em ordem.
  Stream<List<Workout>> watchWorkouts();

  /// Grava a ficha e **substitui** os exercícios: os que não estão em [Workout.exercises] são apagados.
  Future<void> upsertWorkout(Workout w);
  Future<void> deleteWorkout(String id);

  /// Regrava as posições das fichas como 0..n-1, na ordem recebida.
  Future<void> reorderWorkouts(List<Workout> ordered);

  /// Sessões que começaram em [from] (dia) ou depois, da mais recente para a mais antiga, com as séries.
  Stream<List<WorkoutSession>> watchSessions({required DateTime from});

  /// Abre uma sessão no dia de [now].
  Future<WorkoutSession> startSession(Workout w, DateTime now);

  /// Grava (ou corrige) uma série; a chave é o `id`.
  Future<void> logSet(SetLog log);
  Future<void> deleteSetLog(String id);
  Future<void> finishSession(String id, DateTime at);

  /// Apaga a sessão e as séries dela.
  Future<void> deleteSession(String id);
}

/// Implementação em memória para testes; reproduz os `on delete` do banco.
class MemoryFitnessRepository implements FitnessRepository {
  final _workouts = <String, Workout>{};
  final _sessions = <String, WorkoutSession>{};
  final _logs = <String, SetLog>{};
  final _changes = StreamController<void>.broadcast(sync: true);

  /// Quando true, toda escrita falha, simulando uma queda de conexão.
  bool failWrites = false;

  Stream<List<T>> _watch<T>(List<T> Function() snapshot) {
    StreamSubscription<void>? sub;
    late final StreamController<List<T>> controller;
    controller = StreamController<List<T>>(
      onListen: () {
        controller.add(snapshot());
        sub = _changes.stream.listen((_) => controller.add(snapshot()));
      },
      onCancel: () {
        sub?.cancel();
        controller.close();
      },
    );
    return controller.stream;
  }

  Future<T> _write<T>(T Function() change) async {
    if (failWrites) throw const RepositoryException('Sem conexão (simulado)');
    final r = change();
    _changes.add(null);
    return r;
  }

  @override
  Stream<List<Workout>> watchWorkouts() => _watch(() {
        final list = _workouts.values.toList()..sort((a, b) => a.position.compareTo(b.position));
        return [
          for (final w in list)
            w.copyWith(exercises: [...w.exercises]..sort((a, b) => a.position.compareTo(b.position))),
        ];
      });

  @override
  Future<void> upsertWorkout(Workout w) => _write(() {
        final kept = {for (final e in w.exercises) e.id};
        final old = _workouts[w.id]?.exercises ?? const [];
        for (final e in old.where((e) => !kept.contains(e.id))) {
          _forgetExercise(e.id);
        }
        _workouts[w.id] = w.copyWith(exercises: [
          for (var i = 0; i < w.exercises.length; i++)
            w.exercises[i].copyWith(workoutId: w.id, position: i),
        ]);
      });

  // `on delete set null` em set_logs.exercise_id
  void _forgetExercise(String exerciseId) {
    for (final l in _logs.values.where((l) => l.exerciseId == exerciseId).toList()) {
      _logs[l.id] = l.copyWith(clearExercise: true);
    }
  }

  @override
  Future<void> deleteWorkout(String id) => _write(() {
        final w = _workouts.remove(id);
        if (w == null) return;
        for (final e in w.exercises) {
          _forgetExercise(e.id);
        }
        for (final s in _sessions.values.where((s) => s.workoutId == id).toList()) {
          _sessions[s.id] = WorkoutSession(
            id: s.id,
            workoutName: s.workoutName,
            day: s.day,
            startedAt: s.startedAt,
            finishedAt: s.finishedAt,
          );
        }
      });

  @override
  Future<void> reorderWorkouts(List<Workout> ordered) => _write(() {
        for (var i = 0; i < ordered.length; i++) {
          final cur = _workouts[ordered[i].id];
          if (cur != null) _workouts[cur.id] = cur.copyWith(position: i);
        }
      });

  @override
  Stream<List<WorkoutSession>> watchSessions({required DateTime from}) => _watch(() {
        final start = startOfDay(from);
        final list = _sessions.values.where((s) => !s.day.isBefore(start)).toList()
          ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
        return [
          for (final s in list)
            s.copyWith(
              logs: _logs.values.where((l) => l.sessionId == s.id).toList()
                ..sort((a, b) => a.doneAt.compareTo(b.doneAt)),
            ),
        ];
      });

  @override
  Future<WorkoutSession> startSession(Workout w, DateTime now) => _write(() {
        final s = WorkoutSession(
          id: newId(),
          workoutId: w.id,
          workoutName: w.name,
          day: startOfDay(now),
          startedAt: now,
        );
        _sessions[s.id] = s;
        return s;
      });

  @override
  Future<void> logSet(SetLog log) => _write(() => _logs[log.id] = log);

  @override
  Future<void> deleteSetLog(String id) => _write(() => _logs.remove(id));

  @override
  Future<void> finishSession(String id, DateTime at) => _write(() {
        final s = _sessions[id];
        if (s != null) _sessions[id] = s.copyWith(finishedAt: at);
      });

  @override
  Future<void> deleteSession(String id) => _write(() {
        _sessions.remove(id);
        _logs.removeWhere((_, l) => l.sessionId == id);
      });
}
