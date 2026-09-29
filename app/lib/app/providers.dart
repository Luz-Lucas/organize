import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repository.dart';
import '../domain/calendar_event.dart';
import '../domain/note.dart';
import '../domain/space.dart';
import '../domain/task_item.dart';

final repositoryProvider = Provider<Repository>(
  (ref) => throw UnimplementedError('repositoryProvider precisa de override'),
);

final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final spacesProvider =
    StreamProvider<List<Space>>((ref) => ref.watch(repositoryProvider).watchSpaces());

final notesProvider =
    StreamProvider<List<Note>>((ref) => ref.watch(repositoryProvider).watchNotes());

final tasksProvider =
    StreamProvider<List<TaskItem>>((ref) => ref.watch(repositoryProvider).watchTasks());

final eventsFromProvider = StreamProvider.autoDispose.family<List<CalendarEvent>, DateTime>(
  (ref, from) => ref.watch(repositoryProvider).watchEvents(from: from),
);

/// Guarda em memória edições de notas que não puderam ser salvas ao sair da
/// tela (ex.: falha de rede), para que sejam recuperadas na próxima abertura.
class NoteDrafts {
  final _drafts = <String, Note>{};

  void put(Note note) => _drafts[note.id] = note;

  Note? take(String id) => _drafts.remove(id);
}

final noteDraftsProvider = Provider<NoteDrafts>((ref) => NoteDrafts());
