import 'dart:async';

import '../domain/calendar_event.dart';
import '../domain/event_tag.dart';
import '../domain/ids.dart';
import '../domain/note.dart';
import '../domain/space.dart';
import '../domain/task_item.dart';
import '../domain/wikilinks.dart';
import 'repository.dart';

/// Implementação em memória usada nos testes. Reproduz as regras do banco
/// (título único, cascade ao excluir espaço — menos nos cadernos).
class MemoryRepository implements Repository {
  final _spaces = <String, Space>{};
  final _notes = <String, Note>{};
  final _tasks = <String, TaskItem>{};
  final _events = <String, CalendarEvent>{};
  final _tags = <String, EventTag>{};
  final _changes = StreamController<void>.broadcast(sync: true);

  /// Quando true, toda escrita falha, simulando uma queda de conexão.
  bool failWrites = false;

  Stream<List<T>> _watch<T>(List<T> Function() snapshot) {
    StreamSubscription<void>? sub;
    late final StreamController<List<T>> controller;
    controller = StreamController<List<T>>(
      onListen: () {
        controller.add(snapshot());
        sub = _changes.stream.listen((_) => controller.add(snapshot()));
      },
      onCancel: () {
        sub?.cancel();
        controller.close();
      },
    );
    return controller.stream;
  }

  Future<void> _write(void Function() change) async {
    if (failWrites) throw const RepositoryException('Sem conexão (simulado)');
    change();
    _changes.add(null);
  }

  @override
  Stream<List<Space>> watchSpaces() => _watch(
      () => _spaces.values.toList()..sort((a, b) => a.position.compareTo(b.position)));

  @override
  Future<void> upsertSpace(Space space) => _write(() => _spaces[space.id] = space);

  @override
  Future<void> deleteSpace(String id) => _write(() {
        _spaces.remove(id);
        // Cadernos sobrevivem (gatilho `spaces_keep_notebooks` do banco): ficam sem espaço.
        for (final n in _notes.values.where((n) => n.spaceId == id && n.isNotebook).toList()) {
          _notes[n.id] = n.withSpace(null);
        }
        _notes.removeWhere((_, n) => n.spaceId == id);
        _tasks.removeWhere((_, t) => t.spaceId == id);
        for (final e in _events.values.where((e) => e.spaceId == id).toList()) {
          _events[e.id] = e.withoutSpace();
        }
      });

  @override
  Stream<List<Note>> watchNotes() =>
      _watch(() => _notes.values.toList()..sort((a, b) => a.title.compareTo(b.title)));

  @override
  Future<void> upsertNote(Note note) async {
    final key = normalizeTitle(note.title);
    final clash = _notes.values.any((n) => n.id != note.id && normalizeTitle(n.title) == key);
    if (clash) {
      throw RepositoryException('Já existe uma nota "${note.title}"', duplicate: true);
    }
    return _write(() => _notes[note.id] = note);
  }

  @override
  Future<void> deleteNote(String id) => _write(() => _notes.remove(id));

  @override
  Stream<List<TaskItem>> watchTasks() => _watch(() => _tasks.values.toList());

  @override
  Future<void> upsertTask(TaskItem task) => _write(() => _tasks[task.id] = task);

  @override
  Future<void> deleteTask(String id) => _write(() => _tasks.remove(id));

  @override
  Future<void> upsertTasks(List<TaskItem> tasks) {
    if (tasks.isEmpty) return Future.value();
    return _write(() {
      for (final t in tasks) {
        _tasks[t.id] = t;
      }
    });
  }

  @override
  Future<void> deleteTasks(List<String> ids) {
    if (ids.isEmpty) return Future.value();
    return _write(() => ids.forEach(_tasks.remove));
  }

  @override
  Future<List<TaskItem>> listTaskSeries(String seriesId) async =>
      _tasks.values.where((t) => t.seriesId == seriesId).toList()
        ..sort((a, b) {
          final ad = a.dueAt, bd = b.dueAt;
          if (ad == null || bd == null) return ad == null ? (bd == null ? 0 : 1) : -1;
          return ad.compareTo(bd);
        });

  @override
  Stream<List<CalendarEvent>> watchEvents({required DateTime from}) => _watch(() =>
      _events.values.where((e) => !e.endsAt.isBefore(from)).toList()
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt)));

  @override
  Future<void> upsertEvent(CalendarEvent event) => _write(() => _events[event.id] = event);

  @override
  Future<void> deleteEvent(String id) => _write(() => _events.remove(id));

  @override
  Future<void> upsertEvents(List<CalendarEvent> events) {
    if (events.isEmpty) return Future.value();
    return _write(() {
      for (final e in events) {
        _events[e.id] = e;
      }
    });
  }

  @override
  Future<void> deleteEvents(List<String> ids) {
    if (ids.isEmpty) return Future.value();
    return _write(() => ids.forEach(_events.remove));
  }

  @override
  Future<void> deleteSeries(String seriesId, {DateTime? from}) => _write(() => _events.removeWhere(
      (_, e) => e.seriesId == seriesId && (from == null || !e.startsAt.isBefore(from))));

  @override
  Future<List<CalendarEvent>> listSeries(String seriesId) async =>
      _events.values.where((e) => e.seriesId == seriesId).toList()
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt));

  @override
  Stream<List<EventTag>> watchTags() => _watch(() => _sortedTags());

  List<EventTag> _sortedTags() => _tags.values.toList()
    ..sort((a, b) {
      final byPosition = a.position.compareTo(b.position);
      return byPosition != 0 ? byPosition : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

  @override
  Future<void> upsertTag(EventTag tag) async {
    // Como o índice único (user_id, lower(name)) do banco.
    final key = tag.name.trim().toLowerCase();
    final clash = _tags.values.any((t) => t.id != tag.id && t.name.trim().toLowerCase() == key);
    if (clash) {
      throw RepositoryException('Já existe uma etiqueta "${tag.name}"', duplicate: true);
    }
    return _write(() => _tags[tag.id] = tag);
  }

  @override
  Future<void> deleteTag(String id) => _write(() {
        _tags.remove(id);
        // `on delete set null` do banco: os eventos ficam, sem etiqueta.
        for (final e in _events.values.where((e) => e.tagId == id).toList()) {
          _events[e.id] = e.copyWith(clearTag: true);
        }
      });

  @override
  Future<void> reorderTags(List<EventTag> ordered) => _write(() {
        for (var i = 0; i < ordered.length; i++) {
          _tags[ordered[i].id] = ordered[i].copyWith(position: i);
        }
      });

  /// Mesmas etiquetas iniciais da função `seed_event_tags` do banco (por papel). A classificação dos
  /// eventos existentes é do banco e fica fora daqui.
  @override
  Future<int> seedEventTags() async {
    const initial = [
      EventTag(id: '', name: 'Aula', color: '#3E63DD', role: EventTagRole.main, position: 0),
      EventTag(id: '', name: 'Academia', color: '#30A46C', role: EventTagRole.secondary, position: 1),
      EventTag(id: '', name: 'Sazonal', color: '#FFB224', role: EventTagRole.seasonal, position: 2),
      EventTag(id: '', name: 'Reunião', color: '#8E4EC6', role: EventTagRole.meeting, position: 3),
    ];
    final missing = [
      for (final t in initial)
        if (!_tags.values.any((x) => x.role == t.role) &&
            !_tags.values.any((x) => x.name.toLowerCase() == t.name.toLowerCase()))
          t.copyWith(id: newId()),
    ];
    if (missing.isEmpty) return 0;
    await _write(() {
      for (final t in missing) {
        _tags[t.id] = t;
      }
    });
    return missing.length;
  }
}
