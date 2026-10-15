import '../domain/github.dart';
import 'github_repository.dart';
import 'repository.dart';

/// Implementação em memória usada nos testes.
class MemoryGithubRepository implements GithubRepository {
  MemoryGithubRepository({
    List<GithubRepo> repos = const [],
    Map<String, List<String>> labels = const {},
    List<GithubIssue> issues = const [],
    this.issuesRepo,
    DateTime Function()? now,
  })  : _repos = List.of(repos),
        _labels = {for (final e in labels.entries) e.key: List.of(e.value)},
        _now = now ?? DateTime.now {
    if (issues.isNotEmpty) _issues[issuesRepo ?? _repos.first.fullName] = List.of(issues);
  }

  /// Repositório que recebe as [issues] iniciais (padrão: o primeiro de [repos]).
  final String? issuesRepo;

  final List<GithubRepo> _repos;
  final Map<String, List<String>> _labels;
  final Map<String, List<GithubIssue>> _issues = {};
  final DateTime Function() _now;

  bool failActions = false;
  bool notConfigured = false;

  /// Comentários enviados, por `repo#número`.
  final Map<String, List<String>> comments = {};

  /// Chamadas a [createIssue], em ordem: `(repo, title, body, labels)`.
  final List<(String, String, String, List<String>)> created = [];

  void _check() {
    if (notConfigured) throw const GithubNotConfigured();
    if (failActions) throw const RepositoryException('Sem conexão (simulado)');
  }

  @override
  Future<List<GithubRepo>> repos() async {
    _check();
    return List.of(_repos);
  }

  @override
  Future<List<GithubIssue>> issues(String repo, IssueState state) async {
    _check();
    final list = [for (final i in _issues[repo] ?? const <GithubIssue>[]) if (i.state == state) i];
    list.sort((a, b) => b.number.compareTo(a.number));
    return list;
  }

  @override
  Future<GithubCreatedIssue> createIssue(
    String repo, {
    required String title,
    String body = '',
    List<String> labels = const [],
  }) async {
    _check();
    final list = _issues.putIfAbsent(repo, () => []);
    final number = list.fold<int>(0, (m, i) => i.number > m ? i.number : m) + 1;
    final url = 'https://github.com/$repo/issues/$number';
    list.add(GithubIssue(number: number, title: title, createdAt: _now(), labels: List.of(labels), url: url));
    created.add((repo, title, body, List.of(labels)));
    return GithubCreatedIssue(number: number, url: url);
  }

  GithubIssue _find(String repo, int number) {
    final list = _issues[repo] ?? const <GithubIssue>[];
    return list.firstWhere((i) => i.number == number, orElse: () => throw const RepositoryException('Issue não encontrada.'));
  }

  void _replace(String repo, GithubIssue next) {
    final list = _issues[repo]!;
    list[list.indexWhere((i) => i.number == next.number)] = next;
  }

  @override
  Future<void> setState(String repo, int number, IssueState state) async {
    _check();
    final i = _find(repo, number);
    _replace(
      repo,
      GithubIssue(
        number: i.number,
        title: i.title,
        createdAt: i.createdAt,
        state: state,
        labels: i.labels,
        url: i.url,
        comments: i.comments,
      ),
    );
  }

  @override
  Future<void> comment(String repo, int number, String body) async {
    _check();
    final i = _find(repo, number);
    comments.putIfAbsent('$repo#$number', () => []).add(body);
    _replace(
      repo,
      GithubIssue(
        number: i.number,
        title: i.title,
        createdAt: i.createdAt,
        state: i.state,
        labels: i.labels,
        url: i.url,
        comments: i.comments + 1,
      ),
    );
  }

  @override
  Future<List<String>> labels(String repo) async {
    _check();
    return List.of(_labels[repo] ?? const []);
  }
}
