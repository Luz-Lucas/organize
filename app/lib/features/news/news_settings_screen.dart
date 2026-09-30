import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/repository.dart';
import '../../domain/news.dart';
import '../../ui/common.dart';

class NewsSettingsScreen extends ConsumerStatefulWidget {
  const NewsSettingsScreen({super.key});

  @override
  ConsumerState<NewsSettingsScreen> createState() => _NewsSettingsScreenState();
}

class _NewsSettingsScreenState extends ConsumerState<NewsSettingsScreen> {
  final _keywords = TextEditingController();
  final _blocked = TextEditingController();
  int _maxAge = 48;
  int _briefing = 3;
  bool _loaded = false;

  static const _ages = [(24, '24 horas'), (48, '2 dias'), (168, '7 dias')];
  static const _briefings = [(0, 'Nenhuma'), (3, '3'), (5, '5')];

  @override
  void dispose() {
    _keywords.dispose();
    _blocked.dispose();
    super.dispose();
  }

  void _refreshFeed() {
    ref.invalidate(newsSourcesProvider);
    ref.invalidate(newsFeedProvider);
  }

  Future<void> _toggle(NewsSource source, bool subscribed) async {
    try {
      await ref.read(newsRepositoryProvider).setSubscribed(source.id, subscribed);
      if (!mounted) return;
      _refreshFeed();
    } on RepositoryException {
      if (mounted) showError(context, 'Não foi possível alterar a fonte.');
    }
  }

  Future<void> _save() async {
    final prefs = NewsPrefs(
      keywords: parseTerms(_keywords.text),
      blocked: parseTerms(_blocked.text),
      maxAgeHours: _maxAge,
      briefingCount: _briefing,
    );
    try {
      await ref.read(newsRepositoryProvider).savePrefs(prefs);
      if (!mounted) return;
      ref.invalidate(newsPrefsProvider);
      ref.invalidate(newsFeedProvider);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Preferências salvas.')));
    } on RepositoryException {
      if (mounted) showError(context, 'Não foi possível salvar as preferências.');
    }
  }

  Future<void> _addFeed() async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => const AddFeedDialog(),
    );
    if (!mounted || result == null) return;
    final (name, url) = result;
    try {
      await ref.read(newsRepositoryProvider).addCustomSource(name: name, feedUrl: url);
      if (!mounted) return;
      _refreshFeed();
    } on RepositoryException catch (e) {
      if (mounted) {
        showError(context, e.duplicate ? 'Esse feed já foi adicionado.' : e.message);
      }
    }
  }

  Future<void> _delete(NewsSource source) async {
    try {
      await ref.read(newsRepositoryProvider).deleteCustomSource(source.id);
      if (!mounted) return;
      _refreshFeed();
    } on RepositoryException {
      if (mounted) showError(context, 'Não foi possível remover o feed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(newsPrefsProvider);
    final sources = ref.watch(newsSourcesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Fontes e interesses')),
      body: asyncView(prefs, (p) {
        if (!_loaded) {
          _loaded = true;
          _keywords.text = p.keywords.join(', ');
          _blocked.text = p.blocked.join(', ');
          _maxAge = p.maxAgeHours;
          _briefing = p.briefingCount;
        }
        return asyncView(sources, (list) => ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const SectionHeader('Interesses'),
                TextField(
                  key: const Key('news-keywords'),
                  controller: _keywords,
                  decoration: const InputDecoration(
                    labelText: 'Destacar notícias sobre',
                    helperText: 'Separe por vírgula. Ex.: inteligência artificial, Copa, UFMG',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('news-blocked'),
                  controller: _blocked,
                  decoration: const InputDecoration(labelText: 'Esconder notícias sobre'),
                ),
                const SectionHeader('Mostrar notícias de até'),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final (hours, label) in _ages)
                      ChoiceChip(
                        label: Text(label),
                        selected: _maxAge == hours,
                        onSelected: (_) => setState(() => _maxAge = hours),
                      ),
                  ],
                ),
                const SectionHeader('Manchetes no resumo da Alexa'),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final (count, label) in _briefings)
                      ChoiceChip(
                        label: Text(label),
                        selected: _briefing == count,
                        onSelected: (_) => setState(() => _briefing = count),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    key: const Key('save-news-prefs'),
                    onPressed: _save,
                    child: const Text('Salvar preferências'),
                  ),
                ),
                Row(
                  children: [
                    const Expanded(child: SectionHeader('Fontes')),
                    TextButton.icon(
                      key: const Key('add-feed'),
                      onPressed: _addFeed,
                      icon: const Icon(Icons.add),
                      label: const Text('Adicionar feed'),
                    ),
                  ],
                ),
                for (final s in list)
                  SwitchListTile(
                    key: ValueKey('source-${s.id}'),
                    title: Text(s.name),
                    subtitle: Text(s.section),
                    value: s.subscribed,
                    onChanged: (v) => _toggle(s, v),
                    secondary: s.custom
                        ? IconButton(
                            tooltip: 'Remover feed',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _delete(s),
                          )
                        : null,
                  ),
              ],
            ));
      }),
    );
  }
}

class AddFeedDialog extends StatefulWidget {
  const AddFeedDialog({super.key});

  @override
  State<AddFeedDialog> createState() => _AddFeedDialogState();
}

class _AddFeedDialogState extends State<AddFeedDialog> {
  final _name = TextEditingController();
  final _url = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _name.text.trim().isNotEmpty && _url.text.trim().isNotEmpty;
    return AlertDialog(
      title: const Text('Adicionar feed'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('feed-name'),
            controller: _name,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Nome'),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('feed-url'),
            controller: _url,
            keyboardType: TextInputType.url,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Endereço do feed RSS',
              hintText: 'https://site.com/feed',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(
          onPressed: ready
              ? () => Navigator.of(context).pop((_name.text.trim(), _url.text.trim()))
              : null,
          child: const Text('Adicionar'),
        ),
      ],
    );
  }
}
