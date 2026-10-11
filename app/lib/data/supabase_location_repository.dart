import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/json.dart';
import '../location/location_service.dart';
import 'location_repository.dart';
import 'repository.dart';

/// Última localização do usuário em `user_locations` (uma linha por usuário).
class SupabaseLocationRepository implements LocationRepository {
  SupabaseLocationRepository(this._db, {String Function()? userId}) : _userIdOverride = userId;

  final SupabaseClient _db;
  final String Function()? _userIdOverride;

  String get _userId => _userIdOverride != null ? _userIdOverride() : _db.auth.currentUser!.id;

  @override
  Stream<LocationReport?> watchLocation() => _db
      .from('user_locations')
      .stream(primaryKey: ['user_id']).map((rows) => rows.isEmpty ? null : _fromRow(rows.first));

  static LocationReport? _fromRow(Map<String, dynamic> row) {
    final lat = row['lat'];
    final lon = row['lon'];
    final at = row['reported_at'];
    if (lat is! num || lon is! num || at is! String) return null;
    final acc = row['accuracy_m'];
    return LocationReport(
      fix: GeoFix(lat: lat.toDouble(), lon: lon.toDouble(), accuracyM: acc is num ? acc.toDouble() : null),
      reportedAt: parseDate(at)!,
    );
  }

  /// Grava (substitui) a última localização. O horário [at] é ignorado de propósito:
  /// o servidor carimba `reported_at` sozinho (relógio errado do celular não vale).
  @override
  Future<void> report(GeoFix fix, DateTime at) async {
    try {
      await _db.from('user_locations').upsert({
        'user_id': _userId,
        'lat': fix.lat,
        'lon': fix.lon,
        'accuracy_m': fix.accuracyM,
      });
    } on PostgrestException catch (e) {
      throw RepositoryException(e.message);
    } on RepositoryException {
      rethrow;
    } catch (e) {
      throw RepositoryException('Falha de conexão: $e');
    }
  }
}
