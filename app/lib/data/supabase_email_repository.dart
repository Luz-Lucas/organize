import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/email.dart';
import 'email_repository.dart';
import 'repository.dart';

/// Lê `email_state` e `email_items` (só o servidor escreve) e chama as funções gmail-*.
class SupabaseEmailRepository implements EmailRepository {
  SupabaseEmailRepository(this._db);

  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on FunctionException catch (e) {
      throw RepositoryException('Falha ao chamar o servidor (${e.status}).');
    } on PostgrestException catch (e) {
      throw RepositoryException(e.message);
    } on RepositoryException {
      rethrow;
    } catch (e) {
      throw RepositoryException('Falha de conexão: $e');
    }
  }

  @override
  Stream<EmailState?> watchState() => _db
      .from('email_state')
      .stream(primaryKey: ['user_id']).map((rows) => rows.isEmpty ? null : EmailState.fromMap(rows.first));

  @override
  Stream<List<EmailItem>> watchItems({int limit = 10}) => _db
      .from('email_items')
      .stream(primaryKey: ['user_id', 'gmail_id'])
      .order('received_at', ascending: false)
      .limit(limit)
      .map((rows) => [for (final r in rows) EmailItem.fromMap(r)]);

  @override
  Future<Uri> connectUrl({String? email}) => _guard(() async {
        final res = await _db.functions.invoke('gmail-connect', body: {'email': ?email});
        final url = (res.data as Map?)?['url'];
        final uri = url is String ? Uri.tryParse(url) : null;
        if (uri == null || uri.scheme != 'https') {
          throw const RepositoryException('Resposta inesperada do servidor.');
        }
        return uri;
      });

  @override
  Future<void> syncNow() => _guard(() async {
        await _db.functions.invoke('gmail-sync', body: const {});
      });

  @override
  Future<void> disconnect() => _guard(() async {
        await _db.functions.invoke('gmail-disconnect', body: const {});
      });
}
