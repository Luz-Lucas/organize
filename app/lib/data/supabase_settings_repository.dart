import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/user_settings.dart';
import 'repository.dart';
import 'settings_repository.dart';

class SupabaseSettingsRepository implements SettingsRepository {
  SupabaseSettingsRepository(this._db, {String Function()? userId}) : _userIdOverride = userId;

  final SupabaseClient _db;
  final String Function()? _userIdOverride;

  @override
  Stream<UserSettings> watchSettings() => _db
      .from('user_settings')
      .stream(primaryKey: ['user_id']).map(
          (rows) => rows.isEmpty ? const UserSettings() : UserSettings.fromMap(rows.first));

  Future<T> _guard<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on PostgrestException catch (e) {
      throw RepositoryException(e.message);
    } on RepositoryException {
      rethrow;
    } catch (e) {
      throw RepositoryException('Falha de conexão: $e');
    }
  }

  String get _userId => _userIdOverride != null ? _userIdOverride() : _db.auth.currentUser!.id;

  @override
  Future<void> setTheme(String themeId) => _guard(() async {
        await _db.from('user_settings').upsert({'user_id': _userId, 'theme': themeId});
      });

  @override
  Future<void> setDeviceHidden(String deviceId, bool hidden) => _guard(() async {
        // Lê o valor mais recente do servidor e grava só esta coluna.
        final row = await _db
            .from('user_settings')
            .select('hidden_alexa_devices')
            .eq('user_id', _userId)
            .maybeSingle();
        final current = ((row?['hidden_alexa_devices'] as List?) ?? const []).cast<String>();
        final ids = [...current.where((x) => x != deviceId), if (hidden) deviceId];
        await _db.from('user_settings').upsert({'user_id': _userId, 'hidden_alexa_devices': ids});
      });

  @override
  Future<void> setHome(double lat, double lon) => _guard(() async {
        await _db.from('user_settings').upsert({'user_id': _userId, 'home_lat': lat, 'home_lon': lon});
      });

  @override
  Future<void> clearHome() => _guard(() async {
        await _db.from('user_settings').upsert({'user_id': _userId, 'home_lat': null, 'home_lon': null});
      });

  @override
  Future<void> setRequireHome(bool value) => _guard(() async {
        await _db.from('user_settings').upsert({'user_id': _userId, 'require_home': value});
      });
}
