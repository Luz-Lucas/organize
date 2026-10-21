import 'dart:async';

import '../domain/calendar_event.dart';
import '../domain/event_tag.dart';
import '../domain/note.dart';
import '../domain/space.dart';
import '../domain/task_item.dart';
import '../domain/wikilinks.dart';
import '../sync/local_store.dart';
import 'repository.dart';

/// Repositório principal local-primeiro: lê e grava só no banco do aparelho ([LocalStore]); o envio à
/// nuvem é do `SyncEngine`. Por isso as escritas nunca falham por falta de rede.
///
/// As regras que o banco aplicaria no servidor e que a tela precisa ver na hora (título único, cascatas
/// de excluir espaço/nota/etiqueta) são reproduzidas aqui — cada linha alterada pela cascata também entra
/// na fila, inteira, para a nuvem ficar igual mesmo que a cascata dela não rode.
class LocalFirstRepository implements Repository {
  /// [seedEventTagsRemote] chama a RPC `seed_my_event_tags` do servidor (devolve quantas etiquetas criou);
  /// sem ela, ou se falhar, [seedEventTags] devolve 0. [now] é o relógio (só para ordenar as tarefas novas).
  LocalFirstRepository(
    this._store, {
    Future<int> Function()? seedEventTagsRemote,
    DateTime Function()? now,
  })  : _seedRemote = seedEventTagsRemote,
        _now = now ?? DateTime.now;

  final LocalStore _store;
  final Future<int> Function()? _seedRemote;
  final DateTime Function() _now;

  static const _spaces = 'spaces';
  static const _notes = 'notes';
  static const _tasks = 'tasks';
  static const _events = 'events';
  static const _tags = 'event_tags';

  Future<List<Note>> _allNotes() async => [for (final r in await _store.all(_notes)) Note.fromMap(r)];
  Future<List<TaskItem>> _allTasks() async => [for (final r in await _store.all(_tasks)) TaskItem.fromMap(r)];
  Future<List<CalendarEvent>> _allEvents() async =>
      [for (final r in await _store.all(_events)) CalendarEvent.fromMap(r)];

  // ---------------------------------------------------------------- espaços

  @override
  Stream<List<Space>> watchSpaces() => _store.watch(_spaces).map((rows) => [for (final r in rows) Space.fromMap(r)]
    ..sort((a, b) {
      final byPosition = a.position.compareTo(b.position);
      if (byPosition != 0) return byPosition;
      final byName = a.name.compareTo(b.name);
      return byName != 0 ? byName : a.id.compareTo(b.id);
    }));

  @override
  Future<void> upsertSpace(Space space) => _store.put(_spaces, space.toMap());

  /// Como o banco: notas do espaço somem (menos os cadernos, que ficam sem espaço — gatilho
  /// `spaces_keep_notebooks`) junto com as filhas delas, as tarefas somem e os eventos ficam sem espaço.
  @override
  Future<void> deleteSpace(String id) async {
    final notes = await _allNotes();
    final tasks = await _allTasks();
    final events = await _allEvents();
    final doomedNotes = _withDescendants(notes, {
      for (final n in notes)
        if (n.spaceId == id && !n.isNotebook) n.id,
    });
    final doomedTasks = {
      for (final t in tasks)
        if (t.spaceId == id) t.id,
    };
    // Todas as chamadas abaixo gravam de forma síncrona; sem `await` entre elas a tela vê o resultado
    // final numa emissão só. A ordem da fila é a do envio: o espaço por último.
    await Future.wait([
      _store.putMany(_notes, [
        for (final n in notes)
          if (n.spaceId == id && n.isNotebook && !doomedNotes.contains(n.id)) n.withSpace(null).toMap(),
      ]),
      _store.putMany(_tasks, [
        for (final t in tasks)
          if (!doomedTasks.contains(t.id) && doomedNotes.contains(t.noteId)) {...t.toMap(), 'note_id': null},
      ]),
      _store.putMany(_events, [
        for (final e in events)
          if (e.spaceId == id) e.withoutSpace().toMap(),
      ]),
      _store.removeMany(_tasks, doomedTasks.toList()),
      _store.removeMany(_notes, doomedNotes.toList()),
      _store.remove(_spaces, id),
    ]);
  }

