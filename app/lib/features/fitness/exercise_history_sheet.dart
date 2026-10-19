import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/workout.dart';
import '../../ui/common.dart';

/// Histórico de um exercício: por sessão, as repetições de cada série. [exerciseId] pode ser
/// nulo para um exercício que já saiu da ficha; aí vale o nome.
Future<void> showExerciseHistorySheet(
  BuildContext context, {
  String? exerciseId,
  required String exerciseName,
  required List<WorkoutSession> sessions,
}) {
  final points = exerciseProgress(exerciseId ?? '', exerciseName, sessions);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => ExerciseHistorySheet(exerciseName: exerciseName, points: points),
  );
}

class ExerciseHistorySheet extends StatelessWidget {
  const ExerciseHistorySheet({super.key, required this.exerciseName, required this.points});

  final String exerciseName;
  final List<ExerciseProgressPoint> points;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      key: const Key('exercise-history-sheet'),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(exerciseName, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Histórico', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            if (points.isEmpty) const EmptyHint('Ainda sem registros deste exercício.'),
            for (final p in points)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 72,
                      child: Text(DateFormat('d MMM', 'pt_BR').format(p.day).replaceAll('.', ''),
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ),
                    Expanded(child: Text(_line(p), style: theme.textTheme.bodyLarge)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _line(ExerciseProgressPoint p) {
    final series = plural(p.sets, 'série', 'séries');
    return p.reps.isEmpty ? series : '${p.reps.join(', ')} reps · $series';
  }
}
