import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/repository.dart';
import '../../ui/common.dart';
import '../../ui/news_tile.dart';

class NewsScreen extends ConsumerStatefulWidget {
  const NewsScreen({super.key});

  @override
  ConsumerState<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends ConsumerState<NewsScreen> {
  @override
  void initState() {
    super.initState();
    // Ao entrar em Notícias, relê o feed (o provider pode seguir vivo na troca de tela).
    ref.invalidate(newsFeedProvider);
  }

  Future<void> _refresh(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(newsRepositoryProvider).refreshNow();
    } on RepositoryException {
      if (context.mounted) showError(context, 'Não foi possível buscar notícias agora.');
    }
    if (!context.mounted) return;
    ref.invalidate(newsFeedProvider);
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(newsFeedProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notícias'),
        actions: [
          IconButton(
            key: const Key('refresh-news'),
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh),
            onPressed: () => _refresh(context, ref),
          ),
          IconButton(
            key: const Key('news-settings'),
            tooltip: 'Fontes e interesses',
            icon: const Icon(Icons.tune),
            onPressed: () => context.push('/noticias/ajustes'),
          ),
        ],
      ),
      body: asyncView(feed, (items) {
        if (items.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const EmptyHint('Nenhuma notícia ainda.'),
                TextButton(
                  onPressed: () => context.push('/noticias/ajustes'),
                  child: const Text('Escolher fontes'),
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () => _refresh(context, ref),
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) => NewsTile(key: ValueKey(items[i].id), item: items[i]),
          ),
        );
      }),
    );
  }
}
