import '../domain/user_settings.dart';
import 'location_service.dart';

/// Intervalo mínimo entre dois relatórios com o app aberto.
const foregroundReportMinInterval = Duration(minutes: 2);

/// O que importa dos ajustes para decidir se o celular deve reportar a posição.
class HomeReportConfig {
  const HomeReportConfig({this.homeLat, this.homeLon, this.requireHome = true});

  factory HomeReportConfig.fromSettings(UserSettings s) =>
      HomeReportConfig(homeLat: s.homeLat, homeLon: s.homeLon, requireHome: s.requireHome);

  final double? homeLat;
  final double? homeLon;
  final bool requireHome;

  bool get hasHome => homeLat != null && homeLon != null;

  @override
  bool operator ==(Object other) =>
      other is HomeReportConfig &&
      other.homeLat == homeLat &&
      other.homeLon == homeLon &&
      other.requireHome == requireHome;

  @override
  int get hashCode => Object.hash(homeLat, homeLon, requireHome);
}

/// Só vale reportar quando há casa definida e "só tocar em casa" está ligado.
bool shouldReportConfig(HomeReportConfig? config) =>
    config != null && config.hasHome && config.requireHome;

/// Com o app aberto basta "enquanto em uso" (ou "o tempo todo").
bool shouldReportInForeground(HomeReportConfig? config, LocationPermissionLevel permission) =>
    shouldReportConfig(config) &&
    (permission == LocationPermissionLevel.whileInUse ||
        permission == LocationPermissionLevel.always);

/// Em segundo plano só com "Permitir o tempo todo".
bool shouldReportInBackground(HomeReportConfig? config, LocationPermissionLevel permission) =>
    shouldReportConfig(config) && permission == LocationPermissionLevel.always;
