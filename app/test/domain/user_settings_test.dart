import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/domain/user_settings.dart';

void main() {
  test('tema desconhecido ou ausente vira violeta', () {
    expect(UserSettings.fromMap({'theme': 'neon'}).theme, 'violeta');
    expect(UserSettings.fromMap({}).theme, 'violeta');
    expect(UserSettings.fromMap({'theme': 'coral', 'hidden_alexa_devices': ['a']}).hiddenAlexaDevices, ['a']);
  });
  test('toMap e copyWith', () {
    final s = const UserSettings().copyWith(theme: 'bronze', hiddenAlexaDevices: ['x']);
    expect(s.toMap(), {'theme': 'bronze', 'hidden_alexa_devices': ['x']});
    expect(themeIds, hasLength(10));
  });
}
