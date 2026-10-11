import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/user_settings.dart';
import 'repository.dart';
import 'settings_repository.dart';

class SupabaseSettingsRepository implements SettingsRepository {
  SupabaseSettingsRepository(this._db);

  final SupabaseClient _db;

  @override
  Stream<UserSettings> watchSettings() => _db
      .from('user_settings')
      .stream(primaryKey: ['user_id']).map(
          (rows) => rows.isEmpty ? const UserSettings() : UserSettings.fromMap(rows.first));

  @override
  Future<void> saveSettings(UserSettings settings) async {
    try {
      await _db
          .from('user_settings')
          .upsert({...settings.toMap(), 'user_id': _db.auth.currentUser!.id});
    } on PostgrestException catch (e) {
      throw RepositoryException(e.message);
    } on RepositoryException {
      rethrow;
    } catch (e) {
      throw RepositoryException('Falha de conexão: $e');
    }
  }
}
