import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../data/repository.dart';
import '../../domain/ids.dart';
import '../../domain/workout.dart';
import '../../ui/common.dart';
import '../../ui/org_widgets.dart';
import 'exercise_history_sheet.dart';
import 'fitness_providers.dart';

/// Abre a sessão em tela cheia (por cima da casca do app).
Future<void> openSession(BuildContext context, String sessionId) =>
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(builder: (_) => WorkoutSessionScreen(sessionId: sessionId)),
    );

/// Abre uma sessão da ficha [w] (no dia de agora) e vai para a tela do treino.
Future<void> beginWorkout(BuildContext context, WidgetRef ref, Workout w) async {
  try {
    final s = await ref.read(fitnessRepositoryProvider).startSession(w, ref.read(clockProvider)());
    if (context.mounted) await openSession(context, s.id);
  } on RepositoryException {
    if (context.mounted) showError(context, 'Não foi possível começar o treino.');
  }
}

String _clip(String s, int max) => s.length <= max ? s : s.substring(0, max);

/// Um exercício na tela do treino: da ficha ([ex] != null) ou só com séries já feitas (saiu da ficha).
class _ExerciseRow {
  _ExerciseRow({this.ex, required this.name, required this.logs, required this.indices});

  final WorkoutExercise? ex;
  final String name;
  final List<SetLog> logs;
  final List<int> indices;

  SetLog? logAt(int setIndex) {
    for (final l in logs) {
      if (l.setIndex == setIndex) return l;
    }
    return null;
  }
}

List<_ExerciseRow> _buildRows(WorkoutSession s, Workout? w) {
  final rows = <_ExerciseRow>[];
  final known = <String>{};
  for (final ex in w?.exercises ?? const <WorkoutExercise>[]) {
    known.add(ex.id);
    final logs = s.logs.where((l) => l.exerciseId == ex.id).toList();
    final top = logs.fold(ex.sets, (m, l) => l.setIndex > m ? l.setIndex : m);
    rows.add(_ExerciseRow(ex: ex, name: ex.name, logs: logs, indices: [for (var i = 1; i <= top; i++) i]));
  }
  // Séries de exercícios apagados da ficha no meio do treino (ou de ficha apagada): continuam valendo.
  final orphans = s.logs.where((l) => l.exerciseId == null || !known.contains(l.exerciseId)).toList();
  final byName = <String, List<SetLog>>{};
  for (final l in orphans) {
    byName.putIfAbsent(l.exerciseName, () => []).add(l);
  }
  for (final e in byName.entries) {
    final idx = (e.value.map((l) => l.setIndex).toSet().toList())..sort();
    rows.add(_ExerciseRow(name: e.key, logs: e.value, indices: idx));
  }
  return rows;
}

class WorkoutSessionScreen extends ConsumerStatefulWidget {
  const WorkoutSessionScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<WorkoutSessionScreen> createState() => _WorkoutSessionScreenState();
}

class _WorkoutSessionScreenState extends ConsumerState<WorkoutSessionScreen> {
  Future<void> _toggle(WorkoutSession s, _ExerciseRow row, int setIndex, SetLog? log, int? reps) async {
    final repo = ref.read(fitnessRepositoryProvider);
    try {
      if (log != null) {
        await repo.deleteSetLog(log.id);
        return;
      }
      await repo.logSet(SetLog(
        id: newId(),
        sessionId: s.id,
        exerciseId: row.ex?.id,
        exerciseName: _clip(row.name, 80),
        setIndex: setIndex,
        reps: reps?.clamp(0, 999),
        doneAt: ref.read(clockProvider)(),
      ));
    } on RepositoryException {
      if (mounted) showError(context, 'Não foi possível salvar a série.');
    }
  }

  Future<void> _finish(WorkoutSession s) async {
    try {
      await ref.read(fitnessRepositoryProvider).finishSession(s.id, ref.read(clockProvider)());
      if (mounted) Navigator.of(context).maybePop();
    } on RepositoryException {
      if (mounted) showError(context, 'Não foi possível finalizar o treino.');
    }
  }

