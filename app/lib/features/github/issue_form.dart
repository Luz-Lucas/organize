import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/github_repository.dart';
import '../../data/repository.dart';
import '../../domain/github.dart';
import '../../ui/org_theme.dart';

/// Texto mostrado quando o servidor ainda não tem o token do GitHub.
const githubNotConfiguredText =
    'GitHub não configurado. Crie um token fine-grained (Issues: leitura e escrita) e grave '
    'GITHUB_TOKEN e GITHUB_ALLOWED_USER_ID nos segredos da função github '
    '(passo a passo em supabase/functions/GITHUB_SETUP.md).';

/// Repositório efetivo: o escolhido, se ainda existir na lista; senão o primeiro.
String? effectiveGithubRepo(List<GithubRepo> repos, String? selected) {
  if (repos.isEmpty) return null;
  return repos.any((r) => r.fullName == selected) ? selected : repos.first.fullName;
}

/// Resultado de [showIssueForm]: a issue criada e o repositório onde ela foi parar.
typedef CreatedIssue = ({String repo, GithubCreatedIssue issue});

/// Formulário "Nova issue": folha de baixo no celular (< 720 dp), diálogo no
/// computador. Devolve a issue criada, ou null se cancelado.
Future<CreatedIssue?> showIssueForm(
  BuildContext context, {
  String initialTitle = '',
  String initialBody = '',
}) {
  if (MediaQuery.sizeOf(context).width >= 720) {
    return showDialog<CreatedIssue>(
      context: context,
      builder: (_) => IssueForm(initialTitle: initialTitle, initialBody: initialBody),
    );
  }
  return showModalBottomSheet<CreatedIssue>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => IssueForm(initialTitle: initialTitle, initialBody: initialBody, sheet: true),
  );
}

class IssueForm extends ConsumerStatefulWidget {
  const IssueForm({super.key, this.initialTitle = '', this.initialBody = '', this.sheet = false});

  final String initialTitle;
  final String initialBody;
  final bool sheet;

  @override
  ConsumerState<IssueForm> createState() => _IssueFormState();
}

class _IssueFormState extends ConsumerState<IssueForm> {
  late final _title = TextEditingController(text: widget.initialTitle);
  late final _body = TextEditingController(text: widget.initialBody);
  String? _repo;
  final _labels = <String>{};
  bool _busy = false;
  String? _titleError;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _create(String repo) async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = 'Informe o título.');
      return;
    }
    setState(() {
      _busy = true;
      _titleError = null;
      _error = null;
    });
    try {
      final created = await ref.read(githubRepositoryProvider).createIssue(
            repo,
            title: title,
            body: _body.text.trim(),
            labels: _labels.toList(),
          );
      if (!mounted) return;
      ref.read(selectedGithubRepoProvider.notifier).select(repo);
      Navigator.of(context).pop((repo: repo, issue: created));
    } on RepositoryException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is GithubNotConfigured ? githubNotConfiguredText : 'Não foi possível criar a issue. ${e.message}';
      });
    }
  }

  Widget _content(BuildContext context, List<GithubRepo> repos) {
    final repo = effectiveGithubRepo(repos, _repo ?? ref.read(selectedGithubRepoProvider))!;
    final labels = ref.watch(githubLabelsProvider(repo)).value ?? const <String>[];
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (repos.length > 1) ...[
          DropdownButtonFormField<String>(
            key: const Key('github-form-repo'),
            initialValue: repo,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Repositório'),
            items: [for (final r in repos) DropdownMenuItem(value: r.fullName, child: Text(r.fullName, overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setState(() {
              _repo = v;
              _labels.clear();
            }),
          ),
          const SizedBox(height: 12),
        ] else ...[
          Text(repo, style: theme.textTheme.labelLarge?.copyWith(color: context.org.inkMuted)),
          const SizedBox(height: 8),
        ],
        TextField(
          key: const Key('github-issue-title'),
          controller: _title,
          autofocus: widget.initialTitle.isEmpty,
          textCapitalization: TextCapitalization.sentences,
          inputFormatters: [LengthLimitingTextInputFormatter(256)],
          decoration: InputDecoration(labelText: 'Título', errorText: _titleError),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('github-issue-body'),
          controller: _body,
          minLines: 3,
          maxLines: 8,
          textCapitalization: TextCapitalization.sentences,
          inputFormatters: [LengthLimitingTextInputFormatter(65536)],
          decoration: const InputDecoration(labelText: 'Descrição'),
        ),
        if (labels.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Rótulos', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final l in labels)
                FilterChip(
                  key: Key('github-label-$l'),
                  label: Text(l),
                  selected: _labels.contains(l),
                  onSelected: (on) => setState(() => on ? _labels.add(l) : _labels.remove(l)),
                ),
            ],
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, key: const Key('github-form-error'), style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          children: [
            TextButton(
              key: const Key('github-issue-cancel'),
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              key: const Key('github-issue-create'),
              onPressed: _busy ? null : () => _create(repo),
              child: Text(_busy ? 'Criando…' : 'Criar issue'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _wrapped(BuildContext context) {
    final repos = ref.watch(githubReposProvider);
    final body = repos.when(
      loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          e is GithubNotConfigured ? githubNotConfiguredText : 'Não foi possível carregar os repositórios.',
          key: const Key('github-form-error'),
        ),
      ),
      data: (list) => list.isEmpty
          ? const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('Nenhum repositório disponível.'))
          : _content(context, list),
    );
    return body;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sheet) {
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          key: const Key('github-form'),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Nova issue', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              _wrapped(context),
            ],
          ),
        ),
      );
    }
    return AlertDialog(
      key: const Key('github-form'),
      title: const Text('Nova issue'),
      content: SizedBox(width: 440, child: SingleChildScrollView(child: _wrapped(context))),
    );
  }
}
