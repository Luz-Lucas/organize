import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/github_repository.dart';
import '../../data/repository.dart';
import '../../domain/github.dart';
import '../../ui/org_theme.dart';
import '../../ui/org_widgets.dart';
import 'issue_form.dart';

/// Mais > GitHub: issues dos repositórios permitidos (lista, detalhes, criar,
/// fechar/reabrir e comentar). Tudo passa pela Edge Function `github`.
class GithubScreen extends ConsumerStatefulWidget {
  const GithubScreen({super.key});

  @override
  ConsumerState<GithubScreen> createState() => _GithubScreenState();
}

class _GithubScreenState extends ConsumerState<GithubScreen> {
  IssueState _state = IssueState.open;

  Future<void> _newIssue() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final result = await showIssueForm(context);
    if (result == null || !mounted) return;
    ref.invalidate(githubIssuesProvider);
    messenger
      ?..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text('Issue #${result.issue.number} criada.')));
  }

  @override
  Widget build(BuildContext context) {
    final repos = ref.watch(githubReposProvider);
    final ready = repos.value?.isNotEmpty ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('GitHub')),
      floatingActionButton: ready
          ? FloatingActionButton.extended(
              key: const Key('github-new'),
              onPressed: _newIssue,
              icon: const Icon(Icons.add),
              label: const Text('Nova issue'),
            )
          : null,
      body: SafeArea(
        child: repos.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _Problem(error: e, onRetry: () => ref.invalidate(githubReposProvider)),
          data: (list) => list.isEmpty
              ? const EmptyHint('Nenhum repositório disponível para o token do GitHub.')
              : _Loaded(repos: list, state: _state, onState: (s) => setState(() => _state = s)),
        ),
      ),
    );
  }
}

class _Loaded extends ConsumerWidget {
  const _Loaded({required this.repos, required this.state, required this.onState});

  final List<GithubRepo> repos;
  final IssueState state;
  final ValueChanged<IssueState> onState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = effectiveGithubRepo(repos, ref.watch(selectedGithubRepoProvider))!;
    final query = (repo: repo, state: state);
    final issues = ref.watch(githubIssuesProvider(query));
    final gutter = MediaQuery.sizeOf(context).width < 720 ? 16.0 : 24.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 8),
          child: DropdownButton<String>(
            key: const Key('github-repo'),
            value: repo,
            isExpanded: true,
            items: [
              for (final r in repos)
                DropdownMenuItem(
                  value: r.fullName,
                  child: Row(
                    children: [
                      Icon(r.private ? Icons.lock_outline : Icons.public, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(r.fullName, overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
            ],
            onChanged: (v) => ref.read(selectedGithubRepoProvider.notifier).select(v),
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: gutter),
          child: SegmentedButton<IssueState>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: IssueState.open, label: Text('Abertas', key: Key('github-tab-open'))),
              ButtonSegment(value: IssueState.closed, label: Text('Fechadas', key: Key('github-tab-closed'))),
            ],
            selected: {state},
            onSelectionChanged: (v) => onState(v.first),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: issues.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _Problem(error: e, onRetry: () => ref.invalidate(githubIssuesProvider(query))),
            data: (list) => RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(githubIssuesProvider(query));
                try {
                  await ref.read(githubIssuesProvider(query).future);
                } on RepositoryException {
                  // o erro aparece na própria lista
                }
              },
              child: list.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.all(gutter),
                      children: [
                        Text(
                          state == IssueState.open ? 'Nenhuma issue aberta.' : 'Nenhuma issue fechada.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: context.org.inkMuted),
                        ),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(gutter, 4, gutter, 96),
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _IssueTile(issue: list[i], repo: repo),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final notConfigured = error is GithubNotConfigured;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(notConfigured ? Icons.key_off_outlined : Icons.cloud_off_outlined, size: 40, color: context.org.inkMuted),
            const SizedBox(height: 12),
            Text(
              notConfigured
                  ? githubNotConfiguredText
                  : error is RepositoryException
                      ? 'Não foi possível carregar o GitHub. ${(error as RepositoryException).message}'
                      : 'Não foi possível carregar o GitHub.',
              key: Key(notConfigured ? 'github-not-configured' : 'github-error'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            OutlinedButton(key: const Key('github-retry'), onPressed: onRetry, child: const Text('Tentar de novo')),
          ],
        ),
      ),
    );
  }
}

class _IssueTile extends ConsumerWidget {
  const _IssueTile({required this.issue, required this.repo});

