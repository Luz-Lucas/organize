import 'home_presence.dart';

const themeIds = [
  'violeta', 'safira', 'musgo', 'lunar', 'indigo',
  'grafite', 'coral', 'cobalto', 'cacto', 'bronze',
];

/// Raio padrão da casa, em metros.
const defaultHomeRadiusM = 50;

class UserSettings {
  const UserSettings({
    this.theme = 'violeta',
    this.hiddenAlexaDevices = const [],
    this.homeLat,
    this.homeLon,
    this.homeRadiusM = defaultHomeRadiusM,
    this.requireHome = true,
  });

  final String theme;
  final List<String> hiddenAlexaDevices;

  /// Casa do usuário (os dois nulos = não definida).
  final double? homeLat;
  final double? homeLon;
  final int homeRadiusM;

  /// Só toca o despertar quando o usuário está em casa (vale só com a casa definida).
  final bool requireHome;

  bool get hasHome => homeLat != null && homeLon != null;

  GeoPoint? get home => hasHome ? GeoPoint(homeLat!, homeLon!) : null;

  factory UserSettings.fromMap(Map<String, dynamic> m) {
    final theme = m['theme'];
    final lat = m['home_lat'];
    final lon = m['home_lon'];
    final hasHome = lat is num && lon is num;
    final radius = m['home_radius_m'];
    final require = m['require_home'];
    return UserSettings(
      theme: theme is String && themeIds.contains(theme) ? theme : 'violeta',
      hiddenAlexaDevices: ((m['hidden_alexa_devices'] as List?) ?? const []).cast<String>(),
      homeLat: hasHome ? lat.toDouble() : null,
      homeLon: hasHome ? lon.toDouble() : null,
      homeRadiusM: radius is num ? radius.toInt() : defaultHomeRadiusM,
      requireHome: require is bool ? require : true,
    );
  }

  Map<String, dynamic> toMap() => {
        'theme': theme,
        'hidden_alexa_devices': hiddenAlexaDevices,
        'home_lat': homeLat,
        'home_lon': homeLon,
        'home_radius_m': homeRadiusM,
        'require_home': requireHome,
      };

  UserSettings copyWith({
    String? theme,
    List<String>? hiddenAlexaDevices,
    double? homeLat,
    double? homeLon,
    bool clearHome = false,
    int? homeRadiusM,
    bool? requireHome,
  }) =>
      UserSettings(
        theme: theme ?? this.theme,
        hiddenAlexaDevices: hiddenAlexaDevices ?? this.hiddenAlexaDevices,
        homeLat: clearHome ? null : (homeLat ?? this.homeLat),
        homeLon: clearHome ? null : (homeLon ?? this.homeLon),
        homeRadiusM: homeRadiusM ?? this.homeRadiusM,
        requireHome: requireHome ?? this.requireHome,
      );
}
