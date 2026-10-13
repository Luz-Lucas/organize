import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/imported_file.dart';
import 'imported_files_repository.dart';
import 'repository.dart';

/// `imported_files` no Supabase. A RLS limita tudo ao dono; o `user_id` vem de `auth.uid()` (default da coluna).
class SupabaseImportedFilesRepository implements ImportedFilesRepository {
  SupabaseImportedFilesRepository(this._db);

  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on PostgrestException catch (e) {
      throw RepositoryException(e.message);
    } on RepositoryException {
      rethrow;
    } catch (_) {
      throw const RepositoryException('Falha de conexão. Verifique a internet e tente de novo.');
    }
  }

  @override
  Future<bool> has(String sha256) => _guard(() async {
        final rows = await _db.from('imported_files').select('sha256').eq('sha256', sha256).limit(1);
        return rows.isNotEmpty;
      });

  @override
  Future<bool> hasName(String name, {String source = importSourceSamsungNotes}) => _guard(() async {
        final rows = await _db.from('imported_files').select('sha256').eq('name', name).eq('source', source).limit(1);
        return rows.isNotEmpty;
      });

  @override
  Future<void> record(ImportedFile file) => _guard(() async {
        await _db.from('imported_files').upsert(file.toMap(), onConflict: 'user_id,sha256', ignoreDuplicates: true);
      });
}
