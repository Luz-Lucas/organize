import '../domain/calendar_event.dart';
import '../domain/event_tag.dart';
import '../domain/note.dart';
import '../domain/notice.dart';
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

  /// Grava/apaga várias ocorrências de uma vez (séries de eventos).
  Future<void> upsertEvents(List<CalendarEvent> events);
  Future<void> deleteEvents(List<String> ids);

  /// Apaga a série por `series_id`; com [from], só as ocorrências que começam em [from] ou depois.
  /// Evita mandar uma lista enorme de ids em séries longas.
  Future<void> deleteSeries(String seriesId, {DateTime? from});

  /// Todas as ocorrências da série (inclusive as já passadas), por início.
  Future<List<CalendarEvent>> listSeries(String seriesId);

  /// Etiquetas coloridas dos eventos, por posição.
  Stream<List<EventTag>> watchTags();
  Future<void> upsertTag(EventTag tag);

  /// Os eventos com a etiqueta ficam sem etiqueta (o banco faz `on delete set null`).
  Future<void> deleteTag(String id);

  /// Regrava as posições das etiquetas como 0..n-1, na ordem recebida.
  Future<void> reorderTags(List<EventTag> ordered);

  /// Cria as etiquetas iniciais (Aula, Academia, Sazonal, Reunião) que faltam e classifica os eventos
  /// ainda sem etiqueta. Devolve quantas etiquetas criou; chamar de novo não cria nada.
  Future<int> seedEventTags();

  Stream<List<Notice>> watchNotices();
  Future<void> upsertNotice(Notice notice);
  Future<void> deleteNotice(String id);
}
