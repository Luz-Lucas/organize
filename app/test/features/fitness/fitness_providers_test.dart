import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/app/providers.dart';
import 'package:organizacional/data/fitness_repository.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/calendar_event.dart';
import 'package:organizacional/domain/workout.dart';
import 'package:organizacional/features/fitness/fitness_providers.dart';

void main() {
  final now = DateTime(2026, 9, 28, 10);

  ProviderContainer container(MemoryRepository repo, MemoryFitnessRepository fit, DateTime Function() clock) {
    final c = ProviderContainer(overrides: [
      repositoryProvider.overrideWithValue(repo),
      fitnessRepositoryProvider.overrideWithValue(fit),
      clockProvider.overrideWithValue(clock),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  Future<GymToday> today(ProviderContainer c) async {
    final sub = c.listen(gymTodayProvider, (_, _) {});
    addTearDown(sub.close);
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
      final v = c.read(gymTodayProvider);
      if (v.hasValue) return v.value!;
    }
    fail('gymTodayProvider não resolveu');
  }

  test('sem fichas: GymNoWorkouts', () async {
    final c = container(MemoryRepository(), MemoryFitnessRepository(), () => now);
    expect(await today(c), isA<GymNoWorkouts>());
  });

  test('evento de academia hoje na agenda vira treino planejado', () async {
    final repo = MemoryRepository();
    await repo.upsertEvent(CalendarEvent(
        id: 'e', title: 'Academia', startsAt: DateTime(2026, 9, 28, 18), endsAt: DateTime(2026, 9, 28, 19)));
    final fit = MemoryFitnessRepository();
    await fit.upsertWorkout(const Workout(id: 'a', name: 'Treino A'));
    final r = await today(container(repo, fit, () => now));
    expect(r, isA<GymPlanned>());
  });

  test('sessão aberta ontem não é "em andamento" hoje', () async {
    final fit = MemoryFitnessRepository();
    const w = Workout(id: 'a', name: 'Treino A');
    await fit.upsertWorkout(w);
    await fit.startSession(w, DateTime(2026, 9, 27, 21));
    final r = await today(container(MemoryRepository(), fit, () => now));
    expect(r, isA<GymRest>());
  });

  test('recentSessionsProvider cobre os últimos 120 dias', () async {
    final fit = MemoryFitnessRepository();
    const w = Workout(id: 'a', name: 'Treino A');
    await fit.startSession(w, now.subtract(const Duration(days: 119)));
    await fit.startSession(w, now.subtract(const Duration(days: 125)));
    final c = container(MemoryRepository(), fit, () => now);
    final sub = c.listen(recentSessionsProvider, (_, _) {});
    addTearDown(sub.close);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(recentSessionsProvider).value, hasLength(1));
  });
}
