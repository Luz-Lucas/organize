import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/domain/calendar_event.dart';
import 'package:organizacional/domain/event_tag.dart';
import 'package:organizacional/domain/workout.dart';

WorkoutExercise _ex(String id, String wid, String name, {int sets = 3, int pos = 0}) =>
    WorkoutExercise(id: id, workoutId: wid, name: name, sets: sets, position: pos);

Workout _w(String id, String name, int pos, [List<WorkoutExercise> ex = const []]) =>
    Workout(id: id, name: name, position: pos, exercises: ex);

WorkoutSession _s(String id, String? wid, DateTime start,
        {DateTime? finished, List<SetLog> logs = const [], String name = 'Treino'}) =>
    WorkoutSession(
      id: id,
      workoutId: wid,
      workoutName: name,
      day: DateTime(start.year, start.month, start.day),
      startedAt: start,
      finishedAt: finished,
      logs: logs,
    );

SetLog _log(String id, String sid, String? exId, String exName, int idx, DateTime at,
        {int? reps = 10}) =>
    SetLog(id: id, sessionId: sid, exerciseId: exId, exerciseName: exName, setIndex: idx, reps: reps, doneAt: at);

CalendarEvent _ev(String title, DateTime start, {String? tagId, bool allDay = false}) => CalendarEvent(
      id: 'e-$title-${start.hour}',
      title: title,
      startsAt: start,
      endsAt: start.add(const Duration(hours: 1)),
      allDay: allDay,
      tagId: tagId,
    );

