import 'json.dart';

enum TaskStatus { todo, doing, done }

class TaskItem {
  const TaskItem({
    required this.id,
    required this.title,
    this.description = '',
    this.status = TaskStatus.todo,
    this.dueAt,
    this.completedAt,
    this.spaceId,
    this.noteId,
    this.source = 'manual',
    this.externalId,
  });

  final String id;
  final String title;
  final String description;
  final TaskStatus status;
  final DateTime? dueAt;
  final DateTime? completedAt;
  final String? spaceId;
  final String? noteId;
  final String source;
  final String? externalId;

  bool get isDone => status == TaskStatus.done;

  TaskItem toggled(DateTime now) => TaskItem(
        id: id,
        title: title,
        description: description,
        status: isDone ? TaskStatus.todo : TaskStatus.done,
        dueAt: dueAt,
        completedAt: isDone ? null : now,
        spaceId: spaceId,
        noteId: noteId,
        source: source,
        externalId: externalId,
      );

  factory TaskItem.fromMap(Map<String, dynamic> m) => TaskItem(
        id: m['id'] as String,
        title: m['title'] as String,
        description: (m['description'] as String?) ?? '',
        status: TaskStatus.values.byName(m['status'] as String),
        dueAt: parseDate(m['due_at']),
        completedAt: parseDate(m['completed_at']),
        spaceId: m['space_id'] as String?,
        noteId: m['note_id'] as String?,
        source: (m['source'] as String?) ?? 'manual',
        externalId: m['external_id'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'description': description,
        'status': status.name,
        'due_at': encodeDate(dueAt),
        'completed_at': encodeDate(completedAt),
        'space_id': spaceId,
        'note_id': noteId,
        'source': source,
        'external_id': externalId,
      };

  @override
  bool operator ==(Object other) =>
      other is TaskItem &&
      other.id == id &&
      other.title == title &&
      other.description == description &&
      other.status == status &&
      other.dueAt == dueAt &&
      other.completedAt == completedAt &&
      other.spaceId == spaceId &&
      other.noteId == noteId &&
      other.source == source &&
      other.externalId == externalId;

  @override
  int get hashCode => Object.hash(id, title, description, status, dueAt,
      completedAt, spaceId, noteId, source, externalId);
}