  Future<void> _delete(WorkoutSession s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apagar este treino?'),
        content: const Text('As séries registradas nele também serão apagadas.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Apagar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(fitnessRepositoryProvider).deleteSession(s.id);
      if (mounted) Navigator.of(context).maybePop();
    } on RepositoryException {
      if (mounted) showError(context, 'Não foi possível apagar o treino.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionsAsync = ref.watch(recentSessionsProvider);
    final workouts = ref.watch(workoutsProvider).value ?? const <Workout>[];
    final sessions = sessionsAsync.value ?? const <WorkoutSession>[];
    WorkoutSession? session;
    for (final s in sessions) {
      if (s.id == widget.sessionId) session = s;
    }
    Workout? workout;
    for (final w in workouts) {
      if (w.id == session?.workoutId) workout = w;
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(session?.workoutName ?? 'Treino'),
        actions: [
          if (session != null && !session.isFinished)
            TextButton(
              key: const Key('session-finish'),
              onPressed: () => _finish(session!),
              child: const Text('Finalizar'),
            ),
          if (session != null)
            PopupMenuButton<String>(
              key: const Key('session-menu'),
              onSelected: (_) => _delete(session!),
              itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Apagar treino'))],
            ),
        ],
      ),
      body: session == null
          ? asyncView(sessionsAsync, (_) => const Center(child: Text('Treino não encontrado.')))
          : _body(context, session, workout, sessions),
    );
  }

  Widget _body(BuildContext context, WorkoutSession s, Workout? w, List<WorkoutSession> sessions) {
    final theme = Theme.of(context);
    final rows = _buildRows(s, w);
    final history = sessions.where((x) => x.id != s.id).toList();
    final planned = w?.totalSets ?? 0;
    final done = s.logs.length;
    final total = done > planned ? done : planned;
    final mobile = MediaQuery.sizeOf(context).width < 720;
    final gutter = mobile ? 16.0 : 24.0;
    return ListView(
      padding: EdgeInsets.fromLTRB(gutter, 12, gutter, 24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('$done/$total séries', style: theme.textTheme.titleMedium),
                    Text('iniciado às ${DateFormat('HH:mm').format(s.startedAt)}',
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    if (s.isFinished) const OrgBadge('Finalizado'),
                  ],
                ),
                if (w == null && s.workoutId == null)
                  const Padding(padding: EdgeInsets.only(top: 4), child: EmptyHint('A ficha deste treino foi apagada.')),
                const SizedBox(height: 12),
                if (rows.isEmpty) const EmptyHint('Esta ficha não tem exercícios.'),
                for (var i = 0; i < rows.length; i++) ...[
                  _ExerciseCard(
                    key: ValueKey('ex-${rows[i].ex?.id ?? rows[i].name}'),
                    index: i,
                    row: rows[i],
                    history: history,
                    onToggle: (j, log, reps) => _toggle(s, rows[i], j, log, reps),
                    onHistory: () => showExerciseHistorySheet(
                      context,
                      exerciseId: rows[i].ex?.id,
                      exerciseName: rows[i].name,
                      sessions: history,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({
    super.key,
    required this.index,
    required this.row,
    required this.history,
    required this.onToggle,
    required this.onHistory,
  });

  final int index;
  final _ExerciseRow row;
  final List<WorkoutSession> history;
  final void Function(int setIndex, SetLog? log, int? reps) onToggle;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ex = row.ex;
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final plan = ex == null
        ? 'Removido da ficha'
        : [
            '${ex.sets} × ${ex.reps}',
          ].join(' · ');
    // Repetições sugeridas: a última vez daquele exercício; senão o planejado.
    final last = ex == null ? null : lastSetFor(ex.id, ex.name, history);
    final suggestReps = last?.reps ?? (ex == null ? null : firstInt(ex.reps));
    return OrgCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.name, style: theme.textTheme.titleMedium),
                    Text(plan, style: muted),
                    if (ex != null && ex.notes.isNotEmpty) Text(ex.notes, style: muted),
                  ],
                ),
              ),
              IconButton(
                key: Key('exercise-history-$index'),
                tooltip: 'Evolução',
                icon: const Icon(Icons.show_chart),
                onPressed: onHistory,
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final j in row.indices)
            _SetRow(
              key: ValueKey('set-${ex?.id ?? row.name}-$j'),
              rowIndex: index,
              setIndex: j,
              log: row.logAt(j),
              suggestReps: suggestReps,
              onToggle: (log, reps) => onToggle(j, log, reps),
            ),
        ],
      ),
    );
  }
}

class _SetRow extends StatefulWidget {
  const _SetRow({
    super.key,
    required this.rowIndex,
    required this.setIndex,
    required this.log,
    required this.suggestReps,
    required this.onToggle,
  });

  final int rowIndex;
  final int setIndex;
  final SetLog? log;
  final int? suggestReps;
  final void Function(SetLog? log, int? reps) onToggle;

  @override
  State<_SetRow> createState() => _SetRowState();
}

class _SetRowState extends State<_SetRow> {
  late final TextEditingController _reps;

  @override
  void initState() {
    super.initState();
    final l = widget.log;
    _reps = TextEditingController(text: '${l != null ? l.reps ?? '' : widget.suggestReps ?? ''}');
  }

  @override
  void didUpdateWidget(_SetRow old) {
    super.didUpdateWidget(old);
    final l = widget.log;
    if (l != null && l.reps != old.log?.reps) _reps.text = '${l.reps ?? ''}';
  }

  @override
  void dispose() {
    _reps.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = widget.log != null;
    final i = widget.rowIndex, j = widget.setIndex;
    return Row(
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 28),
          child: Text('$j', style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            key: Key('set-reps-$i-$j'),
            controller: _reps,
            readOnly: done,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'reps', isDense: true),
          ),
        ),
        Checkbox(
          key: Key('set-check-$i-$j'),
          value: done,
          onChanged: (_) => widget.onToggle(widget.log, int.tryParse(_reps.text.trim())),
        ),
      ],
    );
  }
}
