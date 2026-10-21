import 'dart:async';

import '../domain/user_settings.dart';
import '../sync/local_store.dart';
import 'settings_repository.dart';

const _table = 'user_settings';

/// Ajustes local-primeiro: lê e grava a linha do usuário em `user_settings` no [LocalStore]; o envio à
/// nuvem é do `SyncEngine`. Cada escrita manda só as colunas que mudaram (upsert parcial por `user_id`),
/// então ajustes feitos em outro aparelho nas demais colunas não são sobrescritos.
class LocalFirstSettingsRepository implements SettingsRepository {
  LocalFirstSettingsRepository(this._store, this._userId);

  final LocalStore _store;
  final String _userId;

  /// Escritas que leem antes de gravar (ocultar dispositivo) rodam uma de cada vez.
  Future<void> _serial = Future.value();

  Future<void> _exclusive(Future<void> Function() op) {
    final done = _serial.then((_) => op());
    _serial = done.then<void>((_) {}, onError: (_) {});
    return done;
  }

  Future<void> _write(Map<String, dynamic> columns) => _store.put(_table, {'user_id': _userId, ...columns});

  @override
  Stream<UserSettings> watchSettings() => _store.watch(_table).map((rows) {
        for (final r in rows) {
          if (r['user_id'] == _userId) return UserSettings.fromMap(r);
        }
        return const UserSettings();
      });

  @override
  Future<void> setTheme(String themeId) => _write({'theme': themeId});

  @override
  Future<void> setDeviceHidden(String deviceId, bool hidden) => _exclusive(() async {
        final row = await _store.get(_table, _userId);
        final current = ((row?['hidden_alexa_devices'] as List?) ?? const []).cast<String>();
        await _write({
          'hidden_alexa_devices': [...current.where((x) => x != deviceId), if (hidden) deviceId],
        });
      });

  @override
  Future<void> setHome(double lat, double lon) => _write({'home_lat': lat, 'home_lon': lon});

  @override
  Future<void> clearHome() => _write({'home_lat': null, 'home_lon': null});

  @override
  Future<void> setRequireHome(bool value) => _write({'require_home': value});

  @override
  Future<void> setNotebookPrefs(Map<String, dynamic> prefs) => _write({'notebook_prefs': prefs});

  @override
  Future<void> setRemindersPhone(bool value) => _write({'reminders_phone': value});

  @override
  Future<void> setRemindersAlexa(bool value) => _write({'reminders_alexa': value});

  @override
  Future<void> setReminderEcho(String? deviceId) => _write({'reminder_echo': deviceId});

  @override
  Future<void> setDnd({bool? enabled, int? start, int? end}) => _write({
        'dnd_enabled': ?enabled,
        if (start != null) 'dnd_start': formatMinutesOfDay(start),
        if (end != null) 'dnd_end': formatMinutesOfDay(end),
      });
}
