import 'package:shared_preferences/shared_preferences.dart';

/// O que o app lembra, por aparelho, sobre atualizações: quando checou pela última vez e qual versão o
/// usuário dispensou com "Depois".
abstract interface class UpdatePrefsStore {
  Future<DateTime?> lastCheck();
  Future<void> setLastCheck(DateTime at);

  /// Maior build dispensado (0 = nenhum).
  Future<int> dismissedBuild();
  Future<void> setDismissedBuild(int build);
}

class MemoryUpdatePrefs implements UpdatePrefsStore {
  DateTime? _last;
  int _dismissed = 0;

  @override
  Future<DateTime?> lastCheck() async => _last;
  @override
  Future<void> setLastCheck(DateTime at) async => _last = at;
  @override
  Future<int> dismissedBuild() async => _dismissed;
  @override
  Future<void> setDismissedBuild(int build) async => _dismissed = build;
}

class SharedPreferencesUpdatePrefs implements UpdatePrefsStore {
  const SharedPreferencesUpdatePrefs();

  static const _lastKey = 'update_last_check';
  static const _dismissedKey = 'update_dismissed_build';

  @override
  Future<DateTime?> lastCheck() async {
    try {
      final ms = (await SharedPreferences.getInstance()).getInt(_lastKey);
      return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {
      return null; // valor de outro tipo ou leitura impossível: como se nunca tivesse checado
    }
  }

  @override
  Future<void> setLastCheck(DateTime at) async =>
      (await SharedPreferences.getInstance()).setInt(_lastKey, at.millisecondsSinceEpoch);

  @override
  Future<int> dismissedBuild() async {
    try {
      return (await SharedPreferences.getInstance()).getInt(_dismissedKey) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  @override
  Future<void> setDismissedBuild(int build) async =>
      (await SharedPreferences.getInstance()).setInt(_dismissedKey, build);
}
