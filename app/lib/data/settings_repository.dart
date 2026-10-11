import '../domain/user_settings.dart';

abstract interface class SettingsRepository {
  Stream<UserSettings> watchSettings();
  /// Grava só o tema, sem tocar nos demais ajustes.
  Future<void> setTheme(String themeId);

  /// Oculta ou mostra um dispositivo da Alexa, partindo do valor mais
  /// recente guardado (não de uma cópia local que pode estar velha).
  Future<void> setDeviceHidden(String deviceId, bool hidden);

  /// Define a casa (grava só lat/lon, sem tocar nos demais ajustes).
  Future<void> setHome(double lat, double lon);

  /// Remove a casa (lat/lon nulos).
  Future<void> clearHome();

  /// Liga/desliga "só tocar o despertar quando eu estiver em casa".
  Future<void> setRequireHome(bool value);
}