  final GithubIssue issue;
  final String repo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final org = context.org;
    final theme = Theme.of(context);
    final now = ref.watch(clockProvider)();
    return OrgCard(
      key: Key('github-issue-${issue.number}'),
      onTap: () => showIssueDetails(context, repo: repo, issue: issue),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              issue.isOpen ? Icons.radio_button_unchecked : Icons.check_circle_outline,
              size: 18,
              color: issue.isOpen ? org.accentText : org.inkMuted,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(issue.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  '#${issue.number} · ${issueAgoLabel(issue.createdAt, now)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: org.inkMuted),
                ),
                if (issue.labels.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 4, children: [for (final l in issue.labels) _LabelPill(l)]),
                ],
              ],
            ),
          ),
          if (issue.comments > 0) ...[
            const SizedBox(width: 8),
            Icon(Icons.chat_bubble_outline, size: 16, color: org.inkMuted),
            const SizedBox(width: 4),
            Text('${issue.comments}', style: theme.textTheme.bodySmall?.copyWith(color: org.inkMuted)),
          ],
        ],
      ),
    );
  }
}

class _LabelPill extends StatelessWidget {
  const _LabelPill(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final org = context.org;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: org.accentSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: org.accentText)),
      ),
    );
  }
}

/// Folha com os detalhes de uma issue: abrir no GitHub, fechar/reabrir e comentar.
Future<void> showIssueDetails(BuildContext context, {required String repo, required GithubIssue issue}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _IssueSheet(repo: repo, issue: issue),
    );

class _IssueSheet extends ConsumerStatefulWidget {
  const _IssueSheet({required this.repo, required this.issue});

  final String repo;
  final GithubIssue issue;

  @override
  ConsumerState<_IssueSheet> createState() => _IssueSheetState();
}

class _IssueSheetState extends ConsumerState<_IssueSheet> {
  final _comment = TextEditingController();
  bool _commenting = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() op, String failure) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await op();
      if (!mounted) return;
      ref.invalidate(githubIssuesProvider);
      Navigator.of(context).pop();
    } on RepositoryException {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = failure;
        });
      }
    }
  }

  Future<void> _open() async {
    final uri = Uri.tryParse(widget.issue.url);
    final opened = uri != null && uri.hasScheme && await ref.read(linkOpenerProvider)(uri);
    if (!opened && mounted) setState(() => _error = 'Não foi possível abrir o link.');
  }

  Future<void> _sendComment() async {
    final text = _comment.text.trim();
    if (text.isEmpty) return;
    await _run(
      () => ref.read(githubRepositoryProvider).comment(widget.repo, widget.issue.number, text),
      'Não foi possível comentar.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final issue = widget.issue;
    final org = context.org;
    final theme = Theme.of(context);
    final now = ref.watch(clockProvider)();
    final next = issue.isOpen ? IssueState.closed : IssueState.open;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        key: const Key('github-detail'),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(issue.title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '${widget.repo} #${issue.number} · ${issue.isOpen ? 'aberta' : 'fechada'} · '
              '${issueAgoLabel(issue.createdAt, now)} · ${issue.comments} ${issue.comments == 1 ? 'comentário' : 'comentários'}',
              style: theme.textTheme.bodySmall?.copyWith(color: org.inkMuted),
            ),
            if (issue.labels.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 4, children: [for (final l in issue.labels) _LabelPill(l)]),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  key: const Key('github-open'),
                  onPressed: issue.url.isEmpty ? null : _open,
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Abrir no GitHub'),
                ),
                OutlinedButton(
                  key: const Key('github-toggle'),
                  onPressed: _busy
                      ? null
                      : () => _run(
                            () => ref.read(githubRepositoryProvider).setState(widget.repo, issue.number, next),
                            'Não foi possível alterar a issue.',
                          ),
                  child: Text(issue.isOpen ? 'Fechar issue' : 'Reabrir issue'),
                ),
                if (!_commenting)
                  TextButton(
                    key: const Key('github-comment'),
                    onPressed: () => setState(() => _commenting = true),
                    child: const Text('Comentar'),
                  ),
              ],
            ),
            if (_commenting) ...[
              const SizedBox(height: 12),
              TextField(
                key: const Key('github-comment-field'),
                controller: _comment,
                autofocus: true,
                minLines: 2,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Comentário'),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  key: const Key('github-comment-send'),
                  onPressed: _busy ? null : _sendComment,
                  child: const Text('Enviar comentário'),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }
}
