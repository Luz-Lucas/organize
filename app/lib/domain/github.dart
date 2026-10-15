/// Estado de uma issue (os mesmos nomes que a Edge Function `github` usa).
enum IssueState { open, closed }

class GithubRepo {
  const GithubRepo({required this.fullName, this.private = false});

  factory GithubRepo.fromMap(Map<String, dynamic> m) =>
      GithubRepo(fullName: m['fullName'] as String, private: m['private'] == true);

  /// `dono/repositório`.
  final String fullName;
  final bool private;
}

class GithubIssue {
  const GithubIssue({
    required this.number,
    required this.title,
    required this.createdAt,
    this.state = IssueState.open,
    this.labels = const [],
    this.url = '',
    this.comments = 0,
  });

  factory GithubIssue.fromMap(Map<String, dynamic> m) => GithubIssue(
        number: (m['number'] as num).toInt(),
        title: (m['title'] as String?) ?? '',
        state: m['state'] == 'closed' ? IssueState.closed : IssueState.open,
        labels: [for (final l in (m['labels'] as List<dynamic>?) ?? const []) '$l'],
        createdAt: DateTime.tryParse('${m['createdAt']}')?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0),
        url: (m['url'] as String?) ?? '',
        comments: (m['comments'] as num?)?.toInt() ?? 0,
      );

  final int number;
  final String title;
  final IssueState state;
  final List<String> labels;
  final DateTime createdAt;
  final String url;
  final int comments;

  bool get isOpen => state == IssueState.open;
}

/// Issue recém-criada: número e endereço no GitHub.
class GithubCreatedIssue {
  const GithubCreatedIssue({required this.number, required this.url});

  final int number;
  final String url;
}

/// "agora", "há 5 min", "há 3 h", "há 2 d", "há 3 meses", "há 2 anos".
String issueAgoLabel(DateTime createdAt, DateTime now) {
  final d = now.difference(createdAt);
  if (d.inMinutes < 1) return 'agora';
  if (d.inMinutes < 60) return 'há ${d.inMinutes} min';
  if (d.inHours < 24) return 'há ${d.inHours} h';
  if (d.inDays < 30) return 'há ${d.inDays} d';
  if (d.inDays < 365) {
    final m = d.inDays ~/ 30;
    return 'há $m ${m == 1 ? 'mês' : 'meses'}';
  }
  final y = d.inDays ~/ 365;
  return 'há $y ${y == 1 ? 'ano' : 'anos'}';
}
