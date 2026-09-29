import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/calendar_event.dart';
import '../domain/note.dart';
import '../domain/space.dart';
import '../domain/task_item.dart';
import 'repository.dart';

class SupabaseRepository implements Repository {
  SupabaseRepository(this._db);

  final SupabaseClient _db;

  Stream<List<T>> _watch<T>(
    String table,
    T Function(Map<String, dynamic>) fromMap,
    String orderBy,
  ) =>
      _db
          .from(table)
          .stream(primaryKey: ['id'])
          .order(orderBy, ascending: true)
          .map((rows) => rows.map(fromMap).toList());

  Future<void> _guard(Future<void> Function() op) async {
    try {
      await op();
    } on PostgrestException catch (e) {
      throw RepositoryException(e.message, duplicate: e.code == '23505');
    } on RepositoryException {
      rethrow;
    } catch (e) {
      throw RepositoryException('Falha de conexão: $e');
    }
  }

  Future<void> _upsert(String table, Map<String, dynamic> row) =>
      _guard(() async => await _db.from(table).upsert(row));

  Future<void> _delete(String table, String id) =>
      _guard(() async => await _db.from(table).delete().eq('id', id));

  @override
  Stream<List<Space>> watchSpaces() => _watch('spaces', Space.fromMap, 'position');

  @override
  Future<void> upsertSpace(Space space) => _upsert('spaces', space.toMap());

  @override
  Future<void> deleteSpace(String id) => _delete('spaces', id);

  @override
  Stream<List<Note>> watchNotes() => _watch('notes', Note.fromMap, 'title');

  @override
  Future<void> upsertNote(Note note) => _upsert('notes', note.toMap());

  @override
  Future<void> deleteNote(String id) => _delete('notes', id);

  @override
  Stream<List<TaskItem>> watchTasks() => _watch('tasks', TaskItem.fromMap, 'created_at');

  @override
  Future<void> upsertTask(TaskItem task) => _upsert('tasks', task.toMap());

  @override
  Future<void> deleteTask(String id) => _delete('tasks', id);

  @override
  Stream<List<CalendarEvent>> watchEvents({required DateTime from}) => _db
      .from('events')
      .stream(primaryKey: ['id'])
      .gte('ends_at', from.toUtc().toIso8601String())
      .order('starts_at', ascending: true)
      .map((rows) => rows.map(CalendarEvent.fromMap).toList());

  @override
  Future<void> upsertEvent(CalendarEvent event) => _upsert('events', event.toMap());

  @override
  Future<void> deleteEvent(String id) => _delete('events', id);
}
