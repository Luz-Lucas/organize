import 'agenda.dart';
import 'calendar_event.dart';
import 'event_tag.dart';
import 'json.dart';

/// Exercício de uma ficha. `reps` é texto livre ("8–12"); `loadKg` é a carga planejada (opcional).
class WorkoutExercise {
  const WorkoutExercise({
    required this.id,
    required this.workoutId,
    required this.name,
    this.sets = 3,
    this.reps = '10',
    this.loadKg,
    this.restSeconds = 90,
    this.notes = '',
    this.position = 0,
  });

  final String id;
  final String workoutId;
  final String name;
  final int sets;
  final String reps;
  final double? loadKg;
  final int restSeconds;
  final String notes;
  final int position;

  factory WorkoutExercise.fromMap(Map<String, dynamic> m) => WorkoutExercise(
        id: m['id'] as String,
        workoutId: m['workout_id'] as String,
        name: m['name'] as String,
        sets: (m['sets'] as num?)?.toInt() ?? 3,
        reps: (m['reps'] as String?) ?? '10',
        loadKg: _toDouble(m['load_kg']),
        restSeconds: (m['rest_seconds'] as num?)?.toInt() ?? 90,
        notes: (m['notes'] as String?) ?? '',
        position: (m['position'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'workout_id': workoutId,
        'name': name,
        'sets': sets,
        'reps': reps,
        'load_kg': loadKg,
        'rest_seconds': restSeconds,
        'notes': notes,
        'position': position,
      };

  WorkoutExercise copyWith({
    String? id,
    String? workoutId,
    String? name,
    int? sets,
    String? reps,
    double? loadKg,
    int? restSeconds,
    String? notes,
    int? position,
    bool clearLoad = false,
  }) =>
      WorkoutExercise(
        id: id ?? this.id,
        workoutId: workoutId ?? this.workoutId,
        name: name ?? this.name,
        sets: sets ?? this.sets,
        reps: reps ?? this.reps,
        loadKg: clearLoad ? null : (loadKg ?? this.loadKg),
        restSeconds: restSeconds ?? this.restSeconds,
        notes: notes ?? this.notes,
        position: position ?? this.position,
      );

  @override
  bool operator ==(Object other) =>
      other is WorkoutExercise &&
      other.id == id &&
      other.workoutId == workoutId &&
      other.name == name &&
      other.sets == sets &&
      other.reps == reps &&
      other.loadKg == loadKg &&
      other.restSeconds == restSeconds &&
      other.notes == notes &&
      other.position == position;

  @override
  int get hashCode => Object.hash(id, workoutId, name, sets, reps, loadKg, restSeconds, notes, position);
}

/// Ficha de treino (Treino A, B…) com os exercícios em ordem.
class Workout {
  const Workout({required this.id, required this.name, this.position = 0, this.exercises = const []});

  final String id;
  final String name;
  final int position;
  final List<WorkoutExercise> exercises;

  int get totalSets => exercises.fold(0, (n, e) => n + e.sets);

  /// Aceita `exercises` (lista de mapas) quando o repositório já juntou as linhas.
  factory Workout.fromMap(Map<String, dynamic> m) => Workout(
        id: m['id'] as String,
        name: m['name'] as String,
        position: (m['position'] as num?)?.toInt() ?? 0,
        exercises: [
          for (final e in (m['exercises'] as List<dynamic>? ?? const []))
            WorkoutExercise.fromMap((e as Map).cast<String, dynamic>()),
        ],
      );

  /// Só a linha de `workouts`; os exercícios têm tabela própria.
  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'position': position};

  Workout copyWith({String? name, int? position, List<WorkoutExercise>? exercises}) => Workout(
        id: id,
        name: name ?? this.name,
        position: position ?? this.position,
        exercises: exercises ?? this.exercises,
      );
}

/// Série feita (ou registrada) numa sessão. Guarda o nome do exercício: ele sobrevive a edições da ficha.
class SetLog {
  const SetLog({
    required this.id,
    required this.sessionId,
    this.exerciseId,
    required this.exerciseName,
    required this.setIndex,
    this.reps,
    this.loadKg,
    required this.doneAt,
  });

  final String id;
  final String sessionId;
  final String? exerciseId;
  final String exerciseName;

  /// A partir de 1.
  final int setIndex;
  final int? reps;
  final double? loadKg;
  final DateTime doneAt;

