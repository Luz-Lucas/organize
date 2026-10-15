import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/domain/home_presence.dart';
import 'package:organizacional/domain/user_settings.dart';

void main() {
  test('tema desconhecido ou ausente vira violeta', () {
    expect(UserSettings.fromMap({'theme': 'neon'}).theme, 'violeta');
    expect(UserSettings.fromMap({}).theme, 'violeta');
    expect(UserSettings.fromMap({'theme': 'coral', 'hidden_alexa_devices': ['a']}).hiddenAlexaDevices, ['a']);
  });
  test('toMap e copyWith', () {
    final s = const UserSettings().copyWith(theme: 'bronze', hiddenAlexaDevices: ['x']);
    expect(s.toMap(), {
      'theme': 'bronze',
      'hidden_alexa_devices': ['x'],
      'home_lat': null,
      'home_lon': null,
      'home_radius_m': 50,
      'require_home': true,
      'notebook_prefs': <String, dynamic>{},
    });
    expect(themeIds, hasLength(10));
  });

  group('minha casa', () {
    test('padrões: sem casa, raio 50 m, exigir casa ligado', () {
      const s = UserSettings();
      expect(s.hasHome, isFalse);
      expect(s.home, isNull);
      expect(s.homeRadiusM, 50);
      expect(s.requireHome, isTrue);
    });

    test('fromMap lê as colunas; ausentes ou inválidas caem nos padrões', () {
      final s = UserSettings.fromMap({
        'home_lat': -19.93,
        'home_lon': -45,
        'home_radius_m': 80,
        'require_home': false,
      });
      expect(s.home, const GeoPoint(-19.93, -45.0));
      expect(s.homeRadiusM, 80);
      expect(s.requireHome, isFalse);
      final bad = UserSettings.fromMap({'home_lat': 'x', 'home_lon': 1, 'home_radius_m': null, 'require_home': 'sim'});
      expect(bad.hasHome, isFalse); // uma coordenada sozinha não define casa
      expect(bad.homeRadiusM, 50);
      expect(bad.requireHome, isTrue);
    });

    test('ida e volta por toMap/fromMap', () {
      const s = UserSettings(homeLat: -19.93, homeLon: -43.94, homeRadiusM: 120, requireHome: false);
      final r = UserSettings.fromMap(s.toMap());
      expect([r.homeLat, r.homeLon, r.homeRadiusM, r.requireHome], [-19.93, -43.94, 120, false]);
    });

    test('copyWith define e limpa a casa', () {
      final s = const UserSettings().copyWith(homeLat: 1, homeLon: 2);
      expect(s.hasHome, isTrue);
      final cleared = s.copyWith(clearHome: true, theme: 'coral');
      expect(cleared.hasHome, isFalse);
      expect(cleared.homeLat, isNull);
      expect(cleared.theme, 'coral');
      expect(s.copyWith(requireHome: false).requireHome, isFalse);
      expect(s.copyWith(requireHome: false).homeLat, 1);
    });
  });

  group('favoritos do caderno', () {
    test('padrão é um mapa vazio; fromMap lê o objeto e ignora lixo', () {
      expect(const UserSettings().notebookPrefs, isEmpty);
      final s = UserSettings.fromMap({
        'notebook_prefs': {'v': 1, 'compact': false},
      });
      expect(s.notebookPrefs, {'v': 1, 'compact': false});
      expect(UserSettings.fromMap({'notebook_prefs': 'texto'}).notebookPrefs, isEmpty);
      expect(UserSettings.fromMap({'notebook_prefs': null}).notebookPrefs, isEmpty);
    });

    test('ida e volta por toMap/fromMap e copyWith', () {
      final s = const UserSettings().copyWith(notebookPrefs: {'v': 1}, theme: 'coral');
      expect(UserSettings.fromMap(s.toMap()).notebookPrefs, {'v': 1});
      expect(s.copyWith(theme: 'musgo').notebookPrefs, {'v': 1});
    });
  });
}
