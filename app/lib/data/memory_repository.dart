import 'dart:async';

import '../domain/calendar_event.dart';
import '../domain/note.dart';
import '../domain/space.dart';
import '../domain/task_item.dart';
import '../domain/wikilinks.dart';
import 'repository.dart';

/// Implementação em memória usada nos testes. Reproduz as regras do banco
/// (título único, cascade ao excluir espaço).
class MemoryRepository implements Repository {
  final _spaces = <String, Space>{};
  final _notes = <String, Note>{};
  final _tasks = <String, TaskItem>{};
  final _events = <String, CalendarEvent>{};
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
  Stream<List<CalendarEvent>> watchEvents({required DateTime from}) => _watch(() =>
      _events.values.where((e) => !e.endsAt.isBefore(from)).toList()
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt)));

  @override
  Future<void> upsertEvent(CalendarEvent event) => _write(() => _events[event.id] = event);

  @override
  Future<void> deleteEvent(String id) => _write(() => _events.remove(id));
}
