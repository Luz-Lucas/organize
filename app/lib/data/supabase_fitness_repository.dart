import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/agenda.dart';
import '../domain/ids.dart';
import '../domain/json.dart';
import '../domain/workout.dart';
import 'fitness_repository.dart';
import 'repository.dart';

class SupabaseFitnessRepository implements FitnessRepository {
  SupabaseFitnessRepository(this._db);

  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on PostgrestException catch (e) {
      throw RepositoryException(e.message, duplicate: e.code == '23505');
    } on RepositoryException {
      rethrow;
    } catch (e) {
      throw RepositoryException('Falha de conexão: $e');
    }
  }

  /// Junta dois streams do Supabase (tabelas pai e filha): emite quando ambos já tiveram um valor
  /// e a cada novo valor de qualquer um.
  Stream<R> _combine<A, B, R>(Stream<A> a, Stream<B> b, R Function(A, B) join) {
    StreamSubscription<A>? subA;
    StreamSubscription<B>? subB;
    A? lastA;
    B? lastB;
    var hasA = false, hasB = false;
    late final StreamController<R> controller;
    void emit() {
      if (hasA && hasB) controller.add(join(lastA as A, lastB as B));
    }

    controller = StreamController<R>(
      onListen: () {
        subA = a.listen((v) {
          lastA = v;
          hasA = true;
          emit();
        }, onError: controller.addError);
        subB = b.listen((v) {
          lastB = v;
          hasB = true;
          emit();
        }, onError: controller.addError);
      },
      onCancel: () async {
        await subA?.cancel();
        await subB?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Stream<List<Workout>> watchWorkouts() => _combine<List<Map<String, dynamic>>, List<Map<String, dynamic>>, List<Workout>>(
        _db.from('workouts').stream(primaryKey: ['id']).order('position', ascending: true),
        _db.from('workout_exercises').stream(primaryKey: ['id']).order('position', ascending: true),
        (ws, es) {
          final byWorkout = <String, List<WorkoutExercise>>{};
          for (final e in es.map(WorkoutExercise.fromMap)) {
            byWorkout.putIfAbsent(e.workoutId, () => []).add(e);
          }
          return [
            for (final w in ws.map(Workout.fromMap))
              w.copyWith(
                exercises: (byWorkout[w.id] ?? [])..sort((a, b) => a.position.compareTo(b.position)),
              ),
          ]..sort((a, b) => a.position.compareTo(b.position));
        },
      );

  @override
  Future<void> upsertWorkout(Workout w) => _guard(() async {
        await _db.from('workouts').upsert(w.toMap());
        final rows = await _db.from('workout_exercises').select('id').eq('workout_id', w.id);
        final kept = {for (final e in w.exercises) e.id};
        final gone = [for (final r in rows) r['id'] as String].where((id) => !kept.contains(id)).toList();
        if (gone.isNotEmpty) {
          await _db.from('workout_exercises').delete().inFilter('id', gone);
        }
        if (w.exercises.isNotEmpty) {
          await _db.from('workout_exercises').upsert([
            for (var i = 0; i < w.exercises.length; i++)
              w.exercises[i].copyWith(workoutId: w.id, position: i).toMap(),
          ]);
        }
      });

  @override
  Future<void> deleteWorkout(String id) => _guard(() async {
        await _db.from('workouts').delete().eq('id', id);
      });

  @override
  Future<void> reorderWorkouts(List<Workout> ordered) {
    if (ordered.isEmpty) return Future.value();
    return _guard(() async {
      await _db.from('workouts').upsert([
        for (var i = 0; i < ordered.length; i++) ordered[i].copyWith(position: i).toMap(),
      ]);
    });
  }

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Stream<List<WorkoutSession>> watchSessions({required DateTime from}) {
    final start = startOfDay(from);
    return _combine<List<Map<String, dynamic>>, List<Map<String, dynamic>>, List<WorkoutSession>>(
      _db.from('workout_sessions').stream(primaryKey: ['id']).gte('day', _day(start)),
      // A série nunca é anterior ao início da sessão, que nunca é anterior ao dia de corte.
      _db.from('set_logs').stream(primaryKey: ['id']).gte('done_at', start.toUtc().toIso8601String()),
      (sessions, logs) {
        final bySession = <String, List<SetLog>>{};
        for (final l in logs.map(SetLog.fromMap)) {
          bySession.putIfAbsent(l.sessionId, () => []).add(l);
        }
        return [
          for (final s in sessions.map(WorkoutSession.fromMap))
            s.copyWith(logs: (bySession[s.id] ?? [])..sort((a, b) => a.doneAt.compareTo(b.doneAt))),
        ]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
      },
    );
  }

  @override
  Future<WorkoutSession> startSession(Workout w, DateTime now) => _guard(() async {
        final s = WorkoutSession(
          id: newId(),
          workoutId: w.id,
          workoutName: w.name,
          day: startOfDay(now),
          startedAt: now,
        );
        await _db.from('workout_sessions').insert(s.toMap());
        return s;
      });

  @override
  Future<void> logSet(SetLog log) => _guard(() async {
        await _db.from('set_logs').upsert(log.toMap());
      });

  @override
  Future<void> deleteSetLog(String id) => _guard(() async {
        await _db.from('set_logs').delete().eq('id', id);
      });

  @override
  Future<void> finishSession(String id, DateTime at) => _guard(() async {
        await _db.from('workout_sessions').update({'finished_at': encodeDate(at)}).eq('id', id);
      });

  @override
  Future<void> deleteSession(String id) => _guard(() async {
        await _db.from('workout_sessions').delete().eq('id', id);
      });
}
