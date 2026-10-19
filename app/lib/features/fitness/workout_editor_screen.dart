import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repository.dart';
import '../../domain/ids.dart';
import '../../domain/workout.dart';
import '../../ui/common.dart';
import '../../ui/org_widgets.dart';
import 'fitness_providers.dart';

/// Abre o editor em tela cheia; sem [workout] cria uma ficha nova.
Future<void> openWorkoutEditor(BuildContext context, {Workout? workout}) =>
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(builder: (_) => WorkoutEditorScreen(workout: workout)),
    );

class _Draft {
  _Draft(WorkoutExercise? e)
      : id = e?.id ?? newId(),
        name = TextEditingController(text: e?.name ?? ''),
        sets = TextEditingController(text: '${e?.sets ?? 3}'),
        reps = TextEditingController(text: e?.reps ?? '10'),
        load = TextEditingController(text: formatKg(e?.loadKg)),
        rest = TextEditingController(text: '${e?.restSeconds ?? 90}'),
        notes = TextEditingController(text: e?.notes ?? '');

  final String id;
  final TextEditingController name, sets, reps, load, rest, notes;

  void dispose() {
    for (final c in [name, sets, reps, load, rest, notes]) {
      c.dispose();
    }
  }
}

/// Cria ou edita uma ficha: nome e exercícios (nome, séries, repetições, carga, descanso, observação).
class WorkoutEditorScreen extends ConsumerStatefulWidget {
  const WorkoutEditorScreen({super.key, this.workout});

  final Workout? workout;

  @override
  ConsumerState<WorkoutEditorScreen> createState() => _WorkoutEditorScreenState();
}

class _WorkoutEditorScreenState extends ConsumerState<WorkoutEditorScreen> {
  late final TextEditingController _name = TextEditingController(text: widget.workout?.name ?? '');
  late final List<_Draft> _drafts = [for (final e in widget.workout?.exercises ?? const <WorkoutExercise>[]) _Draft(e)];
  bool _nameMissing = false;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    for (final d in _drafts) {
      d.dispose();
    }
    super.dispose();
  }

  void _move(int i, int delta) {
    final j = i + delta;
    if (j < 0 || j >= _drafts.length) return;
    setState(() => _drafts.insert(j, _drafts.removeAt(i)));
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameMissing = true);
      return;
    }
    final id = widget.workout?.id ?? newId();
    final position = widget.workout?.position ?? (ref.read(workoutsProvider).value?.length ?? 0);
    final exercises = <WorkoutExercise>[];
    for (final d in _drafts) {
      final n = d.name.text.trim();
      if (n.isEmpty) continue; // linha em branco: descartada
      final reps = d.reps.text.trim();
      exercises.add(WorkoutExercise(
        id: d.id,
        workoutId: id,
        name: n.length > 80 ? n.substring(0, 80) : n,
        sets: (int.tryParse(d.sets.text.trim()) ?? 3).clamp(1, 20),
        reps: reps.isEmpty ? '10' : (reps.length > 20 ? reps.substring(0, 20) : reps),
        loadKg: parseKg(d.load.text)?.clamp(0, 9999.99),
        restSeconds: (int.tryParse(d.rest.text.trim()) ?? 90).clamp(0, 900),
        notes: d.notes.text.trim(),
        position: exercises.length,
      ));
    }
    setState(() => _saving = true);
    try {
      await ref.read(fitnessRepositoryProvider).upsertWorkout(Workout(
            id: id,
            name: name.length > 60 ? name.substring(0, 60) : name,
            position: position,
            exercises: exercises,
          ));
      if (mounted) Navigator.of(context).pop();
    } on RepositoryException {
      if (mounted) {
        setState(() => _saving = false);
        showError(context, 'Não foi possível salvar a ficha. O que você digitou continua aqui.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 720;
    final gutter = mobile ? 16.0 : 24.0;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.workout == null ? 'Nova ficha' : 'Editar ficha'),
        actions: [
          TextButton(
            key: const Key('workout-save'),
            onPressed: _saving ? null : _save,
            child: const Text('Salvar'),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(gutter, 12, gutter, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    key: const Key('workout-name'),
                    controller: _name,
                    maxLength: 60,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: 'Nome da ficha',
                      hintText: 'Treino A',
                      errorText: _nameMissing && _name.text.trim().isEmpty ? 'Dê um nome à ficha' : null,
                    ),
                    onChanged: (_) {
                      if (_nameMissing) setState(() => _nameMissing = false);
                    },
                  ),
                  const SectionHeader('EXERCÍCIOS'),
                  if (_drafts.isEmpty) const EmptyHint('Nenhum exercício ainda.'),
                  for (var i = 0; i < _drafts.length; i++) ...[
                    _ExerciseEditor(
                      key: ObjectKey(_drafts[i]),
                      index: i,
                      draft: _drafts[i],
                      isFirst: i == 0,
                      isLast: i == _drafts.length - 1,
                      onUp: () => _move(i, -1),
                      onDown: () => _move(i, 1),
                      onRemove: () => setState(() => _drafts.removeAt(i).dispose()),
                    ),
                    const SizedBox(height: 12),
                  ],
                  OutlinedButton.icon(
                    key: const Key('exercise-add'),
                    onPressed: () => setState(() => _drafts.add(_Draft(null))),
                    icon: const Icon(Icons.add),
                    label: const Text('Adicionar exercício'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExerciseEditor extends StatelessWidget {
  const _ExerciseEditor({
    super.key,
    required this.index,
    required this.draft,
    required this.isFirst,
    required this.isLast,
    required this.onUp,
    required this.onDown,
    required this.onRemove,
  });

  final int index;
  final _Draft draft;
  final bool isFirst, isLast;
  final VoidCallback onUp, onDown, onRemove;

  Widget _small(String key, TextEditingController c, String label, {bool decimal = false, double width = 84}) => SizedBox(
        width: width,
        child: TextField(
          key: Key(key),
          controller: c,
          keyboardType: decimal ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.number,
          decoration: InputDecoration(labelText: label, isDense: true),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final i = index;
    return OrgCard(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Exercício ${i + 1}', style: Theme.of(context).textTheme.labelLarge)),
              IconButton(
                tooltip: 'Subir',
                icon: const Icon(Icons.arrow_upward, size: 20),
                onPressed: isFirst ? null : onUp,
              ),
              IconButton(
                tooltip: 'Descer',
                icon: const Icon(Icons.arrow_downward, size: 20),
                onPressed: isLast ? null : onDown,
              ),
              IconButton(
                key: Key('exercise-remove-$i'),
                tooltip: 'Remover exercício',
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: onRemove,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextField(
              key: Key('exercise-name-$i'),
              controller: draft.name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nome', hintText: 'Supino reto'),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _small('exercise-sets-$i', draft.sets, 'Séries'),
                _small('exercise-reps-$i', draft.reps, 'Repetições', width: 110),
                _small('exercise-load-$i', draft.load, 'Carga (kg)', decimal: true, width: 110),
                _small('exercise-rest-$i', draft.rest, 'Descanso (s)', width: 110),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextField(
              key: Key('exercise-notes-$i'),
              controller: draft.notes,
              decoration: const InputDecoration(labelText: 'Observação', isDense: true),
            ),
          ),
        ],
      ),
    );
  }
}
