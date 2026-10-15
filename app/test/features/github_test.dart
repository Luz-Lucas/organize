import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_github_repository.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/github.dart';
import 'package:organizacional/domain/task_item.dart';

import '../helpers.dart';

const _phone = Size(360, 800);

MemoryGithubRepository _repo({List<GithubIssue>? issues, bool two = false}) => MemoryGithubRepository(
      repos: [
        const GithubRepo(fullName: 'luz/app', private: true),
        if (two) const GithubRepo(fullName: 'luz/outro'),
      ],
      labels: const {
        'luz/app': ['bug', 'ideia'],
        'luz/outro': ['docs'],
      },
      issues: issues ?? const [],
      now: () => defaultNow,
    );

GithubIssue _issue(int n, String title, {IssueState state = IssueState.open, List<String> labels = const [], int comments = 0}) =>
    GithubIssue(
      number: n,
      title: title,
      state: state,
      labels: labels,
      comments: comments,
      createdAt: defaultNow.subtract(const Duration(days: 2)),
      url: 'https://github.com/luz/app/issues/$n',
    );

Future<void> _open(WidgetTester tester, MemoryGithubRepository gh, {Size size = _phone, Future<bool> Function(Uri)? openLink}) =>
    pumpApp(tester, MemoryRepository(), location: '/github', githubRepo: gh, size: size, openLink: openLink);

