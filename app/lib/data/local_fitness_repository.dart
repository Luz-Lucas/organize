import 'dart:async';

import '../domain/agenda.dart';
import '../domain/ids.dart';
import '../domain/json.dart';
import '../domain/workout.dart';
import '../sync/local_store.dart';
import 'fitness_repository.dart';

const _workouts = 'workouts';
const _exercises = 'workout_exercises';
const _sessions = 'workout_sessions';
const _logs = 'set_logs';

/// Academia local-primeiro: lê e grava no [LocalStore] (a tela muda na hora, sem rede) e o
/// `SyncEngine` leva a fila à nuvem. Reproduz o que o banco faz com `on delete` (exercício apagado
/// mantém a série; ficha apagada mantém a sessão) e a "substituição" dos exercícios do `upsertWorkout`.
class LocalFirstFitnessRepository implements FitnessRepository {
  LocalFirstFitnessRepository(this._store);

  final LocalStore _store;

  /// Escritas que leem antes de gravar (`logSet`) rodam uma de cada vez.
  Future<void> _serial = Future.value();

  Future<T> _exclusive<T>(Future<T> Function() op) {
    final done = _serial.then((_) => op());
    _serial = done.then<void>((_) {}, onError: (_) {});
    return done;
  }

  /// Junta tabelas: emite quando todas já tiveram um valor e a cada novo valor de qualquer uma.
  Stream<R> _watchTables<R>(List<String> tables, R Function(List<List<Map<String, dynamic>>>) join) {
    final subs = <StreamSubscription<List<Map<String, dynamic>>>>[];
    final last = List<List<Map<String, dynamic>>?>.filled(tables.length, null);
    late final StreamController<R> controller;
    controller = StreamController<R>(
      onListen: () {
        for (var i = 0; i < tables.length; i++) {
          subs.add(_store.watch(tables[i]).listen((v) {
            last[i] = v;
            if (!controller.isClosed && last.every((x) => x != null)) {
              controller.add(join([for (final x in last) x!]));
            }
          }, onError: controller.addError));
        }
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
      },
    );
    return controller.stream;
  }

  /// Só as colunas graváveis (a cópia local também guarda as que só o servidor preenche).
  static Map<String, dynamic> _pick(Map<String, dynamic> raw, Iterable<String> columns) =>
      {for (final c in columns) if (raw.containsKey(c)) c: raw[c]};

  static WorkoutSession _session(Map<String, dynamic> r, Set<Object?> workoutIds, List<SetLog> logs) {
    final s = WorkoutSession.fromMap(r);
    return WorkoutSession(
      id: s.id,
      workoutId: workoutIds.contains(s.workoutId) ? s.workoutId : null,
      workoutName: s.workoutName,
      day: s.day,
      startedAt: s.startedAt,
      finishedAt: s.finishedAt,
      logs: logs,
    );
  }

  static const _sessionColumns = ['id', 'workout_id', 'workout_name', 'day', 'started_at', 'finished_at'];

  // ---------------------------------------------------------------- fichas

  @override
  Stream<List<Workout>> watchWorkouts() => _watchTables([_workouts, _exercises], (t) {
        final (ws, es) = (t[0], t[1]);
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
      });

  @override
  Future<void> upsertWorkout(Workout w) async {
    await _store.put(_workouts, w.toMap());
    final kept = {for (final e in w.exercises) e.id};
    final gone = [
      for (final r in await _store.all(_exercises))
        if (r['workout_id'] == w.id && !kept.contains(r['id'])) r['id'] as String,
    ];
    if (gone.isNotEmpty) {
      await _store.removeMany(_exercises, gone);
    }
    if (w.exercises.isNotEmpty) {
      await _store.putMany(_exercises, [
        for (var i = 0; i < w.exercises.length; i++) w.exercises[i].copyWith(workoutId: w.id, position: i).toMap(),
      ]);
    }
  }

  @override
  Future<void> deleteWorkout(String id) async {
    final exerciseIds = [
      for (final r in await _store.all(_exercises))
        if (r['workout_id'] == id) r['id'] as String,
    ];
    await _store.removeMany(_exercises, exerciseIds);
    await _store.remove(_workouts, id);
  }

  @override
  Future<void> reorderWorkouts(List<Workout> ordered) async {
    if (ordered.isEmpty) return;
    final rows = <Map<String, dynamic>>[];
    for (var i = 0; i < ordered.length; i++) {
      final cur = await _store.get(_workouts, ordered[i].id);
      if (cur != null) rows.add(_pick(cur, ['id', 'name'])..['position'] = i);
    }
    await _store.putMany(_workouts, rows);
  }

  // ---------------------------------------------------------------- sessões

  @override
  Stream<List<WorkoutSession>> watchSessions({required DateTime from}) {
    final start = startOfDay(from);
    return _watchTables([_sessions, _logs, _workouts, _exercises], (t) {
      // `on delete set null` do banco, aplicado na leitura: a ficha ou o exercício apagado some do vínculo
      // (o histórico fica) sem reenviar a linha. Reenviar a série com `exercise_id` nulo seria recusado:
      // a chave natural não casa com nulos e o `id` já existe.
      final workoutIds = {for (final r in t[2]) r['id']};
      final exerciseIds = {for (final r in t[3]) r['id']};
      final bySession = <String, List<SetLog>>{};
      for (final r in t[1]) {
        final l = SetLog.fromMap(r);
        bySession.putIfAbsent(l.sessionId, () => []).add(exerciseIds.contains(l.exerciseId) ? l : l.copyWith(clearExercise: true));
      }
      return [
        for (final r in t[0])
          if (!WorkoutSession.fromMap(r).day.isBefore(start))
            _session(r, workoutIds, (bySession[r['id']] ?? [])..sort((a, b) => a.doneAt.compareTo(b.doneAt))),
      ]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    });
  }

  @override
  Future<WorkoutSession> startSession(Workout w, DateTime now) async {
    final s = WorkoutSession(
      id: newId(),
      workoutId: w.id,
      workoutName: w.name,
      day: startOfDay(now),
      startedAt: now,
    );
    await _store.put(_sessions, s.toMap());
    return s;
  }

  /// Se já existe o registro daquela série (mesma sessão + exercício + número), o `id` dele é reaproveitado:
  /// marcar de novo corrige o registro em vez de criar outro (a nuvem recusaria a chave repetida).
  @override
  Future<void> logSet(SetLog log) => _exclusive(() async {
        var id = log.id;
        final exerciseId = log.exerciseId;
        if (exerciseId != null) {
          for (final r in await _store.all(_logs)) {
            if (r['session_id'] == log.sessionId && r['exercise_id'] == exerciseId && r['set_index'] == log.setIndex) {
              id = r['id'] as String;
              break;
            }
          }
        }
        final map = log.toMap();
        map['id'] = id;
        await _store.put(_logs, map);
      });

  @override
  Future<void> deleteSetLog(String id) async {
    if (await _store.get(_logs, id) != null) await _store.remove(_logs, id);
  }

  @override
  Future<void> finishSession(String id, DateTime at) async {
    final cur = await _store.get(_sessions, id);
    if (cur == null) return;
    await _store.put(_sessions, _pick(cur, _sessionColumns)..['finished_at'] = encodeDate(at));
  }

  @override
  Future<void> deleteSession(String id) async {
    final logIds = [
      for (final r in await _store.all(_logs))
        if (r['session_id'] == id) r['id'] as String,
    ];
    await _store.removeMany(_logs, logIds);
    await _store.remove(_sessions, id);
  }
}