void main() {
  final now = DateTime(2026, 9, 28, 10); // segunda-feira
  final a = _w('a', 'Treino A', 0, [_ex('a1', 'a', 'Supino', sets: 3), _ex('a2', 'a', 'Remada', sets: 3)]);
  final b = _w('b', 'Treino B', 1, [_ex('b1', 'b', 'Agachamento', sets: 4)]);
  final c = _w('c', 'Treino C', 2);

  group('isGymEvent', () {
    const tags = {'t': EventTag(id: 't', name: 'Academia', color: '#30A46C')};

    test('reconhece pelo título, sem acento e sem diferenciar maiúsculas', () {
      expect(isGymEvent(_ev('Academia', now), {}), isTrue);
      expect(isGymEvent(_ev('TREINO de pernas', now), {}), isTrue);
      expect(isGymEvent(_ev('Musculação', now), {}), isTrue);
      expect(isGymEvent(_ev('Aula de cálculo', now), {}), isFalse);
    });

    test('reconhece pelo nome da etiqueta', () {
      expect(isGymEvent(_ev('Pernas', now, tagId: 't'), tags), isTrue);
      expect(isGymEvent(_ev('Pernas', now, tagId: 'outra'), tags), isFalse);
      expect(isGymEvent(_ev('Pernas', now), tags), isFalse);
    });

    test('etiqueta com acento e caixa diferentes', () {
      const t = {'x': EventTag(id: 'x', name: 'MUSCULAÇÃO', color: '#000000')};
      expect(isGymEvent(_ev('Pernas', now, tagId: 'x'), t), isTrue);
    });
  });

  group('nextWorkout', () {
    test('sem fichas devolve nulo', () {
      expect(nextWorkout([], []), isNull);
    });

    test('nunca treinou: a primeira', () {
      expect(nextWorkout([b, a, c], [])?.id, 'a');
    });

    test('segue a ordem a partir do último treino feito e volta ao início', () {
      final s1 = _s('s1', 'a', DateTime(2026, 9, 20, 9), finished: DateTime(2026, 9, 20, 10));
      expect(nextWorkout([a, b, c], [s1])?.id, 'b');
      final s2 = _s('s2', 'b', DateTime(2026, 9, 22, 9), finished: DateTime(2026, 9, 22, 10));
      expect(nextWorkout([a, b, c], [s1, s2])?.id, 'c');
      final s3 = _s('s3', 'c', DateTime(2026, 9, 24, 9), finished: DateTime(2026, 9, 24, 10));
      expect(nextWorkout([a, b, c], [s1, s2, s3])?.id, 'a');
    });

    test('ignora sessão não finalizada e ficha apagada', () {
      final open = _s('o', 'a', DateTime(2026, 9, 27, 9));
      expect(nextWorkout([a, b], [open])?.id, 'a');
      final gone = _s('g', null, DateTime(2026, 9, 27, 9), finished: DateTime(2026, 9, 27, 10));
      expect(nextWorkout([a, b], [gone])?.id, 'a');
    });
  });

  group('lastSetFor', () {
    final older = _s('s1', 'a', DateTime(2026, 9, 20, 9), finished: DateTime(2026, 9, 20, 10), logs: [
      _log('l1', 's1', 'a1', 'Supino', 1, DateTime(2026, 9, 20, 9, 10), reps: 8),
    ]);
    final newer = _s('s2', 'a', DateTime(2026, 9, 24, 9), finished: DateTime(2026, 9, 24, 10), logs: [
      _log('l2', 's2', 'a1', 'Supino', 1, DateTime(2026, 9, 24, 9, 10), reps: 10),
      _log('l3', 's2', null, 'Remada', 1, DateTime(2026, 9, 24, 9, 20), reps: 12),
    ]);

    test('devolve a série mais recente do exercício, por id', () {
      expect(lastSetFor('a1', 'Supino', [older, newer])?.reps, 10);
    });

    test('sem id correspondente, procura pelo nome (sem acento/caixa)', () {
      expect(lastSetFor('x9', 'remada', [older, newer])?.reps, 12);
    });

    test('nunca feito devolve nulo', () {
      expect(lastSetFor('z', 'Rosca', [older, newer]), isNull);
    });
  });

  group('exerciseProgress', () {
    test('uma linha por sessão com as repetições de cada série, mais recente primeiro', () {
      final s1 = _s('s1', 'a', DateTime(2026, 9, 20, 9), logs: [
        _log('l2', 's1', 'a1', 'Supino', 2, DateTime(2026, 9, 20, 9, 12), reps: 8),
        _log('l1', 's1', 'a1', 'Supino', 1, DateTime(2026, 9, 20, 9, 10), reps: 10),
        _log('l0', 's1', 'a1', 'Supino', 3, DateTime(2026, 9, 20, 9, 14), reps: null),
      ]);
      final s2 = _s('s2', 'a', DateTime(2026, 9, 24, 9), logs: [
        _log('l3', 's2', 'a1', 'Supino', 1, DateTime(2026, 9, 24, 9, 10), reps: 6),
      ]);
      final p = exerciseProgress('a1', 'Supino', [s1, s2]);
      expect(p.map((e) => e.day), [DateTime(2026, 9, 24), DateTime(2026, 9, 20)]);
      expect(p[1].reps, [10, 8]);
      expect(p[1].maxReps, 10);
      expect(p[1].sets, 3);
      expect(p[0].reps, [6]);
    });

    test('sessão sem repetições registradas: maxReps nulo', () {
      final s1 = _s('s1', 'a', DateTime(2026, 9, 20, 9), logs: [
        _log('l1', 's1', 'a1', 'Supino', 1, DateTime(2026, 9, 20, 9, 10), reps: null),
      ]);
      final p = exerciseProgress('a1', 'Supino', [s1]);
      expect(p.single.reps, isEmpty);
      expect(p.single.maxReps, isNull);
      expect(p.single.sets, 1);
    });
  });

  group('gymToday', () {
    const tags = <String, EventTag>{};
    GymToday run({
      List<Workout> ws = const [],
      List<WorkoutSession> ss = const [],
      List<CalendarEvent> evs = const [],
      DateTime? at,
    }) =>
        gymToday(now: at ?? now, events: evs, tags: tags, workouts: ws, sessions: ss);

    test('sem fichas', () {
      expect(run(), isA<GymNoWorkouts>());
    });

    test('sem evento de academia: descanso com a próxima ficha', () {
      final r = run(ws: [a, b]);
      expect(r, isA<GymRest>());
      expect((r as GymRest).next?.id, 'a');
    });

    test('com evento de academia hoje: treino planejado', () {
      final r = run(ws: [a, b], evs: [_ev('Academia', DateTime(2026, 9, 28, 18))]);
      expect(r, isA<GymPlanned>());
      expect((r as GymPlanned).w.id, 'a');
    });

    test('evento de academia de outro dia não conta', () {
      expect(run(ws: [a], evs: [_ev('Academia', DateTime(2026, 9, 29, 18))]), isA<GymRest>());
    });

    test('sessão aberta hoje: em andamento com progresso', () {
      final open = _s('s', 'a', DateTime(2026, 9, 28, 9), logs: [
        _log('l1', 's', 'a1', 'Supino', 1, DateTime(2026, 9, 28, 9, 5)),
        _log('l2', 's', 'a1', 'Supino', 2, DateTime(2026, 9, 28, 9, 8)),
      ]);
      final r = run(ws: [a, b], ss: [open]);
      expect(r, isA<GymInProgress>());
      r as GymInProgress;
      expect(r.doneSets, 2);
      expect(r.totalSets, 6);
      expect(r.s.id, 's');
    });

    test('ficha apagada: total vira o número de séries feitas', () {
      final open = _s('s', null, DateTime(2026, 9, 28, 9), logs: [
        _log('l1', 's', null, 'Supino', 1, DateTime(2026, 9, 28, 9, 5)),
      ]);
      final r = run(ws: [a], ss: [open]) as GymInProgress;
      expect(r.totalSets, 1);
    });

    test('sessão finalizada hoje: feito', () {
      final done = _s('s', 'a', DateTime(2026, 9, 28, 8), finished: DateTime(2026, 9, 28, 9));
      final r = run(ws: [a, b], ss: [done]);
      expect(r, isA<GymDone>());
      expect((r as GymDone).s.id, 's');
    });

    test('virada do dia: sessão aberta ontem não aparece como em andamento', () {
      final yesterday = _s('s', 'a', DateTime(2026, 9, 27, 21));
      final r = run(ws: [a, b], ss: [yesterday], at: DateTime(2026, 9, 28, 7));
      expect(r, isA<GymRest>());
    });

    test('treino em andamento vale mais que um já feito hoje', () {
      final done = _s('d', 'a', DateTime(2026, 9, 28, 7), finished: DateTime(2026, 9, 28, 8));
      final open = _s('o', 'b', DateTime(2026, 9, 28, 9));
      expect(run(ws: [a, b], ss: [done, open]), isA<GymInProgress>());
    });
  });

  group('serialização', () {
    test('WorkoutExercise vai e volta do mapa do banco', () {
      final e = WorkoutExercise(
          id: 'x', workoutId: 'w', name: 'Supino', sets: 4, reps: '8–12', notes: 'n', position: 2);
      expect(WorkoutExercise.fromMap(e.toMap()), e);
      expect(e.toMap()['workout_id'], 'w');
    });

    test('o mapa do exercício não envia carga nem descanso (o banco usa os padrões)', () {
      const e = WorkoutExercise(id: 'x', workoutId: 'w', name: 'Supino');
      expect(e.toMap().keys, isNot(contains('load_kg')));
      expect(e.toMap().keys, isNot(contains('rest_seconds')));
    });

    test('fromMap ignora load_kg e rest_seconds que o banco ainda devolve', () {
      final e = WorkoutExercise.fromMap(
          {'id': 'x', 'workout_id': 'w', 'name': 'Barra', 'load_kg': 20, 'rest_seconds': 60});
      expect(e.sets, 3);
      expect(e.reps, '10');
      expect(e, const WorkoutExercise(id: 'x', workoutId: 'w', name: 'Barra'));
    });

    test('WorkoutSession usa day como data pura e fromMap lê o fuso local', () {
      final s = WorkoutSession(
          id: 's', workoutId: null, workoutName: 'A', day: DateTime(2026, 9, 28), startedAt: DateTime(2026, 9, 28, 9));
      final m = s.toMap();
      expect(m['day'], '2026-09-28');
      expect(m['workout_id'], isNull);
      final back = WorkoutSession.fromMap(m);
      expect(back.day, DateTime(2026, 9, 28));
      expect(back.startedAt, DateTime(2026, 9, 28, 9));
    });

    test('SetLog ignora load_kg que o banco ainda devolve e não o envia', () {
      final l = SetLog.fromMap({
        'id': 'l',
        'session_id': 's',
        'exercise_id': null,
        'exercise_name': 'Supino',
        'set_index': 1,
        'reps': 10,
        'load_kg': '22.50',
        'done_at': '2026-09-28T12:00:00Z',
      });
      expect(l.reps, 10);
      expect(l.exerciseId, isNull);
      expect(l.toMap().keys, isNot(contains('load_kg')));
    });
  });

  group('repetições', () {
    test('firstInt tira o primeiro número de "8–12"', () {
      expect(firstInt('8–12'), 8);
      expect(firstInt('10'), 10);
      expect(firstInt('até a falha'), isNull);
    });
  });
}
