import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/calendar_event.dart';
import '../domain/event_tag.dart';
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
  Future<void> upsertTasks(List<TaskItem> tasks) {
    if (tasks.isEmpty) return Future.value();
    return _guard(() async => await _db.from('tasks').upsert(tasks.map((t) => t.toMap()).toList()));
  }

  /// Em lotes: o filtro `id in (...)` vai na URL e uma série longa (até 366 uuids) a estouraria.
  @override
  Future<void> deleteTasks(List<String> ids) => _guard(() async {
        for (var i = 0; i < ids.length; i += _deleteBatch) {
          final batch = ids.sublist(i, i + _deleteBatch > ids.length ? ids.length : i + _deleteBatch);
          await _db.from('tasks').delete().inFilter('id', batch);
        }
      });

  static const _deleteBatch = 100;

  @override
  Future<List<TaskItem>> listTaskSeries(String seriesId) async {
    try {
      final rows = await _db.from('tasks').select().eq('series_id', seriesId).order('due_at', ascending: true);
      return rows.map<TaskItem>(TaskItem.fromMap).toList();
    } on PostgrestException catch (e) {
      throw RepositoryException(e.message);
    } catch (e) {
      throw RepositoryException('Falha de conexão: $e');
    }
  }

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

  @override
  Future<void> upsertEvents(List<CalendarEvent> events) {
    if (events.isEmpty) return Future.value();
    return _guard(() async => await _db.from('events').upsert(events.map((e) => e.toMap()).toList()));
  }

  @override
  Future<void> deleteEvents(List<String> ids) {
    if (ids.isEmpty) return Future.value();
    return _guard(() async => await _db.from('events').delete().inFilter('id', ids));
  }

  @override
  Future<void> deleteSeries(String seriesId, {DateTime? from}) => _guard(() async {
        var q = _db.from('events').delete().eq('series_id', seriesId);
        if (from != null) q = q.gte('starts_at', from.toUtc().toIso8601String());
        await q;
      });

  @override
  Future<List<CalendarEvent>> listSeries(String seriesId) async {
    try {
      final rows = await _db.from('events').select().eq('series_id', seriesId).order('starts_at', ascending: true);
      return rows.map<CalendarEvent>(CalendarEvent.fromMap).toList();
    } on PostgrestException catch (e) {
      throw RepositoryException(e.message);
    } catch (e) {
      throw RepositoryException('Falha de conexão: $e');
    }
  }

  @override
  Stream<List<EventTag>> watchTags() => _watch('event_tags', EventTag.fromMap, 'position');

  @override
  Future<void> upsertTag(EventTag tag) => _upsert('event_tags', tag.toMap());

  @override
  Future<void> deleteTag(String id) => _delete('event_tags', id);

  @override
  Future<void> reorderTags(List<EventTag> ordered) {
    if (ordered.isEmpty) return Future.value();
    return _guard(() async => await _db
        .from('event_tags')
        .upsert([for (var i = 0; i < ordered.length; i++) ordered[i].copyWith(position: i).toMap()]));
  }

  @override
  Future<int> seedEventTags() async {
    try {
      final n = await _db.rpc('seed_my_event_tags');
      return n is num ? n.toInt() : 0;
    } on PostgrestException catch (e) {
      throw RepositoryException(e.message);
    } catch (e) {
      throw RepositoryException('Falha de conexão: $e');
    }
  }
}