void main() {
  testWidgets('Mais tem o item GitHub que abre a tela e volta para Mais', (tester) async {
    await pumpApp(tester, MemoryRepository(), location: '/mais', githubRepo: _repo(), size: _phone);
    expect(find.byKey(const ValueKey('more-/github')), findsOneWidget);
    expect(find.text('GitHub'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('more-/github')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('github-new')), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('more-/github')), findsOneWidget);
  });

  testWidgets('lista as issues abertas com número, título, rótulos, idade e comentários', (tester) async {
    final gh = _repo(issues: [
      _issue(1, 'Corrigir login', labels: ['bug'], comments: 3),
      _issue(2, 'Tema escuro'),
      _issue(3, 'Já resolvida', state: IssueState.closed),
    ]);
    await _open(tester, gh);
    expect(find.byKey(const Key('github-issue-1')), findsOneWidget);
    expect(find.byKey(const Key('github-issue-2')), findsOneWidget);
    expect(find.byKey(const Key('github-issue-3')), findsNothing);
    expect(find.textContaining('#1'), findsOneWidget);
    expect(find.text('Corrigir login'), findsOneWidget);
    expect(find.text('bug'), findsOneWidget);
    expect(find.textContaining('há 2 d'), findsWidgets);
    expect(find.text('3'), findsOneWidget); // comentários
    expect(tester.takeException(), isNull);
  });

  testWidgets('aba Fechadas mostra só as fechadas', (tester) async {
    final gh = _repo(issues: [_issue(1, 'Aberta'), _issue(3, 'Já resolvida', state: IssueState.closed)]);
    await _open(tester, gh);
    await tester.tap(find.byKey(const Key('github-tab-closed')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('github-issue-3')), findsOneWidget);
    expect(find.byKey(const Key('github-issue-1')), findsNothing);
  });

  testWidgets('sem issues mostra o estado vazio', (tester) async {
    await _open(tester, _repo());
    expect(find.textContaining('Nenhuma issue'), findsOneWidget);
  });

  testWidgets('trocar de repositório recarrega a lista', (tester) async {
    final gh = _repo(two: true, issues: [_issue(1, 'Do app')]);
    await _open(tester, gh);
    expect(find.text('Do app'), findsOneWidget);
    await tester.tap(find.byKey(const Key('github-repo')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('luz/outro').last);
    await tester.pumpAndSettle();
    expect(find.text('Do app'), findsNothing);
    expect(find.textContaining('Nenhuma issue'), findsOneWidget);
  });

  testWidgets('puxar para atualizar relê o servidor', (tester) async {
    final gh = _repo(issues: [_issue(1, 'Antiga')]);
    await _open(tester, gh);
    await gh.createIssue('luz/app', title: 'Criada de fora');
    expect(find.text('Criada de fora'), findsNothing);
    await tester.fling(find.byKey(const Key('github-issue-1')), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Criada de fora'), findsOneWidget);
  });

  testWidgets('GitHub não configurado explica o passo do token', (tester) async {
    final gh = _repo()..notConfigured = true;
    await _open(tester, gh);
    expect(find.byKey(const Key('github-not-configured')), findsOneWidget);
    expect(find.textContaining('GITHUB_TOKEN'), findsOneWidget);
    expect(find.byKey(const Key('github-new')), findsNothing);
  });

  testWidgets('falha de rede mostra erro e "Tentar de novo" recarrega', (tester) async {
    final gh = _repo(issues: [_issue(1, 'Volta')])..failActions = true;
    await _open(tester, gh);
    expect(find.byKey(const Key('github-error')), findsOneWidget);
    gh.failActions = false;
    await tester.tap(find.byKey(const Key('github-retry')));
    await tester.pumpAndSettle();
    expect(find.text('Volta'), findsOneWidget);
  });

  group('detalhes', () {
    testWidgets('mostra a issue e abre no GitHub pelo linkOpener', (tester) async {
      final opened = <Uri>[];
      final gh = _repo(issues: [_issue(1, 'Corrigir login', labels: ['bug'])]);
      await _open(tester, gh, openLink: (u) async {
        opened.add(u);
        return true;
      });
      await tester.tap(find.byKey(const Key('github-issue-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('github-detail')), findsOneWidget);
      await tester.tap(find.byKey(const Key('github-open')));
      await tester.pumpAndSettle();
      expect(opened.single.toString(), 'https://github.com/luz/app/issues/1');
    });

    testWidgets('Fechar move a issue para Fechadas e Reabrir devolve', (tester) async {
      final gh = _repo(issues: [_issue(1, 'Corrigir login')]);
      await _open(tester, gh);
      await tester.tap(find.byKey(const Key('github-issue-1')));
      await tester.pumpAndSettle();
      expect(find.text('Fechar issue'), findsOneWidget);
      await tester.tap(find.byKey(const Key('github-toggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('github-detail')), findsNothing);
      expect(find.byKey(const Key('github-issue-1')), findsNothing);
      expect((await gh.issues('luz/app', IssueState.closed)).single.number, 1);

      await tester.tap(find.byKey(const Key('github-tab-closed')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('github-issue-1')));
      await tester.pumpAndSettle();
      expect(find.text('Reabrir issue'), findsOneWidget);
      await tester.tap(find.byKey(const Key('github-toggle')));
      await tester.pumpAndSettle();
      expect((await gh.issues('luz/app', IssueState.open)).single.number, 1);
    });

    testWidgets('Comentar envia o texto e não aceita comentário em branco', (tester) async {
      final gh = _repo(issues: [_issue(1, 'Corrigir login')]);
      await _open(tester, gh);
      await tester.tap(find.byKey(const Key('github-issue-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('github-comment')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('github-comment-field')), '   ');
      await tester.tap(find.byKey(const Key('github-comment-send')));
      await tester.pumpAndSettle();
      expect(gh.comments, isEmpty);
      await tester.enterText(find.byKey(const Key('github-comment-field')), 'Reproduzi aqui.');
      await tester.tap(find.byKey(const Key('github-comment-send')));
      await tester.pumpAndSettle();
      expect(gh.comments['luz/app#1'], ['Reproduzi aqui.']);
      expect(find.byKey(const Key('github-detail')), findsNothing);
      expect(find.text('1'), findsOneWidget); // contador de comentários atualizado
    });

    testWidgets('falha ao fechar mantém a folha e avisa', (tester) async {
      final gh = _repo(issues: [_issue(1, 'Corrigir login')]);
      await _open(tester, gh);
      await tester.tap(find.byKey(const Key('github-issue-1')));
      await tester.pumpAndSettle();
      gh.failActions = true;
      await tester.tap(find.byKey(const Key('github-toggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('github-detail')), findsOneWidget);
      expect(find.text('Não foi possível alterar a issue.'), findsOneWidget);
    });
  });

  group('nova issue', () {
    testWidgets('título obrigatório; cria com descrição e rótulos escolhidos e atualiza a lista', (tester) async {
      final gh = _repo();
      await _open(tester, gh);
      await tester.tap(find.byKey(const Key('github-new')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('github-form')), findsOneWidget);

      await tester.tap(find.byKey(const Key('github-issue-create')));
      await tester.pumpAndSettle();
      expect(gh.created, isEmpty);
      expect(find.text('Informe o título.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('github-issue-title')), '  Nova ideia ');
      await tester.enterText(find.byKey(const Key('github-issue-body')), 'Detalhes da ideia');
      await tester.tap(find.byKey(const Key('github-label-ideia')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('github-issue-create')));
      await tester.pumpAndSettle();

      final c = gh.created.single;
      expect([c.$1, c.$2, c.$3, ...c.$4], ['luz/app', 'Nova ideia', 'Detalhes da ideia', 'ideia']);
      expect(find.byKey(const Key('github-form')), findsNothing);
      expect(find.text('Nova ideia'), findsOneWidget); // já na lista
      expect(find.textContaining('Issue #1 criada'), findsOneWidget);
    });

    testWidgets('falha mantém o formulário com o que foi digitado', (tester) async {
      final gh = _repo();
      await _open(tester, gh);
      await tester.tap(find.byKey(const Key('github-new')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('github-issue-title')), 'Vai falhar');
      gh.failActions = true;
      await tester.tap(find.byKey(const Key('github-issue-create')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('github-form')), findsOneWidget);
      expect(find.text('Vai falhar'), findsOneWidget);
      expect(find.textContaining('Não foi possível criar a issue'), findsOneWidget);
      gh.failActions = false;
      await tester.tap(find.byKey(const Key('github-issue-create')));
      await tester.pumpAndSettle();
      expect(gh.created.single.$2, 'Vai falhar');
    });

    testWidgets('no computador o formulário é um diálogo e cria igual', (tester) async {
      final gh = _repo(two: true);
      await _open(tester, gh, size: const Size(1000, 800));
      await tester.tap(find.byKey(const Key('github-new')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.byKey(const Key('github-form-repo')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('luz/outro').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('github-issue-title')), 'No outro');
      await tester.tap(find.byKey(const Key('github-label-docs')));
      await tester.tap(find.byKey(const Key('github-issue-create')));
      await tester.pumpAndSettle();
      expect(gh.created.single.$1, 'luz/outro');
      expect(gh.created.single.$4, ['docs']);
    });

    testWidgets('formulário a 360 dp com fonte 1.3x não estoura', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _open(tester, _repo(two: true, issues: [_issue(1, 'Um título razoavelmente comprido para quebrar linha', labels: ['bug', 'ideia'], comments: 12)]));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('github-new')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('atalho na tarefa', () {
    Future<void> openTask(WidgetTester tester, MemoryRepository tasks, MemoryGithubRepository gh) async {
      await pumpApp(tester, tasks, location: '/tarefas', githubRepo: gh, size: _phone);
      await tester.tap(find.byKey(const ValueKey('task-card-a')));
      await tester.pumpAndSettle();
    }

    testWidgets('abre o formulário preenchido e, ao criar, anexa o link e salva a tarefa', (tester) async {
      final tasks = MemoryRepository();
      await tasks.upsertTask(const TaskItem(id: 'a', title: 'Corrigir login', description: 'Falha ao entrar'));
      final gh = _repo();
      await openTask(tester, tasks, gh);

      await tester.ensureVisible(find.byKey(const Key('task-to-issue')));
      await tester.tap(find.byKey(const Key('task-to-issue')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(const Key('github-issue-title'))).controller!.text, 'Corrigir login');
      expect(tester.widget<TextField>(find.byKey(const Key('github-issue-body'))).controller!.text, 'Falha ao entrar');

      await tester.tap(find.byKey(const Key('github-issue-create')));
      await tester.pumpAndSettle();

      expect(gh.created.single.$1, 'luz/app');
      final t = (await tasks.watchTasks().first).single;
      expect(t.description, 'Falha ao entrar\n\nhttps://github.com/luz/app/issues/1');
      expect(find.byKey(const Key('task-save')), findsNothing); // editor fechou
    });

    testWidgets('cancelar o formulário não muda a tarefa', (tester) async {
      final tasks = MemoryRepository();
      await tasks.upsertTask(const TaskItem(id: 'a', title: 'Corrigir login'));
      final gh = _repo();
      await openTask(tester, tasks, gh);
      await tester.ensureVisible(find.byKey(const Key('task-to-issue')));
      await tester.tap(find.byKey(const Key('task-to-issue')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('github-issue-cancel')));
      await tester.pumpAndSettle();
      expect(gh.created, isEmpty);
      expect(find.byKey(const Key('task-save')), findsOneWidget);
      expect((await tasks.watchTasks().first).single.description, '');
    });

    testWidgets('descrição vazia fica só com o link', (tester) async {
      final tasks = MemoryRepository();
      await tasks.upsertTask(const TaskItem(id: 'a', title: 'Ideia'));
      await openTask(tester, tasks, _repo());
      await tester.ensureVisible(find.byKey(const Key('task-to-issue')));
      await tester.tap(find.byKey(const Key('task-to-issue')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('github-issue-create')));
      await tester.pumpAndSettle();
      expect((await tasks.watchTasks().first).single.description, 'https://github.com/luz/app/issues/1');
    });
  });
}
