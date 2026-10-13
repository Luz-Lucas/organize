import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/imported_file.dart';

/// Registro dos arquivos já sincronizados (tabela `imported_files`, por usuário).
abstract interface class ImportedFilesRepository {
  /// Já existe registro com este sha256 (conteúdo)?
  Future<bool> has(String sha256);

  /// Já existe algum arquivo [source] com este nome (com outro conteúdo, é uma versão nova)?
  Future<bool> hasName(String name, {String source = importSourceSamsungNotes});

  /// Grava o registro. Idempotente: se o sha256 já existe, o primeiro registro permanece.
  Future<void> record(ImportedFile file);
}

final importedFilesRepositoryProvider = Provider<ImportedFilesRepository>(
  (ref) => throw UnimplementedError('importedFilesRepositoryProvider precisa de override'),
);
