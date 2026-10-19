import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/repository.dart';
import '../../domain/ids.dart';
import '../../domain/workout.dart';
import '../../ui/common.dart';
import '../../ui/org_widgets.dart';
import 'fitness_providers.dart';
import 'workout_editor_screen.dart';
import 'workout_session_screen.dart';
import 'workout_today_card.dart';

/// Academia (rota `/academia`): treino de hoje, fichas e histórico.
class FitnessScreen extends ConsumerWidget {
  const FitnessScreen({super.key});

  Future<void> _run(BuildContext context, Future<void> Function() op, String error) async {
    try {
      await op();
    } on RepositoryException {
      if (context.mounted) showError(context, error);
    }
  }

  Future<void> _duplicate(BuildContext context, WidgetRef ref, Workout w, int count) {
    final id = newId();
    final name = '${w.name} (cópia)';
    final copy = Workout(
      id: id,
      name: name.length > 60 ? name.substring(0, 60) : name,
      position: count,
      exercises: [
        for (final e in w.exercises) e.copyWith(id: newId(), workoutId: id),
      ],
    );
    return _run(context, () => ref.read(fitnessRepositoryProvider).upsertWorkout(copy),
        'Não foi possível duplicar a ficha.');
  }

  Future<void> _move(BuildContext context, WidgetRef ref, List<Workout> all, int i, int delta) {
    final ordered = [...all];
    ordered.insert(i + delta, ordered.removeAt(i));
    return _run(context, () => ref.read(fitnessRepositoryProvider).reorderWorkouts(ordered),
        'Não foi possível mudar a ordem.');
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Workout w) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Apagar "${w.name}"?'),
        content: const Text('Os treinos já feitos continuam no histórico.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Apagar')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await _run(context, () => ref.read(fitnessRepositoryProvider).deleteWorkout(w.id),
        'Não foi possível apagar a ficha.');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workouts = ref.watch(workoutsProvider);
    final sessions = ref.watch(recentSessionsProvider).value ?? const <WorkoutSession>[];
    final mobile = MediaQuery.sizeOf(context).width < 720;
    final gutter = mobile ? 16.0 : 24.0;
    return Scaffold(
      body: SafeArea(
        child: asyncView(workouts, (list) {
          final next = nextWorkout(list, sessions);
          final shown = sessions.take(20).toList();
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const PageHeader(title: 'Academia', subtitle: 'Fichas, treino de hoje e histórico'),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: gutter),
                        child: const WorkoutTodayCard(),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: gutter - 8),
                        child: const SectionHeader('FICHAS'),
                      ),
                      if (list.isEmpty)
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: gutter - 8),
                          child: const EmptyHint('Nenhuma ficha ainda.'),
                        ),
                      for (var i = 0; i < list.length; i++)
                        Padding(
                          padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 8),
                          child: _WorkoutTile(
                            workout: list[i],
                            isNext: next?.id == list[i].id,
                            onEdit: () => openWorkoutEditor(context, workout: list[i]),
                            onStart: () => beginWorkout(context, ref, list[i]),
                            onDuplicate: () => _duplicate(context, ref, list[i], list.length),
                            onUp: i == 0 ? null : () => _move(context, ref, list, i, -1),
                            onDown: i == list.length - 1 ? null : () => _move(context, ref, list, i, 1),
                            onDelete: () => _delete(context, ref, list[i]),
                          ),
                        ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(gutter, 4, gutter, 0),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            key: const Key('workout-add'),
                            onPressed: () => openWorkoutEditor(context),
                            icon: const Icon(Icons.add),
                            label: const Text('Nova ficha'),
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: gutter - 8),
                        child: const SectionHeader('HISTÓRICO'),
                      ),
                      if (shown.isEmpty)
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: gutter - 8),
                          child: const EmptyHint('Os treinos que você fizer aparecem aqui.'),
                        ),
                      for (final s in shown)
                        Padding(
                          padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 8),
                          child: _SessionTile(session: s, onTap: () => openSession(context, s.id)),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _WorkoutTile extends StatelessWidget {
  const _WorkoutTile({
    required this.workout,
    required this.isNext,
    required this.onEdit,
    required this.onStart,
    required this.onDuplicate,
    required this.onUp,
    required this.onDown,
    required this.onDelete,
  });

  final Workout workout;
  final bool isNext;
  final VoidCallback onEdit, onStart, onDuplicate, onDelete;
  final VoidCallback? onUp, onDown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final w = workout;
    return OrgCard(
      key: Key('workout-tile-${w.id}'),
      onTap: onEdit,
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(w.name, style: theme.textTheme.titleMedium),
                Text(
                  '${plural(w.exercises.length, 'exercício', 'exercícios')} · ${plural(w.totalSets, 'série', 'séries')}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                if (isNext) const Padding(padding: EdgeInsets.only(top: 4), child: OrgBadge('Próximo')),
              ],
            ),
          ),
          IconButton(
            key: Key('workout-play-${w.id}'),
            tooltip: 'Começar',
            icon: const Icon(Icons.play_arrow),
            onPressed: onStart,
          ),
          PopupMenuButton<String>(
            key: Key('workout-menu-${w.id}'),
            onSelected: (v) => switch (v) {
              'dup' => onDuplicate(),
              'up' => onUp?.call(),
              'down' => onDown?.call(),
              _ => onDelete(),
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'dup', child: Text('Duplicar')),
              PopupMenuItem(value: 'up', enabled: onUp != null, child: const Text('Subir')),
              PopupMenuItem(value: 'down', enabled: onDown != null, child: const Text('Descer')),
              const PopupMenuItem(value: 'del', child: Text('Apagar')),
            ],
          ),
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session, required this.onTap});

  final WorkoutSession session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = session;
    final day = DateFormat('EEE, d MMM', 'pt_BR').format(s.day).replaceAll('.', '');
    final minutes = s.finishedAt?.difference(s.startedAt).inMinutes;
    final detail = [
      day,
      plural(s.logs.length, 'série', 'séries'),
      if (minutes != null && minutes > 0) '$minutes min',
    ].join(' · ');
    return OrgCard(
      key: Key('session-tile-${s.id}'),
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.workoutName, style: theme.textTheme.titleSmall),
                Text(detail, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          if (!s.isFinished) const OrgBadge('Não finalizado', tone: OrgBadgeTone.neutral),
        ],
      ),
    );
  }
}
