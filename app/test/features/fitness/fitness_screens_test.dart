import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/fitness_repository.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/calendar_event.dart';
import 'package:organizacional/domain/workout.dart';
import 'package:organizacional/features/fitness/fitness_screen.dart';
import 'package:organizacional/features/fitness/workout_editor_screen.dart';
import 'package:organizacional/features/fitness/workout_session_screen.dart';
import 'package:organizacional/features/fitness/workout_today_card.dart';

import 'fitness_harness.dart';

WorkoutExercise _ex(String id, String wid, String name, {int sets = 3, String reps = '10', int pos = 0}) =>
    WorkoutExercise(id: id, workoutId: wid, name: name, sets: sets, reps: reps, position: pos);

final _fichaA = Workout(id: 'a', name: 'Treino A', position: 0, exercises: [
  _ex('a1', 'a', 'Supino'),
  _ex('a2', 'a', 'Remada', pos: 1),
]);

Future<List<WorkoutSession>> _sessions(MemoryFitnessRepository fit) =>
    fit.watchSessions(from: DateTime(2026, 1, 1)).first;

void main() {
  group('Academia: fluxo completo', () {
    testWidgets('cria ficha com 2 exercícios, treina com as repetições da última vez, desmarca e finaliza', (tester) async {
      final fit = MemoryFitnessRepository();
      // Treino antigo (ficha que não existe mais): Supino com 8 repetições.
      final old = await fit.startSession(const Workout(id: 'old', name: 'Antigo'), DateTime(2026, 9, 21, 9));
      await fit.logSet(SetLog(
          id: 'o1', sessionId: old.id, exerciseName: 'Supino', setIndex: 1, reps: 8, doneAt: DateTime(2026, 9, 21, 9, 10)));
      await fit.finishSession(old.id, DateTime(2026, 9, 21, 10));

      await pumpFitness(tester, const FitnessScreen(), fit: fit);
      expect(find.byKey(const Key('gym-create')), findsOneWidget);

      await tapKey(tester, 'gym-create');
      await tester.enterText(find.byKey(const Key('workout-name')), 'Treino A');
      await tapKey(tester, 'exercise-add');
      await tester.enterText(find.byKey(const Key('exercise-name-0')), 'Supino');
      await tapKey(tester, 'exercise-add');
      await tester.enterText(find.byKey(const Key('exercise-name-1')), 'Remada');
      await tapKey(tester, 'workout-save');

      final ws = await fit.watchWorkouts().first;
      expect(ws, hasLength(1));
      expect(ws.single.name, 'Treino A');
      expect(ws.single.exercises.map((e) => e.name), ['Supino', 'Remada']);
      expect(find.text('Treino A'), findsWidgets);

      // Sem evento de academia hoje: "Treinar mesmo assim".
      expect(find.text('Treinar mesmo assim'), findsOneWidget);
      await tapKey(tester, 'gym-start');

      expect(find.byType(WorkoutSessionScreen), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const Key('set-reps-0-1'))).controller!.text, '8');
      // Remada nunca foi feita: repetições do planejado.
      expect(tester.widget<TextField>(find.byKey(const Key('set-reps-1-1'))).controller!.text, '10');
      // Não existe mais campo de carga.
      expect(find.byKey(const Key('set-load-0-1')), findsNothing);
      expect(find.text('kg'), findsNothing);

      await tapKey(tester, 'set-check-0-1', settle: false);
      var s = (await _sessions(fit)).firstWhere((s) => s.workoutId == ws.single.id);
      expect(s.logs, hasLength(1));
      expect(s.logs.single.reps, 8);
      expect(s.logs.single.exerciseName, 'Supino');
      expect(s.logs.single.exerciseId, ws.single.exercises.first.id);
      // Sem cronômetro de descanso entre as séries.
      expect(find.byKey(const Key('rest-timer')), findsNothing);

      await tapKey(tester, 'set-check-0-1', settle: false);
      s = (await _sessions(fit)).firstWhere((s) => s.workoutId == ws.single.id);
      expect(s.logs, isEmpty);

      await tapKey(tester, 'set-check-0-1', settle: false);
      await tapKey(tester, 'session-finish');

      s = (await _sessions(fit)).firstWhere((s) => s.workoutId == ws.single.id);
      expect(s.isFinished, isTrue);
      expect(s.logs, hasLength(1));
      // Voltou para a Academia, que agora mostra "Feito".
      expect(find.byType(FitnessScreen), findsOneWidget);
      expect(find.textContaining('Feito'), findsWidgets);
    });

    testWidgets('repetições digitadas vão para a série marcada', (tester) async {
      final fit = MemoryFitnessRepository();
      await fit.upsertWorkout(_fichaA);
      final s = await fit.startSession(_fichaA, fitnessNow);
      await pumpFitness(tester, WorkoutSessionScreen(sessionId: s.id), fit: fit);

      await tester.enterText(find.byKey(const Key('set-reps-0-2')), '9');
      await tapKey(tester, 'set-check-0-2', settle: false);
      final log = (await _sessions(fit)).single.logs.single;
      expect(log.setIndex, 2);
      expect(log.reps, 9);
      expect(find.byKey(const Key('rest-timer')), findsNothing);
      expect(find.byKey(const Key('rest-skip')), findsNothing);
    });

    testWidgets('exercício apagado da ficha durante o treino: a sessão continua', (tester) async {
      final fit = MemoryFitnessRepository();
      await fit.upsertWorkout(_fichaA);
      final s = await fit.startSession(_fichaA, fitnessNow);
      await pumpFitness(tester, WorkoutSessionScreen(sessionId: s.id), fit: fit);

      await tapKey(tester, 'set-check-0-1', settle: false);

      // A ficha é editada em outro lugar: Supino sai.
      await fit.upsertWorkout(_fichaA.copyWith(exercises: [_fichaA.exercises[1]]));
      await tester.pumpAndSettle();

      expect(find.text('Supino'), findsOneWidget);
      expect(find.text('Remada'), findsOneWidget);
      // Remada virou a linha 0; a série já feita de Supino aparece marcada, como linha órfã.
      expect(tester.widget<Checkbox>(find.byKey(const Key('set-check-1-1'))).value, isTrue);
      await tapKey(tester, 'set-check-0-1', settle: false);
      await tapKey(tester, 'session-finish');

      final got = (await _sessions(fit)).single;
      expect(got.isFinished, isTrue);
      expect(got.logs.map((l) => l.exerciseName).toSet(), {'Supino', 'Remada'});
    });

    testWidgets('ficha e sessões aparecem na tela; apagar a ficha mantém o histórico', (tester) async {
      final fit = MemoryFitnessRepository();
      await fit.upsertWorkout(_fichaA);
      final s = await fit.startSession(_fichaA, DateTime(2026, 9, 25, 9));
      await fit.logSet(SetLog(id: 'l', sessionId: s.id, exerciseId: 'a1', exerciseName: 'Supino', setIndex: 1, reps: 8, doneAt: DateTime(2026, 9, 25, 9, 5)));
      await fit.finishSession(s.id, DateTime(2026, 9, 25, 10));

      await pumpFitness(tester, const FitnessScreen(), fit: fit);
      expect(find.byKey(const Key('workout-tile-a')), findsOneWidget);
      expect(find.byKey(Key('session-tile-${s.id}')), findsOneWidget);

      await tapKey(tester, 'workout-menu-a');
      await tester.tap(find.text('Apagar'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Apagar'));
      await tester.pumpAndSettle();

      expect(await fit.watchWorkouts().first, isEmpty);
      expect(find.byKey(Key('session-tile-${s.id}')), findsOneWidget);
    });

    testWidgets('duplicar ficha cria cópia com novos ids', (tester) async {
      final fit = MemoryFitnessRepository();
      await fit.upsertWorkout(_fichaA);
      await pumpFitness(tester, const FitnessScreen(), fit: fit);
      await tapKey(tester, 'workout-menu-a');
      await tester.tap(find.text('Duplicar'));
      await tester.pumpAndSettle();
      final ws = await fit.watchWorkouts().first;
      expect(ws, hasLength(2));
      expect(ws[1].name, 'Treino A (cópia)');
      expect(ws[1].exercises.map((e) => e.name), ['Supino', 'Remada']);
      expect(ws[1].exercises.first.id, isNot('a1'));
      expect(ws[1].exercises.first.workoutId, ws[1].id);
    });

    testWidgets('descer a ficha troca a ordem', (tester) async {
      final fit = MemoryFitnessRepository();
      await fit.upsertWorkout(_fichaA);
      await fit.upsertWorkout(const Workout(id: 'b', name: 'Treino B', position: 1));
      await pumpFitness(tester, const FitnessScreen(), fit: fit);
      await tapKey(tester, 'workout-menu-a');
      await tester.tap(find.text('Descer'));
      await tester.pumpAndSettle();
      expect((await fit.watchWorkouts().first).map((w) => w.id), ['b', 'a']);
    });

    testWidgets('editor: nome obrigatório e exercício em branco é descartado', (tester) async {
      final fit = MemoryFitnessRepository();
      await pumpFitness(tester, const WorkoutEditorScreen(), fit: fit);
      await tapKey(tester, 'workout-save');
      expect(find.text('Dê um nome à ficha'), findsOneWidget);
      expect(await fit.watchWorkouts().first, isEmpty);

      await tester.enterText(find.byKey(const Key('workout-name')), 'Treino Z');
      await tapKey(tester, 'exercise-add');
      await tapKey(tester, 'workout-save');
      final ws = await fit.watchWorkouts().first;
      expect(ws.single.name, 'Treino Z');
      expect(ws.single.exercises, isEmpty);
    });

    testWidgets('editor: edita ficha existente sem trocar os ids dos exercícios', (tester) async {
      final fit = MemoryFitnessRepository();
      await fit.upsertWorkout(_fichaA);
      await pumpFitness(tester, WorkoutEditorScreen(workout: _fichaA), fit: fit);
      // O editor não tem mais carga nem descanso.
      expect(find.byKey(const Key('exercise-load-0')), findsNothing);
      expect(find.byKey(const Key('exercise-rest-0')), findsNothing);
      expect(find.text('Carga (kg)'), findsNothing);
      expect(find.text('Descanso (s)'), findsNothing);
      await tester.enterText(find.byKey(const Key('exercise-reps-0')), '8–12');
      await tapKey(tester, 'workout-save');
      final w = (await fit.watchWorkouts().first).single;
      expect(w.exercises.first.id, 'a1');
      expect(w.exercises.first.reps, '8–12');
    });

    testWidgets('falha ao salvar mostra aviso e mantém a tela', (tester) async {
      final fit = MemoryFitnessRepository()..failWrites = true;
      await pumpFitness(tester, const WorkoutEditorScreen(), fit: fit);
      await tester.enterText(find.byKey(const Key('workout-name')), 'Treino Z');
      await tapKey(tester, 'workout-save');
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.byType(WorkoutEditorScreen), findsOneWidget);
    });

    testWidgets('histórico do exercício mostra data e repetições de cada série', (tester) async {
      final fit = MemoryFitnessRepository();
      await fit.upsertWorkout(_fichaA);
      for (final (day, reps) in [(20, [10, 8]), (24, [12])]) {
        final s = await fit.startSession(_fichaA, DateTime(2026, 9, day, 9));
        for (var i = 0; i < reps.length; i++) {
          await fit.logSet(SetLog(id: 'l$day-$i', sessionId: s.id, exerciseId: 'a1', exerciseName: 'Supino', setIndex: i + 1, reps: reps[i], doneAt: DateTime(2026, 9, day, 9, 5 + i)));
        }
        await fit.finishSession(s.id, DateTime(2026, 9, day, 10));
      }
      final cur = await fit.startSession(_fichaA, fitnessNow);
      await pumpFitness(tester, WorkoutSessionScreen(sessionId: cur.id), fit: fit);
      await tapKey(tester, 'exercise-history-0');
      final sheet = find.byKey(const Key('exercise-history-sheet'));
      expect(sheet, findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.textContaining('12 reps')), findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.textContaining('10, 8 reps')), findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.textContaining('2 séries')), findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.textContaining('kg')), findsNothing);
      expect(find.descendant(of: sheet, matching: find.textContaining('carga')), findsNothing);
    });
  });

  group('Cartão da Início', () {
    Future<void> pumpCard(WidgetTester tester, MemoryFitnessRepository fit, {MemoryRepository? repo, Size size = const Size(400, 800), double scale = 1}) =>
        pumpFitness(tester, Scaffold(body: Center(child: WorkoutTodayCard(onOpen: () {}))),
            fit: fit, repo: repo, size: size, textScale: scale);

    testWidgets('sem fichas: convida a criar a primeira', (tester) async {
      await pumpCard(tester, MemoryFitnessRepository());
      expect(find.byKey(const Key('gym-card')), findsOneWidget);
      expect(find.text('Criar primeira ficha'), findsOneWidget);
      await tapKey(tester, 'gym-create');
      expect(find.byType(WorkoutEditorScreen), findsOneWidget);
    });

    testWidgets('dia de academia: mostra a ficha e Começar abre a sessão', (tester) async {
      final repo = MemoryRepository();
      await repo.upsertEvent(CalendarEvent(id: 'e', title: 'Academia', startsAt: DateTime(2026, 9, 28, 18), endsAt: DateTime(2026, 9, 28, 19)));
      final fit = MemoryFitnessRepository();
      await fit.upsertWorkout(_fichaA);
      await pumpCard(tester, fit, repo: repo);
      expect(find.textContaining('Treino A'), findsOneWidget);
      expect(find.textContaining('2 exercícios'), findsOneWidget);
      await tapKey(tester, 'gym-start');
      expect(find.byType(WorkoutSessionScreen), findsOneWidget);
      expect((await _sessions(fit)).single.workoutId, 'a');
    });

    testWidgets('sem evento: Descanso com "Treinar mesmo assim"', (tester) async {
      final fit = MemoryFitnessRepository();
      await fit.upsertWorkout(_fichaA);
      await pumpCard(tester, fit);
      expect(find.textContaining('Descanso'), findsOneWidget);
      expect(find.text('Treinar mesmo assim'), findsOneWidget);
    });

    testWidgets('em andamento: progresso e Continuar', (tester) async {
      final fit = MemoryFitnessRepository();
      await fit.upsertWorkout(_fichaA);
      final s = await fit.startSession(_fichaA, DateTime(2026, 9, 28, 9));
      await fit.logSet(SetLog(id: 'l', sessionId: s.id, exerciseId: 'a1', exerciseName: 'Supino', setIndex: 1, doneAt: DateTime(2026, 9, 28, 9, 5)));
      await pumpCard(tester, fit);
      expect(find.text('1/6 séries'), findsOneWidget);
      expect(find.text('Continuar'), findsOneWidget);
      await tapKey(tester, 'gym-start');
      expect(find.byType(WorkoutSessionScreen), findsOneWidget);
      expect((await _sessions(fit)), hasLength(1)); // não abriu outra sessão
    });

    testWidgets('treino de ontem esquecido aberto não aparece como em andamento', (tester) async {
      final fit = MemoryFitnessRepository();
      await fit.upsertWorkout(_fichaA);
      await fit.startSession(_fichaA, DateTime(2026, 9, 27, 21));
      await pumpCard(tester, fit);
      expect(find.text('Continuar'), findsNothing);
      expect(find.textContaining('Descanso'), findsOneWidget);
    });

    testWidgets('treino finalizado hoje: Feito', (tester) async {
      final fit = MemoryFitnessRepository();
      await fit.upsertWorkout(_fichaA);
      final s = await fit.startSession(_fichaA, DateTime(2026, 9, 28, 8));
      await fit.finishSession(s.id, DateTime(2026, 9, 28, 9));
      await pumpCard(tester, fit);
      expect(find.textContaining('Feito'), findsOneWidget);
      expect(find.byKey(const Key('gym-start')), findsNothing);
    });
  });

  group('Sem estouro de layout (360 dp, texto grande)', () {
    const phone = Size(360, 640);

    Future<MemoryFitnessRepository> seeded() async {
      final fit = MemoryFitnessRepository();
      await fit.upsertWorkout(Workout(id: 'a', name: 'Treino A com um nome bem comprido para testar', position: 0, exercises: [
        _ex('a1', 'a', 'Supino reto com barra e pegada aberta', reps: '8–12'),
        _ex('a2', 'a', 'Remada curvada', pos: 1),
      ]));
      final s = await fit.startSession(_fichaA, DateTime(2026, 9, 25, 9));
      await fit.logSet(SetLog(id: 'l', sessionId: s.id, exerciseId: 'a1', exerciseName: 'Supino', setIndex: 1, reps: 8, doneAt: DateTime(2026, 9, 25, 9, 5)));
      await fit.finishSession(s.id, DateTime(2026, 9, 25, 10));
      return fit;
    }

    for (final scale in [1.0, 1.8]) {
      testWidgets('FitnessScreen x$scale', (tester) async {
        await pumpFitness(tester, const FitnessScreen(), fit: await seeded(), size: phone, textScale: scale);
        expect(tester.takeException(), isNull);
      });

      testWidgets('FitnessScreen vazia x$scale', (tester) async {
        await pumpFitness(tester, const FitnessScreen(), fit: MemoryFitnessRepository(), size: phone, textScale: scale);
        expect(tester.takeException(), isNull);
      });

      testWidgets('editor x$scale', (tester) async {
        final fit = await seeded();
        final w = (await fit.watchWorkouts().first).single;
        await pumpFitness(tester, WorkoutEditorScreen(workout: w), fit: fit, size: phone, textScale: scale);
        expect(tester.takeException(), isNull);
      });

      testWidgets('sessão x$scale', (tester) async {
        final fit = await seeded();
        final w = (await fit.watchWorkouts().first).single;
        final s = await fit.startSession(w, fitnessNow);
        await pumpFitness(tester, WorkoutSessionScreen(sessionId: s.id), fit: fit, size: phone, textScale: scale);
        await tapKey(tester, 'set-check-0-1', settle: false);
        expect(tester.takeException(), isNull);
      });

      testWidgets('cartão em andamento x$scale', (tester) async {
        final fit = await seeded();
        final w = (await fit.watchWorkouts().first).single;
        await fit.startSession(w, fitnessNow);
        await pumpFitness(tester, Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: WorkoutTodayCard(onOpen: () {}))),
            fit: fit, size: phone, textScale: scale);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
