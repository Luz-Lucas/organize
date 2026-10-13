import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Armazenamento local do caderno, por nota. Guarda duas coisas independentes:
///
/// * a **fila** de alterações ainda não confirmadas no servidor (`load`/`save`/`clear`);
/// * o **cache** da última lista de páginas conhecida (`loadPagesCache`…), para abrir
///   e escrever offline.
///
/// O conteúdo é um JSON opaco para o armazenamento; quem o monta é o `NotebookController`.
abstract interface class NotebookPendingStore {
  Future<Map<String, Object?>?> load(String noteId);
  Future<void> save(String noteId, Map<String, Object?> json);
  Future<void> clear(String noteId);

  /// Ids dos cadernos que têm fila guardada (para enviar tudo ao iniciar o app).
  Future<List<String>> pendingNoteIds();

  Future<Map<String, Object?>?> loadPagesCache(String noteId);
  Future<void> savePagesCache(String noteId, Map<String, Object?> json);
  Future<void> clearPagesCache(String noteId);
}

class MemoryNotebookPendingStore implements NotebookPendingStore {
  final _data = <String, String>{};
  final _cache = <String, String>{};

  Map<String, Object?>? _decode(String? raw) => raw == null ? null : (jsonDecode(raw) as Map).cast<String, Object?>();

  @override
  Future<Map<String, Object?>?> load(String noteId) async => _decode(_data[noteId]);

  @override
  Future<void> save(String noteId, Map<String, Object?> json) async => _data[noteId] = jsonEncode(json);

  @override
  Future<void> clear(String noteId) async => _data.remove(noteId);

  @override
  Future<List<String>> pendingNoteIds() async => _data.keys.toList();

  @override
  Future<Map<String, Object?>?> loadPagesCache(String noteId) async => _decode(_cache[noteId]);

  @override
  Future<void> savePagesCache(String noteId, Map<String, Object?> json) async => _cache[noteId] = jsonEncode(json);

  @override
  Future<void> clearPagesCache(String noteId) async => _cache.remove(noteId);
}

/// Guarda em `shared_preferences` (fila em `notebook.pending.<noteId>`, cache em
/// `notebook.cache.<noteId>`). Um JSON corrompido é ignorado.
class SharedPreferencesNotebookPendingStore implements NotebookPendingStore {
  const SharedPreferencesNotebookPendingStore();

  static const _pendingPrefix = 'notebook.pending.';
  static const _cachePrefix = 'notebook.cache.';

  static String key(String noteId) => '$_pendingPrefix$noteId';
  static String cacheKey(String noteId) => '$_cachePrefix$noteId';

  Future<Map<String, Object?>?> _read(String k) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(k);
    if (raw == null) return null;
    try {
      return (jsonDecode(raw) as Map).cast<String, Object?>();
    } catch (_) {
      await prefs.remove(k);
      return null;
    }
  }

  Future<void> _write(String k, Map<String, Object?> json) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(k, jsonEncode(json));
  }

  Future<void> _remove(String k) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(k);
  }

  @override
  Future<Map<String, Object?>?> load(String noteId) => _read(key(noteId));

  @override
  Future<void> save(String noteId, Map<String, Object?> json) => _write(key(noteId), json);

  @override
  Future<void> clear(String noteId) => _remove(key(noteId));

  @override
  Future<List<String>> pendingNoteIds() async {
    final prefs = await SharedPreferences.getInstance();
    return [
      for (final k in prefs.getKeys())
        if (k.startsWith(_pendingPrefix)) k.substring(_pendingPrefix.length),
    ];
  }

  @override
  Future<Map<String, Object?>?> loadPagesCache(String noteId) => _read(cacheKey(noteId));

  @override
  Future<void> savePagesCache(String noteId, Map<String, Object?> json) => _write(cacheKey(noteId), json);

  @override
  Future<void> clearPagesCache(String noteId) => _remove(cacheKey(noteId));
}
