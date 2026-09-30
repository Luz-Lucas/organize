import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../domain/news.dart';

class NewsTile extends ConsumerWidget {
  const NewsTile({super.key, required this.item});

  final NewsItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final now = ref.watch(clockProvider)();
    final meta = '${item.sourceName} · ${timeAgo(item.publishedAt, now)}';
    return ListTile(
      leading: item.highlighted
          ? Icon(Icons.star, color: theme.colorScheme.primary, semanticLabel: 'Destaque')
          : null,
      title: Text(
        item.title,
        style: item.highlighted ? const TextStyle(fontWeight: FontWeight.w600) : null,
      ),
      subtitle: Text(
        item.summary.isEmpty ? meta : '$meta\n${item.summary}',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: item.summary.isNotEmpty,
      onTap: () => ref.read(linkOpenerProvider)(Uri.parse(item.url)),
    );
  }
}