  factory SetLog.fromMap(Map<String, dynamic> m) => SetLog(
        id: m['id'] as String,
        sessionId: m['session_id'] as String,
        exerciseId: m['exercise_id'] as String?,
        exerciseName: m['exercise_name'] as String,
        setIndex: (m['set_index'] as num).toInt(),
        reps: (m['reps'] as num?)?.toInt(),
        loadKg: _toDouble(m['load_kg']),
        doneAt: parseDate(m['done_at']) ?? DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'session_id': sessionId,
        'exercise_id': exerciseId,
        'exercise_name': exerciseName,
        'set_index': setIndex,
        'reps': reps,
        'load_kg': loadKg,
        'done_at': encodeDate(doneAt),
      };

  SetLog copyWith({
    String? exerciseId,
    int? reps,
    double? loadKg,
    DateTime? doneAt,
    bool clearExercise = false,
  }) =>
      SetLog(
        id: id,
        sessionId: sessionId,
        exerciseId: clearExercise ? null : (exerciseId ?? this.exerciseId),
        exerciseName: exerciseName,
        setIndex: setIndex,
        reps: reps ?? this.reps,
        loadKg: loadKg ?? this.loadKg,
        doneAt: doneAt ?? this.doneAt,
      );
}

/// Uma ida à academia. `day` é o dia (só data) em que começou, mesmo que termine depois da meia-noite.
class WorkoutSession {
  const WorkoutSession({
    required this.id,
    this.workoutId,
    required this.workoutName,
    required this.day,
    required this.startedAt,
    this.finishedAt,
    this.logs = const [],
  });

  final String id;
  final String? workoutId;
  final String workoutName;
  final DateTime day;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final List<SetLog> logs;

  bool get isFinished => finishedAt != null;

  factory WorkoutSession.fromMap(Map<String, dynamic> m) {
    final day = DateTime.parse(m['day'] as String);
    return WorkoutSession(
      id: m['id'] as String,
      workoutId: m['workout_id'] as String?,
      workoutName: m['workout_name'] as String,
      day: DateTime(day.year, day.month, day.day),
      startedAt: parseDate(m['started_at']) ?? day,
      finishedAt: parseDate(m['finished_at']),
      logs: [
        for (final l in (m['logs'] as List<dynamic>? ?? const []))
          SetLog.fromMap((l as Map).cast<String, dynamic>()),
      ],
    );
  }

  /// Só a linha de `workout_sessions`; as séries têm tabela própria.
  Map<String, dynamic> toMap() => {
        'id': id,
        'workout_id': workoutId,
        'workout_name': workoutName,
        'day': _dayString(day),
        'started_at': encodeDate(startedAt),
        'finished_at': encodeDate(finishedAt),
      };

  WorkoutSession copyWith({DateTime? finishedAt, List<SetLog>? logs}) => WorkoutSession(
        id: id,
        workoutId: workoutId,
        workoutName: workoutName,
        day: day,
        startedAt: startedAt,
        finishedAt: finishedAt ?? this.finishedAt,
        logs: logs ?? this.logs,
      );
}

String _dayString(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

double? _toDouble(Object? v) => switch (v) {
      null => null,
      num n => n.toDouble(),
      String s => double.tryParse(s),
      _ => null,
    };

const _accents = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', 'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ç': 'c', 'ñ': 'n',
};

/// Minúsculo e sem acento (como `fold_event_text` do banco).
String foldText(String s) {
  final lower = s.toLowerCase();
  final b = StringBuffer();
  for (final r in lower.runes) {
    final ch = String.fromCharCode(r);
    b.write(_accents[ch] ?? ch);
  }
  return b.toString();
}

/// Evento de academia: título **ou** nome da etiqueta contém `academia`, `treino` ou `musculac`.
bool isGymEvent(CalendarEvent e, Map<String, EventTag> tags) {
  bool hit(String s) {
    final t = foldText(s);
    return t.contains('academia') || t.contains('treino') || t.contains('musculac');
  }

  final tag = e.tagId == null ? null : tags[e.tagId];
  return hit(e.title) || (tag != null && hit(tag.name));
}

/// Próxima ficha no rodízio: a seguinte à do último treino finalizado (a primeira se nunca treinou
/// ou se a ficha do último treino foi apagada).
Workout? nextWorkout(List<Workout> workouts, List<WorkoutSession> history) {
  if (workouts.isEmpty) return null;
  final ws = [...workouts]..sort((a, b) => a.position.compareTo(b.position));
  final finished = history.where((s) => s.isFinished && s.workoutId != null).toList()
    ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  for (final s in finished) {
    final i = ws.indexWhere((w) => w.id == s.workoutId);
    if (i >= 0) return ws[(i + 1) % ws.length];
  }
  return ws.first;
}

bool _sameName(SetLog l, String name) => foldText(l.exerciseName.trim()) == foldText(name.trim());

/// Série mais recente daquele exercício: procura pelo id; se nunca houve, pelo nome.
SetLog? lastSetFor(String exerciseId, String exerciseName, List<WorkoutSession> history) {
  final all = [for (final s in history) ...s.logs];
  SetLog? latest(Iterable<SetLog> logs) {
    SetLog? best;
    for (final l in logs) {
      if (best == null || l.doneAt.isAfter(best.doneAt)) best = l;
    }
    return best;
  }

  return latest(all.where((l) => l.exerciseId == exerciseId)) ??
      latest(all.where((l) => _sameName(l, exerciseName)));
}

/// Um ponto da evolução de um exercício: o melhor da sessão.
class ExerciseProgressPoint {
  const ExerciseProgressPoint({required this.day, required this.maxLoadKg, required this.reps, required this.sets});

