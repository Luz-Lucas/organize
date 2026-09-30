import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/alexa.dart';
import 'alexa_repository.dart';
import 'repository.dart';

class SupabaseAlexaRepository implements AlexaRepository {
  SupabaseAlexaRepository(this._db);

  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on PostgrestException catch (e) {
      throw RepositoryException(e.message, duplicate: e.code == '23505');
    } on RepositoryException {
      rethrow;
    } catch (e) {
      throw RepositoryException('Falha de conexão: $e');
    }
  }

  @override
  Stream<BridgeStatus?> watchStatus() => _db
      .from('alexa_bridge_status')
      .stream(primaryKey: ['user_id'])
      .map((rows) => rows.isEmpty ? null : BridgeStatus.fromMap(rows.first));

  @override
  Stream<List<AlexaDevice>> watchDevices() => _db
      .from('alexa_devices')
      .stream(primaryKey: ['user_id', 'id'])
      .order('name', ascending: true)
      .map((rows) => rows.map(AlexaDevice.fromMap).toList());

  @override
  Stream<List<AlexaRoutine>> watchRoutines() => _db
      .from('alexa_routines')
      .stream(primaryKey: ['user_id', 'id'])
      .order('name', ascending: true)
      .map((rows) => rows.map(AlexaRoutine.fromMap).toList());

  @override
  Stream<List<WakePlan>> watchWakePlans() => _db
      .from('wake_plans')
      .stream(primaryKey: ['id'])
      .order('time', ascending: true)
      .map((rows) => rows.map(WakePlan.fromMap).toList());

  @override
  Future<void> upsertWakePlan(WakePlan plan) =>
      _guard(() async => await _db.from('wake_plans').upsert(plan.toMap()));

  @override
  Future<void> deleteWakePlan(String id) =>
      _guard(() async => await _db.from('wake_plans').delete().eq('id', id));

  @override
  Future<String> sendCommand(String kind, Map<String, Object?> payload) => _guard(() async {
        final row = await _db
            .from('alexa_commands')
            .insert({'kind': kind, 'payload': payload})
            .select('id')
            .single();
        return row['id'] as String;
      });

  @override
  Stream<AlexaCommand> watchCommand(String id) => _db
      .from('alexa_commands')
      .stream(primaryKey: ['id'])
      .eq('id', id)
      .where((rows) => rows.isNotEmpty)
      .map((rows) => AlexaCommand.fromMap(rows.first));
}
