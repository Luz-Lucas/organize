import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/github.dart';
import 'github_repository.dart';
import 'repository.dart';

/// Chama a Edge Function `github` (JWT do usuário; o token do GitHub fica no servidor).
class SupabaseGithubRepository implements GithubRepository {
  SupabaseGithubRepository(this._db);

  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on FunctionException catch (e) {
      final detail = e.details;
      final message = detail is Map && detail['error'] is String ? detail['error'] as String : null;
      if (e.status == 500 && message == 'GitHub não configurado') throw const GithubNotConfigured();
      throw RepositoryException(message ?? 'Falha ao chamar o servidor (${e.status}).');
    } on RepositoryException {
      rethrow;
    } catch (e) {
      throw RepositoryException('Falha de conexão: $e');
    }
  }

  Future<dynamic> _call(Map<String, Object?> body) async {
    final res = await _db.functions.invoke('github', body: body);
    return res.data;
  }

  List<Map<String, dynamic>> _rows(dynamic data) {
    if (data is! List) throw const RepositoryException('Resposta inesperada do servidor.');
    return [for (final r in data) (r as Map).cast<String, dynamic>()];
  }

  @override
  Future<List<GithubRepo>> repos() => _guard(() async {
        return _rows(await _call({'action': 'repos'})).map(GithubRepo.fromMap).toList();
      });

  @override
  Future<List<GithubIssue>> issues(String repo, IssueState state) => _guard(() async {
        final data = await _call({'action': 'list', 'repo': repo, 'state': state.name});
        return _rows(data).map(GithubIssue.fromMap).toList();
      });

  @override
  Future<GithubCreatedIssue> createIssue(
    String repo, {
    required String title,
    String body = '',
    List<String> labels = const [],
  }) =>
      _guard(() async {
        final data = await _call({
          'action': 'create',
          'repo': repo,
          'title': title,
          if (body.isNotEmpty) 'body': body,
          if (labels.isNotEmpty) 'labels': labels,
        });
        if (data is! Map || data['number'] is! num || data['url'] is! String) {
          throw const RepositoryException('Resposta inesperada do servidor.');
        }
        return GithubCreatedIssue(number: (data['number'] as num).toInt(), url: data['url'] as String);
      });

  @override
  Future<void> setState(String repo, int number, IssueState state) => _guard(() async {
        await _call({'action': 'set_state', 'repo': repo, 'number': number, 'state': state.name});
      });

  @override
  Future<void> comment(String repo, int number, String body) => _guard(() async {
        await _call({'action': 'comment', 'repo': repo, 'number': number, 'body': body});
      });

  @override
  Future<List<String>> labels(String repo) => _guard(() async {
        final data = await _call({'action': 'labels', 'repo': repo});
        if (data is! List) throw const RepositoryException('Resposta inesperada do servidor.');
        return [for (final l in data) '$l'];
      });
}