  final DateTime day;

  /// Maior carga do dia (`null` se nenhuma série teve carga).
  final double? maxLoadKg;

  /// Repetições da série de maior carga (ou da de mais repetições, sem carga).
  final int? reps;

  /// Quantas séries foram registradas.
  final int sets;
}

/// Evolução do exercício (por id ou por nome), da sessão mais recente para a mais antiga.
List<ExerciseProgressPoint> exerciseProgress(
    String exerciseId, String exerciseName, List<WorkoutSession> history) {
  final out = <ExerciseProgressPoint>[];
  final sessions = [...history]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  for (final s in sessions) {
    final logs = s.logs.where((l) => l.exerciseId == exerciseId || _sameName(l, exerciseName)).toList();
    if (logs.isEmpty) continue;
    SetLog best = logs.first;
    for (final l in logs.skip(1)) {
      final a = l.loadKg ?? -1, b = best.loadKg ?? -1;
      if (a > b || (a == b && (l.reps ?? 0) > (best.reps ?? 0))) best = l;
    }
    out.add(ExerciseProgressPoint(day: s.day, maxLoadKg: best.loadKg, reps: best.reps, sets: logs.length));
  }
  return out;
}

/// O que a academia mostra hoje (tela e cartão da Início).
sealed class GymToday {
  const GymToday();
}

/// Ainda não há fichas.
class GymNoWorkouts extends GymToday {
  const GymNoWorkouts();
}

/// Sem evento de academia hoje; [next] é a ficha sugerida para "treinar mesmo assim".
class GymRest extends GymToday {
  const GymRest(this.next);
  final Workout? next;
}

/// Há evento de academia hoje e nada foi iniciado.
class GymPlanned extends GymToday {
  const GymPlanned(this.w);
  final Workout w;
}

class GymInProgress extends GymToday {
  const GymInProgress(this.s, this.doneSets, this.totalSets);
  final WorkoutSession s;
  final int doneSets;
  final int totalSets;
}

class GymDone extends GymToday {
  const GymDone(this.s);
  final WorkoutSession s;
}

GymToday gymToday({
  required DateTime now,
  required Iterable<CalendarEvent> events,
  required Map<String, EventTag> tags,
  required List<Workout> workouts,
  required List<WorkoutSession> sessions,
}) {
  if (workouts.isEmpty) return const GymNoWorkouts();
  final today = startOfDay(now);
  final todays = sessions.where((s) => startOfDay(s.day) == today).toList()
    ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  // Sessão aberta de ontem não conta: a sessão pertence ao dia em que começou.
  for (final s in todays) {
    if (s.isFinished) continue;
    Workout? w;
    for (final x in workouts) {
      if (x.id == s.workoutId) w = x;
    }
    final done = s.logs.length;
    final planned = w?.totalSets ?? 0;
    return GymInProgress(s, done, done > planned ? done : planned);
  }
  for (final s in todays) {
    if (s.isFinished) return GymDone(s);
  }
  final next = nextWorkout(workouts, sessions);
  final hasGymEvent = eventsOnDay(events, today).any((e) => isGymEvent(e, tags));
  if (hasGymEvent && next != null) return GymPlanned(next);
  return GymRest(next);
}

/// "42,5", "40": vírgula decimal, sem zeros à direita. Nulo vira texto vazio.
String formatKg(double? kg) {
  if (kg == null) return '';
  final s = kg == kg.roundToDouble() ? kg.round().toString() : kg.toString();
  return s.replaceAll('.', ',');
}

/// Lê uma carga digitada (vírgula ou ponto). Vazio, inválido ou negativo vira nulo.
double? parseKg(String text) {
  final v = double.tryParse(text.trim().replaceAll(',', '.'));
  return v == null || v < 0 || v.isNaN || v.isInfinite ? null : v;
}

/// Primeiro número inteiro de um texto como "8–12" (8); nulo se não houver.
int? firstInt(String text) {
  final m = RegExp(r'\d+').firstMatch(text);
  return m == null ? null : int.parse(m.group(0)!);
}
