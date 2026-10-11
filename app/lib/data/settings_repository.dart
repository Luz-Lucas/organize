import '../domain/user_settings.dart';

abstract interface class SettingsRepository {
  Stream<UserSettings> watchSettings();
  /// Grava só o tema, sem tocar nos demais ajustes.
  Future<void> setTheme(String themeId);

  /// Oculta ou mostra um dispositivo da Alexa, partindo do valor mais
  /// recente guardado (não de uma cópia local que pode estar velha).
  Future<void> setDeviceHidden(String deviceId, bool hidden);
}
