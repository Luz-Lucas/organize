import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/domain/github.dart';

void main() {
  test('GithubRepo.fromMap', () {
    final r = GithubRepo.fromMap({'fullName': 'luz/app', 'private': true});
    expect(r.fullName, 'luz/app');
    expect(r.private, isTrue);
    expect(GithubRepo.fromMap({'fullName': 'a/b'}).private, isFalse);
  });

  test('GithubIssue.fromMap lê rótulos, estado e data', () {
    final i = GithubIssue.fromMap({
      'number': 8,
      'title': 'Bug no widget',
      'state': 'closed',
      'labels': ['bug', 'ui'],
      'createdAt': '2026-10-02T10:00:00Z',
      'url': 'https://github.com/luz/app/issues/8',
      'comments': 3,
    });
    expect(i.number, 8);
    expect(i.state, IssueState.closed);
    expect(i.labels, ['bug', 'ui']);
    expect(i.createdAt.toUtc(), DateTime.utc(2026, 10, 2, 10));
    expect(i.comments, 3);
    expect(i.isOpen, isFalse);
  });

  test('GithubIssue.fromMap tolera campos ausentes', () {
    final i = GithubIssue.fromMap({'number': 1, 'title': 'x'});
    expect(i.state, IssueState.open);
    expect(i.labels, isEmpty);
    expect(i.comments, 0);
    expect(i.url, '');
  });

  test('issueAgoLabel', () {
    final now = DateTime(2026, 10, 12, 12);
    expect(issueAgoLabel(now.subtract(const Duration(seconds: 20)), now), 'agora');
    expect(issueAgoLabel(now.subtract(const Duration(minutes: 5)), now), 'há 5 min');
    expect(issueAgoLabel(now.subtract(const Duration(hours: 3)), now), 'há 3 h');
    expect(issueAgoLabel(now.subtract(const Duration(days: 2, hours: 5)), now), 'há 2 d');
    expect(issueAgoLabel(now.subtract(const Duration(days: 45)), now), 'há 1 mês');
    expect(issueAgoLabel(now.subtract(const Duration(days: 100)), now), 'há 3 meses');
    expect(issueAgoLabel(now.subtract(const Duration(days: 800)), now), 'há 2 anos');
    expect(issueAgoLabel(now.add(const Duration(hours: 1)), now), 'agora');
  });
}
