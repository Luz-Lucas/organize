import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/github.dart';
import 'repository.dart';

/// Issues do GitHub, sempre pela Edge Function `github` (o token nunca chega ao app).
abstract interface class GithubRepository {
  /// Repositórios que o app pode usar.
  Future<List<GithubRepo>> repos();

  /// As 30 issues mais recentes do [repo] no [state] (pull requests ficam de fora).
  Future<List<GithubIssue>> issues(String repo, IssueState state);

  Future<GithubCreatedIssue> createIssue(
    String repo, {
    required String title,
    String body = '',
    List<String> labels = const [],
  });

  Future<void> setState(String repo, int number, IssueState state);

  Future<void> comment(String repo, int number, String body);

  /// Rótulos existentes no [repo].
  Future<List<String>> labels(String repo);
}

/// O servidor ainda não tem `GITHUB_TOKEN`/`GITHUB_ALLOWED_USER_ID`.
class GithubNotConfigured extends RepositoryException {
  const GithubNotConfigured() : super('GitHub não configurado');
}

final githubRepositoryProvider = Provider<GithubRepository>(
  (ref) => throw UnimplementedError('githubRepositoryProvider precisa de override'),
);

/// Repositório escolhido na tela GitHub (lembrado enquanto o app está aberto).
class SelectedGithubRepo extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? fullName) => state = fullName;
}

final selectedGithubRepoProvider = NotifierProvider<SelectedGithubRepo, String?>(SelectedGithubRepo.new);

// autoDispose: cada visita à tela relê o servidor e nada vaza entre contas.
final githubReposProvider =
    FutureProvider.autoDispose<List<GithubRepo>>((ref) => ref.watch(githubRepositoryProvider).repos());

final githubIssuesProvider = FutureProvider.autoDispose.family<List<GithubIssue>, ({String repo, IssueState state})>(
  (ref, q) => ref.watch(githubRepositoryProvider).issues(q.repo, q.state),
);

final githubLabelsProvider = FutureProvider.autoDispose.family<List<String>, String>(
  (ref, repo) => ref.watch(githubRepositoryProvider).labels(repo),
);