  // ---------------------------------------------------------------- notas

  @override
  Stream<List<Note>> watchNotes() => _store.watch(_notes).map((rows) => [for (final r in rows) Note.fromMap(r)]
    ..sort((a, b) {
      final byTitle = a.title.compareTo(b.title);
      return byTitle != 0 ? byTitle : a.id.compareTo(b.id);
    }));

  @override
  Future<void> upsertNote(Note note) async {
    // Como o índice único do banco (título sem caixa nem espaços repetidos), visto do que há no aparelho.
    final key = normalizeTitle(note.title);
    final clash = (await _allNotes()).any((n) => n.id != note.id && normalizeTitle(n.title) == key);
    if (clash) {
      throw RepositoryException('Já existe uma nota "${note.title}"', duplicate: true);
    }
    return _store.put(_notes, note.toMap());
  }

  /// Como o banco: as notas filhas (`parent_id`) somem junto e as tarefas ligadas a elas ficam sem nota.
  @override
  Future<void> deleteNote(String id) async {
    final doomed = _withDescendants(await _allNotes(), {id});
    final tasks = await _allTasks();
    await Future.wait([
      _store.putMany(_tasks, [
        for (final t in tasks)
          if (doomed.contains(t.noteId)) {...t.toMap(), 'note_id': null},
      ]),
      _store.removeMany(_notes, doomed.toList()),
    ]);
  }

  /// [roots] mais tudo que descende deles por `parent_id` (`on delete cascade`).
  Set<String> _withDescendants(List<Note> notes, Set<String> roots) {
    final doomed = {...roots};
    var grew = true;
    while (grew) {
      grew = false;
      for (final n in notes) {
        if (n.parentId != null && doomed.contains(n.parentId) && doomed.add(n.id)) grew = true;
      }
    }
    return doomed;
  }

  // ---------------------------------------------------------------- tarefas

  /// Ordem de criação (`created_at`, que o servidor preenche e a tarefa nova recebe daqui); sem ela, por último.
  @override
  Stream<List<TaskItem>> watchTasks() => _store.watch(_tasks).map((rows) {
        final sorted = [...rows]..sort((a, b) {
            final ac = parseSyncTimestamp(a['created_at']), bc = parseSyncTimestamp(b['created_at']);
            if (ac != bc) {
              if (ac == null || bc == null) return ac == null ? 1 : -1;
              return ac.compareTo(bc);
            }
            return (a['id'] as String).compareTo(b['id'] as String);
          });
        return [for (final r in sorted) TaskItem.fromMap(r)];
      });

  @override
  Future<void> upsertTask(TaskItem task) => upsertTasks([task]);

  @override
  Future<void> deleteTask(String id) => _store.remove(_tasks, id);

  @override
  Future<void> upsertTasks(List<TaskItem> tasks) async {
    if (tasks.isEmpty) return;
    // Tarefa nova leva o `created_at` daqui (crescente dentro do lote) para manter a ordem de criação
    // antes de o servidor devolver a linha; nas que já existem o valor original continua.
    final withCreated = {
      for (final r in await _store.all(_tasks))
        if (r['created_at'] != null) r['id'] as String,
    };
    final base = _now().toUtc();
    await _store.putMany(_tasks, [
      for (var i = 0; i < tasks.length; i++)
        {
          ...tasks[i].toMap(),
          if (!withCreated.contains(tasks[i].id)) 'created_at': base.add(Duration(microseconds: i)).toIso8601String(),
        },
    ]);
  }

  @override
  Future<void> deleteTasks(List<String> ids) => _store.removeMany(_tasks, ids);

