import 'home_presence.dart';

const themeIds = [
  'violeta', 'safira', 'musgo', 'lunar', 'indigo',
  'grafite', 'coral', 'cobalto', 'cacto', 'bronze',
];

/// Raio padrão da casa, em metros.
const defaultHomeRadiusM = 50;

/// Não perturbe padrão: das 23:00 às 10:00 (minutos do dia).
const defaultDndStart = 23 * 60;
const defaultDndEnd = 10 * 60;

/// "07:05" para 425 minutos do dia.
String formatMinutesOfDay(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

/// Lê "HH:MM" ou "HH:MM:SS" (coluna `time`) em minutos do dia; inválido vira [fallback].
int _parseMinutes(Object? value, int fallback) {
  if (value is! String) return fallback;
  final m = RegExp(r'^(\d{1,2}):(\d{2})(?::\d{2})?$').firstMatch(value);
  if (m == null) return fallback;
  final h = int.parse(m[1]!), min = int.parse(m[2]!);
  return h < 24 && min < 60 ? h * 60 + min : fallback;
}

class UserSettings {
  const UserSettings({
    this.theme = 'violeta',
    this.hiddenAlexaDevices = const [],
    this.homeLat,
    this.homeLon,
    this.homeRadiusM = defaultHomeRadiusM,
    this.requireHome = true,
    this.notebookPrefs = const {},
    this.remindersPhone = true,
    this.remindersAlexa = true,
    this.reminderEcho,
    this.dndEnabled = true,
    this.dndStart = defaultDndStart,
    this.dndEnd = defaultDndEnd,
  });

  final String theme;
  final List<String> hiddenAlexaDevices;

  /// Casa do usuário (os dois nulos = não definida).
  final double? homeLat;
  final double? homeLon;
  final int homeRadiusM;

  /// Só toca o despertar quando o usuário está em casa (vale só com a casa definida).
  final bool requireHome;

  /// Favoritos do Caderno (canetas, cores, modo da barra) em JSON; `{}` = nunca
  /// personalizado. O formato é interpretado em `notebook/ui/notebook_prefs.dart`.
  final Map<String, dynamic> notebookPrefs;

  /// Lembretes de tarefas e eventos por notificação no celular.
  final bool remindersPhone;

  /// Lembretes falados no Echo escolhido ([reminderEcho]).
  final bool remindersAlexa;

  /// Id do Echo (`alexa_devices.id`) que fala os lembretes; `null` = nenhum escolhido.
  final String? reminderEcho;

  /// Não perturbe: lembretes que cairiam entre [dndStart] e [dndEnd] (minutos do
  /// dia; pode atravessar a meia-noite) esperam o fim do intervalo.
  final bool dndEnabled;
  final int dndStart;
  final int dndEnd;

  bool get hasHome => homeLat != null && homeLon != null;

  GeoPoint? get home => hasHome ? GeoPoint(homeLat!, homeLon!) : null;

  factory UserSettings.fromMap(Map<String, dynamic> m) {
    final theme = m['theme'];
    final lat = m['home_lat'];
    final lon = m['home_lon'];
    final hasHome = lat is num && lon is num;
    final radius = m['home_radius_m'];
    final require = m['require_home'];
    final prefs = m['notebook_prefs'];
    final echo = m['reminder_echo'];
    return UserSettings(
      theme: theme is String && themeIds.contains(theme) ? theme : 'violeta',
      hiddenAlexaDevices: ((m['hidden_alexa_devices'] as List?) ?? const []).cast<String>(),
      homeLat: hasHome ? lat.toDouble() : null,
      homeLon: hasHome ? lon.toDouble() : null,
      homeRadiusM: radius is num ? radius.toInt() : defaultHomeRadiusM,
      requireHome: require is bool ? require : true,
      notebookPrefs: prefs is Map ? prefs.cast<String, dynamic>() : const {},
      remindersPhone: m['reminders_phone'] is bool ? m['reminders_phone'] as bool : true,
      remindersAlexa: m['reminders_alexa'] is bool ? m['reminders_alexa'] as bool : true,
      reminderEcho: echo is String && echo.isNotEmpty ? echo : null,
      dndEnabled: m['dnd_enabled'] is bool ? m['dnd_enabled'] as bool : true,
      dndStart: _parseMinutes(m['dnd_start'], defaultDndStart),
      dndEnd: _parseMinutes(m['dnd_end'], defaultDndEnd),
    );
  }

  Map<String, dynamic> toMap() => {
        'theme': theme,
        'hidden_alexa_devices': hiddenAlexaDevices,
        'home_lat': homeLat,
        'home_lon': homeLon,
        'home_radius_m': homeRadiusM,
        'require_home': requireHome,
        'notebook_prefs': notebookPrefs,
        'reminders_phone': remindersPhone,
        'reminders_alexa': remindersAlexa,
        'reminder_echo': reminderEcho,
        'dnd_enabled': dndEnabled,
        'dnd_start': formatMinutesOfDay(dndStart),
        'dnd_end': formatMinutesOfDay(dndEnd),
      };

  UserSettings copyWith({
    String? theme,
    List<String>? hiddenAlexaDevices,
    double? homeLat,
    double? homeLon,
    bool clearHome = false,
    int? homeRadiusM,
    bool? requireHome,
    Map<String, dynamic>? notebookPrefs,
    bool? remindersPhone,
    bool? remindersAlexa,
    String? reminderEcho,
    bool clearReminderEcho = false,
    bool? dndEnabled,
    int? dndStart,
    int? dndEnd,
  }) =>
      UserSettings(
        theme: theme ?? this.theme,
        hiddenAlexaDevices: hiddenAlexaDevices ?? this.hiddenAlexaDevices,
        homeLat: clearHome ? null : (homeLat ?? this.homeLat),
        homeLon: clearHome ? null : (homeLon ?? this.homeLon),
        homeRadiusM: homeRadiusM ?? this.homeRadiusM,
        requireHome: requireHome ?? this.requireHome,
        notebookPrefs: notebookPrefs ?? this.notebookPrefs,
        remindersPhone: remindersPhone ?? this.remindersPhone,
        remindersAlexa: remindersAlexa ?? this.remindersAlexa,
        reminderEcho: clearReminderEcho ? null : (reminderEcho ?? this.reminderEcho),
        dndEnabled: dndEnabled ?? this.dndEnabled,
        dndStart: dndStart ?? this.dndStart,
        dndEnd: dndEnd ?? this.dndEnd,
      );
}
