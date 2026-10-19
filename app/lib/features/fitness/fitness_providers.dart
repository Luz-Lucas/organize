import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/fitness_repository.dart';
import '../../domain/agenda.dart';
import '../../domain/workout.dart';

/// Os testes e o `main.dart` trocam por [MemoryFitnessRepository] / [SupabaseFitnessRepository].
final fitnessRepositoryProvider = Provider<FitnessRepository>(
  (ref) => throw UnimplementedError('fitnessRepositoryProvider precisa de override'),
);

final workoutsProvider =
    StreamProvider<List<Workout>>((ref) => ref.watch(fitnessRepositoryProvider).watchWorkouts());

/// Sessões dos últimos 120 dias (com as séries), da mais recente para a mais antiga.
final recentSessionsProvider = StreamProvider<List<WorkoutSession>>((ref) {
  final now = ref.watch(clockProvider)();
  final from = startOfDay(now).subtract(const Duration(days: 120));
  return ref.watch(fitnessRepositoryProvider).watchSessions(from: DateTime(from.year, from.month, from.day));
});

/// Estado da academia hoje. Espera fichas, sessões, agenda e etiquetas; se a agenda ou as etiquetas
/// falharem, segue sem elas (vira "descanso") em vez de esconder a Academia.
final gymTodayProvider = Provider<AsyncValue<GymToday>>((ref) {
  final now = ref.watch(clockProvider)();
  final workouts = ref.watch(workoutsProvider);
  final sessions = ref.watch(recentSessionsProvider);
  final events = ref.watch(eventsFromProvider(startOfDay(now)));
  final tags = ref.watch(eventTagsProvider);

  if (workouts.hasError && !workouts.hasValue) return AsyncError(workouts.error!, workouts.stackTrace!);
  if (sessions.hasError && !sessions.hasValue) return AsyncError(sessions.error!, sessions.stackTrace!);
  bool waiting(AsyncValue<Object?> v) => !v.hasValue && !v.hasError;
  if (waiting(workouts) || waiting(sessions) || waiting(events) || waiting(tags)) {
    return const AsyncLoading();
  }
  return AsyncData(gymToday(
    now: now,
    events: events.value ?? const [],
    tags: {for (final t in tags.value ?? const []) t.id: t},
    workouts: workouts.value ?? const [],
    sessions: sessions.value ?? const [],
  ));
});
