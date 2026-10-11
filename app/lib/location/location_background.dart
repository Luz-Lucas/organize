import 'package:supabase_flutter/supabase_flutter.dart';

import 'geolocator_location_service.dart';
import 'location_service.dart';
import 'report_policy.dart';

/// Nome da tarefa periódica do workmanager (roteada em `callbackDispatcher`).
const locationReportTask = 'locationReport';
const locationReportUniqueName = 'location-report';

/// Frequência mínima permitida pelo Android para trabalho periódico.
const locationReportFrequency = Duration(minutes: 15);

/// Tempo máximo para obter a posição em segundo plano.
const locationReportFixTimeout = Duration(seconds: 30);

/// Acesso aos dados do usuário no segundo plano (injetável nos testes).
abstract interface class LocationBackendSource {
  bool get hasSession;

  /// Casa e "só em casa" gravados em `user_settings`.
  Future<HomeReportConfig?> readConfig();

  /// Substitui a última localização (o servidor carimba `reported_at`).
  Future<void> upsertLocation(GeoFix fix);
}

class SupabaseLocationBackendSource implements LocationBackendSource {
  SupabaseLocationBackendSource(this._db);

  final SupabaseClient _db;

  @override
  bool get hasSession => _db.auth.currentSession != null;

  @override
  Future<HomeReportConfig?> readConfig() async {
    final row = await _db.from('user_settings').select('home_lat, home_lon, require_home').maybeSingle();
    if (row == null) return null;
    final lat = row['home_lat'];
    final lon = row['home_lon'];
    final require = row['require_home'];
    return HomeReportConfig(
      homeLat: lat is num && lon is num ? lat.toDouble() : null,
      homeLon: lat is num && lon is num ? lon.toDouble() : null,
      requireHome: require is bool ? require : true,
    );
  }

  @override
  Future<void> upsertLocation(GeoFix fix) async {
    await _db.from('user_locations').upsert({
      'user_id': _db.auth.currentUser!.id,
      'lat': fix.lat,
      'lon': fix.lon,
      'accuracy_m': fix.accuracyM,
    });
  }
}

/// Uma rodada de relatório em segundo plano. Só faz algo com sessão, casa
/// definida, `require_home` ligado e permissão "o tempo todo". Devolve se
/// gravou; toda falha é engolida (nada de coordenadas em logs).
Future<bool> reportLocationInBackground({
  required LocationBackendSource source,
  required LocationService service,
  Duration timeout = locationReportFixTimeout,
}) async {
  try {
    if (!source.hasSession) return false;
    final config = await source.readConfig();
    if (!shouldReportConfig(config)) return false;
    if (!shouldReportInBackground(config, await service.permission())) return false;
    final fix = await service.currentFix(timeout: timeout);
    if (fix == null) return false;
    await source.upsertLocation(fix);
    return true;
  } catch (_) {
    return false;
  }
}

/// Ponto de entrada da tarefa `locationReport` (cliente já inicializado).
Future<bool> runLocationReportTask(SupabaseClient? client) {
  if (client == null) return Future.value(false);
  return reportLocationInBackground(
    source: SupabaseLocationBackendSource(client),
    service: const GeolocatorLocationService(),
  );
}
