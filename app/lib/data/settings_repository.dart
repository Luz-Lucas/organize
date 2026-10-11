import '../domain/user_settings.dart';

abstract interface class SettingsRepository {
  Stream<UserSettings> watchSettings();
  Future<void> saveSettings(UserSettings settings);
}