  @override
  Future<List<TaskItem>> listTaskSeries(String seriesId) async =>
      [for (final t in await _allTasks()) if (t.seriesId == seriesId) t]..sort((a, b) {
          final ad = a.dueAt, bd = b.dueAt;
          if (ad != bd) {
            if (ad == null || bd == null) return ad == null ? 1 : -1;
            return ad.compareTo(bd);
          }
          return a.id.compareTo(b.id);
        });

  // ---------------------------------------------------------------- eventos

  @override
  Stream<List<CalendarEvent>> watchEvents({required DateTime from}) =>
      _store.watch(_events).map((rows) => [
            for (final r in rows)
              if (!CalendarEvent.fromMap(r).endsAt.isBefore(from)) CalendarEvent.fromMap(r),
          ]..sort(_byStart));

  static int _byStart(CalendarEvent a, CalendarEvent b) {
    final byStart = a.startsAt.compareTo(b.startsAt);
    return byStart != 0 ? byStart : a.id.compareTo(b.id);
  }

  @override
  Future<void> upsertEvent(CalendarEvent event) => _store.put(_events, event.toMap());

  @override
  Future<void> deleteEvent(String id) => _store.remove(_events, id);

  @override
  Future<void> upsertEvents(List<CalendarEvent> events) =>
      _store.putMany(_events, [for (final e in events) e.toMap()]);

  @override
  Future<void> deleteEvents(List<String> ids) => _store.removeMany(_events, ids);

  @override
  Future<void> deleteSeries(String seriesId, {DateTime? from}) async {
    final ids = [
      for (final e in await _allEvents())
        if (e.seriesId == seriesId && (from == null || !e.startsAt.isBefore(from))) e.id,
    ];
    await _store.removeMany(_events, ids);
  }

  @override
  Future<List<CalendarEvent>> listSeries(String seriesId) async =>
      [for (final e in await _allEvents()) if (e.seriesId == seriesId) e]..sort(_byStart);

  // ---------------------------------------------------------------- etiquetas

  @override
  Stream<List<EventTag>> watchTags() => _store.watch(_tags).map((rows) => [for (final r in rows) EventTag.fromMap(r)]
    ..sort((a, b) {
      final byPosition = a.position.compareTo(b.position);
      if (byPosition != 0) return byPosition;
      final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return byName != 0 ? byName : a.id.compareTo(b.id);
    }));

  @override
  Future<void> upsertTag(EventTag tag) async {
    // Como o índice único (user_id, lower(name)) do banco.
    final key = tag.name.trim().toLowerCase();
    final all = [for (final r in await _store.all(_tags)) EventTag.fromMap(r)];
    if (all.any((t) => t.id != tag.id && t.name.trim().toLowerCase() == key)) {
      throw RepositoryException('Já existe uma etiqueta "${tag.name}"', duplicate: true);
    }
    return _store.put(_tags, tag.toMap());
  }

  /// Como o banco (`on delete set null`): os eventos ficam, sem etiqueta.
  @override
  Future<void> deleteTag(String id) async {
    final events = await _allEvents();
    await Future.wait([
      _store.putMany(_events, [
        for (final e in events)
          if (e.tagId == id) e.copyWith(clearTag: true).toMap(),
      ]),
      _store.remove(_tags, id),
    ]);
  }

  @override
  Future<void> reorderTags(List<EventTag> ordered) =>
      _store.putMany(_tags, [for (var i = 0; i < ordered.length; i++) ordered[i].copyWith(position: i).toMap()]);

  /// As etiquetas iniciais e a classificação dos eventos são do servidor (RPC): sem rede, ou sem a função
  /// injetada, não cria nada e devolve 0 — o app tenta de novo na próxima abertura. As etiquetas criadas
  /// chegam depois pela sincronização.
  @override
  Future<int> seedEventTags() async {
    final remote = _seedRemote;
    if (remote == null) return 0;
    try {
      return await remote();
    } catch (_) {
      return 0;
    }
  }
}
