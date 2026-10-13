import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Fila local do caderno (alterações ainda não confirmadas no servidor), uma por nota.
/// O conteúdo é um JSON opaco para o armazenamento; quem o monta é o `NotebookController`.
abstract interface class NotebookPendingStore {
  Future<Map<String, Object?>?> load(String noteId);
  Future<void> save(String noteId, Map<String, Object?> json);
  Future<void> clear(String noteId);
}

class MemoryNotebookPendingStore implements NotebookPendingStore {
  final _data = <String, String>{};

  @override
  Future<Map<String, Object?>?> load(String noteId) async {
    final raw = _data[noteId];
    return raw == null ? null : (jsonDecode(raw) as Map).cast<String, Object?>();
  }

  @override
  Future<void> save(String noteId, Map<String, Object?> json) async => _data[noteId] = jsonEncode(json);

  @override
  Future<void> clear(String noteId) async => _data.remove(noteId);
}

/// Guarda em `shared_preferences` (chave `notebook.pending.<noteId>`). Um JSON corrompido é ignorado.
class SharedPreferencesNotebookPendingStore implements NotebookPendingStore {
  const SharedPreferencesNotebookPendingStore();

  static String key(String noteId) => 'notebook.pending.$noteId';

  @override
  Future<Map<String, Object?>?> load(String noteId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key(noteId));
    if (raw == null) return null;
    try {
      return (jsonDecode(raw) as Map).cast<String, Object?>();
    } catch (_) {
      await prefs.remove(key(noteId));
      return null;
    }
  }

  @override
  Future<void> save(String noteId, Map<String, Object?> json) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key(noteId), jsonEncode(json));
  }

  @override
  Future<void> clear(String noteId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key(noteId));
  }
}
