import 'json.dart';
import 'recurrence.dart';

enum TaskStatus { todo, doing, done }

enum TaskPriority {
  baixa('Baixa'),
  media('Média'),
  alta('Alta');

  const TaskPriority(this.label);
  final String label;

  /// Valor ausente ou desconhecido vira [media].
  static TaskPriority parse(Object? value) {
    for (final p in values) {
      if (p.name == value) return p;
    }
    return media;
  }
}

class TaskItem {
  const TaskItem({
    required this.id,
    required this.title,
    this.description = '',
    this.status = TaskStatus.todo,
    this.priority = TaskPriority.media,
    this.dueAt,
    this.completedAt,
    this.spaceId,
    this.noteId,
    this.source = 'manual',
    this.externalId,
    this.seriesId,
    this.recurrence,
  });

  final String id;
  final String title;
  final String description;
  final TaskStatus status;
  final TaskPriority priority;
  final DateTime? dueAt;
  final DateTime? completedAt;
  final String? spaceId;
  final String? noteId;
  final String source;
  final String? externalId;

  /// Ocorrências da mesma série compartilham o `seriesId`.
  final String? seriesId;

  /// Regra que gerou a série (informativa).
  final Recurrence? recurrence;

  bool get isDone => status == TaskStatus.done;

  TaskItem copyWith({
    String? id,
    String? title,
    String? description,
    TaskStatus? status,
    TaskPriority? priority,
    DateTime? dueAt,
    DateTime? completedAt,
    String? spaceId,
    String? seriesId,
    Recurrence? recurrence,
    bool clearDue = false,
    bool clearCompleted = false,
    bool clearSpace = false,
    bool clearSeries = false,
  }) =>
      TaskItem(
        id: id ?? this.id,
        title: title ?? this.title,
        description: description ?? this.description,
        status: status ?? this.status,
        priority: priority ?? this.priority,
        dueAt: clearDue ? null : (dueAt ?? this.dueAt),
        completedAt: clearCompleted ? null : (completedAt ?? this.completedAt),
        spaceId: clearSpace ? null : (spaceId ?? this.spaceId),
        noteId: noteId,
        source: source,
        externalId: externalId,
        seriesId: clearSeries ? null : (seriesId ?? this.seriesId),
        recurrence: clearSeries ? null : (recurrence ?? this.recurrence),
      );

  TaskItem toggled(DateTime now) => isDone
      ? copyWith(status: TaskStatus.todo, clearCompleted: true)
      : copyWith(status: TaskStatus.done, completedAt: now);

  /// Move para outra coluna: define `completedAt` ao entrar em "feito" e limpa ao sair.
  TaskItem moved(TaskStatus to, DateTime now) => to == TaskStatus.done
      ? copyWith(status: to, completedAt: isDone ? completedAt : now)
      : copyWith(status: to, clearCompleted: true);

  factory TaskItem.fromMap(Map<String, dynamic> m) => TaskItem(
        id: m['id'] as String,
        title: m['title'] as String,
        description: (m['description'] as String?) ?? '',
        status: TaskStatus.values.byName(m['status'] as String),
        priority: TaskPriority.parse(m['priority']),
        dueAt: parseDate(m['due_at']),
        completedAt: parseDate(m['completed_at']),
        spaceId: m['space_id'] as String?,
        noteId: m['note_id'] as String?,
        source: (m['source'] as String?) ?? 'manual',
        externalId: m['external_id'] as String?,
        seriesId: m['series_id'] as String?,
        recurrence: m['recurrence'] is Map
            ? Recurrence.fromMap(Map<String, dynamic>.from(m['recurrence'] as Map))
            : null,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'description': description,
        'status': status.name,
        'priority': priority.name,
        'due_at': encodeDate(dueAt),
        'completed_at': encodeDate(completedAt),
        'space_id': spaceId,
        'note_id': noteId,
        'source': source,
        'external_id': externalId,
        'series_id': seriesId,
        'recurrence': recurrence?.toMap(),
      };

  @override
  bool operator ==(Object other) =>
      other is TaskItem &&
      other.id == id &&
      other.title == title &&
      other.description == description &&
      other.status == status &&
      other.priority == priority &&
      other.dueAt == dueAt &&
      other.completedAt == completedAt &&
      other.spaceId == spaceId &&
      other.noteId == noteId &&
      other.source == source &&
      other.externalId == externalId &&
      other.seriesId == seriesId &&
      other.recurrence == recurrence;

  @override
  int get hashCode => Object.hash(id, title, description, status, priority, dueAt,
      completedAt, spaceId, noteId, source, externalId, seriesId, recurrence);
}
