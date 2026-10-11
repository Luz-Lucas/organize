const themeIds = [
  'violeta', 'safira', 'musgo', 'lunar', 'indigo',
  'grafite', 'coral', 'cobalto', 'cacto', 'bronze',
];

class UserSettings {
  const UserSettings({this.theme = 'violeta', this.hiddenAlexaDevices = const []});

  final String theme;
  final List<String> hiddenAlexaDevices;

  factory UserSettings.fromMap(Map<String, dynamic> m) {
    final theme = m['theme'];
    return UserSettings(
      theme: theme is String && themeIds.contains(theme) ? theme : 'violeta',
      hiddenAlexaDevices: ((m['hidden_alexa_devices'] as List?) ?? const []).cast<String>(),
    );
  }

  Map<String, dynamic> toMap() => {'theme': theme, 'hidden_alexa_devices': hiddenAlexaDevices};

  UserSettings copyWith({String? theme, List<String>? hiddenAlexaDevices}) => UserSettings(
        theme: theme ?? this.theme,
        hiddenAlexaDevices: hiddenAlexaDevices ?? this.hiddenAlexaDevices,
      );
}
