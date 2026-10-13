import '../domain/imported_file.dart';
import 'imported_files_repository.dart';
import 'repository.dart';

/// Implementação em memória usada nos testes.
class MemoryImportedFilesRepository implements ImportedFilesRepository {
  final _files = <String, ImportedFile>{};

  /// Faz toda chamada falhar, como uma queda de conexão.
  bool fail = false;

  List<ImportedFile> get all => List.unmodifiable(_files.values);

  void _check() {
    if (fail) throw const RepositoryException('Sem conexão (simulado)');
  }

  @override
  Future<bool> has(String sha256) async {
    _check();
    return _files.containsKey(sha256);
  }

  @override
  Future<bool> hasName(String name, {String source = importSourceSamsungNotes}) async {
    _check();
    return _files.values.any((f) => f.name == name && f.source == source);
  }

  @override
  Future<void> record(ImportedFile file) async {
    _check();
    _files.putIfAbsent(file.sha256, () => file);
  }
}
