import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/update/update_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('SharedPreferencesUpdatePrefs guarda a última checagem e o build dispensado', () async {
    const prefs = SharedPreferencesUpdatePrefs();
    expect(await prefs.lastCheck(), isNull);
    expect(await prefs.dismissedBuild(), 0);
    final t = DateTime(2026, 10, 27, 9, 30);
    await prefs.setLastCheck(t);
    await prefs.setDismissedBuild(7);
    expect(await prefs.lastCheck(), t);
    expect(await prefs.dismissedBuild(), 7);
  });

  test('valor de outro tipo ou leitura impossível não quebra: age como se nunca tivesse checado', () async {
    SharedPreferences.setMockInitialValues({'update_last_check': 'lixo', 'update_dismissed_build': 'x'});
    const prefs = SharedPreferencesUpdatePrefs();
    expect(await prefs.lastCheck(), isNull);
    expect(await prefs.dismissedBuild(), 0);
  });
}
