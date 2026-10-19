import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/workout.dart';
import '../../ui/common.dart';
import '../../ui/org_widgets.dart';
import 'fitness_providers.dart';
import 'workout_editor_screen.dart';
import 'workout_session_screen.dart';

/// Cartão da Início (e da tela Academia): o treino de hoje e o botão para começar/continuar.
/// [onOpen] abre a tela Academia; sem ele o cartão não é clicável (é o caso dentro da própria tela).
/// Some enquanto carrega ou se não conseguir ler (nunca quebra a Início).
class WorkoutTodayCard extends ConsumerWidget {
  const WorkoutTodayCard({super.key, this.onOpen});

  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gymTodayProvider).value;
    if (state == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    Widget start(String label, VoidCallback onPressed, {bool tonal = false}) {
      final child = Text(label);
      return tonal
          ? FilledButton.tonal(key: const Key('gym-start'), onPressed: onPressed, child: child)
          : FilledButton(key: const Key('gym-start'), onPressed: onPressed, child: child);
    }

    final (String headline, String? detail, Widget? action) = switch (state) {
      GymNoWorkouts() => (
          'Nenhuma ficha ainda',
          null,
          FilledButton(
            key: const Key('gym-create'),
            onPressed: () => openWorkoutEditor(context),
            child: const Text('Criar primeira ficha'),
          ),
        ),
      GymRest(:final next) => (
          'Descanso',
          next == null ? null : 'Próximo treino: ${next.name}',
          next == null ? null : start('Treinar mesmo assim', () => beginWorkout(context, ref, next), tonal: true),
        ),
      GymPlanned(:final w) => (
          'Hoje: ${w.name}',
          plural(w.exercises.length, 'exercício', 'exercícios'),
          start('Começar', () => beginWorkout(context, ref, w)),
        ),
      GymInProgress(:final s, :final doneSets, :final totalSets) => (
          '${s.workoutName} em andamento',
          '$doneSets/$totalSets séries',
          start('Continuar', () => openSession(context, s.id)),
        ),
      GymDone(:final s) => (
          'Feito ✓',
          '${s.workoutName} · ${plural(s.logs.length, 'série', 'séries')}',
          null,
        ),
    };

    return OrgCard(
      key: const Key('gym-card'),
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.fitness_center, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text('Academia', style: theme.textTheme.titleSmall)),
              if (onOpen != null) Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
          const SizedBox(height: 8),
          Text(headline, style: theme.textTheme.titleMedium),
          if (detail != null) Text(detail, style: muted),
          if (state case GymInProgress(:final doneSets, :final totalSets))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(value: totalSets == 0 ? 0 : (doneSets / totalSets).clamp(0.0, 1.0)),
            ),
          if (action != null) Padding(padding: const EdgeInsets.only(top: 12), child: action),
        ],
      ),
    );
  }
}
