import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notebooks_logic.dart';

/// Qual aba da tela Notas está aberta.
enum NotesTab { notes, notebooks }

/// Onde a aba escolhida fica guardada (por aparelho, não vai para a nuvem).
abstract interface class NotesTabPrefs {
  Future<String?> load();
  Future<void> save(String value);
}

class MemoryNotesTabPrefs implements NotesTabPrefs {
  String? _value;

  @override
  Future<String?> load() async => _value;

  @override
  Future<void> save(String value) async => _value = value;
}

class SharedPreferencesNotesTabPrefs implements NotesTabPrefs {
  const SharedPreferencesNotesTabPrefs();

  static const _key = 'notes_tab';

  @override
  Future<String?> load() async => (await SharedPreferences.getInstance()).getString(_key);

  @override
  Future<void> save(String value) async => (await SharedPreferences.getInstance()).setString(_key, value);
}

/// Os testes usam a memória; `main.dart` troca por [SharedPreferencesNotesTabPrefs].
final notesTabPrefsProvider = Provider<NotesTabPrefs>((ref) => MemoryNotesTabPrefs());

class NotesTabNotifier extends Notifier<NotesTab> {
  bool _chosen = false;

  @override
  NotesTab build() {
    unawaited(_restore());
    return NotesTab.notes;
  }

  Future<void> _restore() async {
    try {
      final saved = await ref.read(notesTabPrefsProvider).load();
      if (!_chosen && ref.mounted && saved == NotesTab.notebooks.name) state = NotesTab.notebooks;
    } catch (_) {
      // Sem preferência guardada: fica em Notas.
    }
  }

  void select(NotesTab tab) {
    _chosen = true;
    state = tab;
    unawaited(ref.read(notesTabPrefsProvider).save(tab.name).catchError((Object _) {}));
  }
}

final notesTabProvider = NotifierProvider<NotesTabNotifier, NotesTab>(NotesTabNotifier.new);

/// Pasta aberta em Cadernos: [kFolderAll], [kFolderNone] ou o id de um espaço.
class NotebookFolderNotifier extends Notifier<String> {
  @override
  String build() => kFolderAll;

  void select(String folder) => state = folder;
}

final notebookFolderProvider = NotifierProvider<NotebookFolderNotifier, String>(NotebookFolderNotifier.new);
