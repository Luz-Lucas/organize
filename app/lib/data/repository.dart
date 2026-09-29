import '../domain/calendar_event.dart';
import '../domain/note.dart';
import '../domain/space.dart';
import '../domain/task_item.dart';

class RepositoryException implements Exception {
  const RepositoryException(this.message, {this.duplicate = false});

  final String message;
  final bool duplicate;

  @override
  String toString() => 'RepositoryException: $message';
}

abstract interface class Repository {
  Stream<List<Space>> watchSpaces();
  Future<void> upsertSpace(Space space);
  Future<void> deleteSpace(String id);

  Stream<List<Note>> watchNotes();
  Future<void> upsertNote(Note note);
  Future<void> deleteNote(String id);

  Stream<List<TaskItem>> watchTasks();
  Future<void> upsertTask(TaskItem task);
  Future<void> deleteTask(String id);

  /// Eventos que terminam em [from] ou depois.
  Stream<List<CalendarEvent>> watchEvents({required DateTime from});
  Future<void> upsertEvent(CalendarEvent event);
  Future<void> deleteEvent(String id);
}
