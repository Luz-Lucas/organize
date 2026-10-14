import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:organizacional/data/github_repository.dart';
import 'package:organizacional/data/memory_github_repository.dart';
import 'package:organizacional/data/repository.dart';
import 'package:organizacional/data/supabase_github_repository.dart';
import 'package:organizacional/domain/github.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('MemoryGithubRepository', () {
    late MemoryGithubRepository repo;
    setUp(() {
      repo = MemoryGithubRepository(
        repos: const [GithubRepo(fullName: 'luz/app', private: true)],
        labels: const {'luz/app': ['bug', 'ideia']},
        now: () => DateTime(2026, 10, 12, 12),
      );
    });

    test('cria issue com número sequencial e lista só as do estado pedido', () async {
      final a = await repo.createIssue('luz/app', title: 'Primeira', labels: const ['bug']);
      final b = await repo.createIssue('luz/app', title: 'Segunda', body: 'detalhe');
      expect(a.number, 1);
      expect(b.number, 2);
      expect(b.url, 'https://github.com/luz/app/issues/2');
      final open = await repo.issues('luz/app', IssueState.open);
      expect(open.map((i) => i.title), ['Segunda', 'Primeira']); // mais nova primeiro
      expect(open.last.labels, ['bug']);
      expect(await repo.issues('luz/app', IssueState.closed), isEmpty);
    });

    test('setState move entre abertas e fechadas; comment soma ao contador', () async {
      await repo.createIssue('luz/app', title: 'x');
      await repo.setState('luz/app', 1, IssueState.closed);
      expect(await repo.issues('luz/app', IssueState.open), isEmpty);
      expect((await repo.issues('luz/app', IssueState.closed)).single.number, 1);
      await repo.comment('luz/app', 1, 'ok');
      expect((await repo.issues('luz/app', IssueState.closed)).single.comments, 1);
      expect(repo.comments['luz/app#1'], ['ok']);
    });

    test('repos, labels e falha simulada', () async {
      expect((await repo.repos()).single.fullName, 'luz/app');
      expect(await repo.labels('luz/app'), ['bug', 'ideia']);
      expect(await repo.labels('outro/x'), isEmpty);
      repo.failActions = true;
      await expectLater(repo.issues('luz/app', IssueState.open), throwsA(isA<RepositoryException>()));
      repo.failActions = false;
      repo.notConfigured = true;
      await expectLater(repo.repos(), throwsA(isA<GithubNotConfigured>()));
    });
  });

  group('SupabaseGithubRepository', () {
    SupabaseClient client(List<Map<String, Object?>> sent, {int status = 200, String reply = '{}'}) {
      final mock = MockClient((http.Request req) async {
        sent.add({'path': req.url.path, 'body': jsonDecode(req.body)});
        return http.Response(reply, status, request: req, headers: {'content-type': 'application/json'});
      });
      return SupabaseClient('http://localhost:54321', 'anon', httpClient: mock);
    }

    test('list envia {action, repo, state} para a função github e converte as issues', () async {
      final sent = <Map<String, Object?>>[];
      final repo = SupabaseGithubRepository(client(sent, reply: jsonEncode([
        {
          'number': 8,
          'title': 'Bug',
          'state': 'open',
          'labels': ['bug'],
          'createdAt': '2026-10-02T10:00:00Z',
          'url': 'https://github.com/luz/app/issues/8',
          'comments': 2,
        }
      ])));
      final issues = await repo.issues('luz/app', IssueState.open);
      expect(sent.single['path'], '/functions/v1/github');
      expect(sent.single['body'], {'action': 'list', 'repo': 'luz/app', 'state': 'open'});
      expect(issues.single.number, 8);
      expect(issues.single.comments, 2);
    });

    test('create / set_state / comment / labels / repos montam o corpo certo', () async {
      final sent = <Map<String, Object?>>[];
      final repo = SupabaseGithubRepository(client(sent, reply: jsonEncode({'number': 12, 'url': 'https://github.com/luz/app/issues/12'})));
      final c = await repo.createIssue('luz/app', title: 'T', body: 'B', labels: const ['bug']);
      expect(c.number, 12);
      expect(c.url, 'https://github.com/luz/app/issues/12');
      expect(sent.last['body'], {'action': 'create', 'repo': 'luz/app', 'title': 'T', 'body': 'B', 'labels': ['bug']});

      await repo.createIssue('luz/app', title: 'só título');
      expect(sent.last['body'], {'action': 'create', 'repo': 'luz/app', 'title': 'só título'});

      await repo.setState('luz/app', 12, IssueState.closed);
      expect(sent.last['body'], {'action': 'set_state', 'repo': 'luz/app', 'number': 12, 'state': 'closed'});
      await repo.comment('luz/app', 12, 'oi');
      expect(sent.last['body'], {'action': 'comment', 'repo': 'luz/app', 'number': 12, 'body': 'oi'});
    });

    test('labels e repos convertem a resposta', () async {
      final sent = <Map<String, Object?>>[];
      final labels = SupabaseGithubRepository(client(sent, reply: '["bug","ideia"]'));
      expect(await labels.labels('luz/app'), ['bug', 'ideia']);
      expect(sent.last['body'], {'action': 'labels', 'repo': 'luz/app'});
      final repos = SupabaseGithubRepository(client(sent, reply: '[{"fullName":"luz/app","private":true}]'));
      expect((await repos.repos()).single.private, isTrue);
      expect(sent.last['body'], {'action': 'repos'});
    });

    test('erro da função vira RepositoryException com a mensagem em pt-BR do servidor', () async {
      final repo = SupabaseGithubRepository(client([], status: 404, reply: '{"error":"Repositório ou issue não encontrado."}'));
      await expectLater(
        repo.comment('luz/app', 1, 'x'),
        throwsA(isA<RepositoryException>().having((e) => e.message, 'message', contains('não encontrado'))),
      );
    });

    test('500 "GitHub não configurado" vira GithubNotConfigured', () async {
      final repo = SupabaseGithubRepository(client([], status: 500, reply: '{"error":"GitHub não configurado"}'));
      await expectLater(repo.repos(), throwsA(isA<GithubNotConfigured>()));
    });

    test('resposta fora do formato vira RepositoryException', () async {
      final repo = SupabaseGithubRepository(client([], reply: '"oi"'));
      await expectLater(repo.issues('luz/app', IssueState.open), throwsA(isA<RepositoryException>()));
    });
  });
}
