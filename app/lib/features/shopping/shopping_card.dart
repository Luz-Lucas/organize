import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/shopping.dart';
import '../../ui/common.dart';
import '../../ui/org_theme.dart';
import '../../ui/org_widgets.dart';
import 'shopping_providers.dart';

/// Cartão da Início: "Mercado — 7 itens", os 3 primeiros e o botão Abrir (`/compras`).
class ShoppingCard extends ConsumerWidget {
  const ShoppingCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final org = context.org;
    final lists = ref.watch(shoppingListsProvider);
    final items = ref.watch(shoppingItemsProvider);

    final sorted = [...?lists.value]..sort((a, b) => a.position.compareTo(b.position));
    final list = sorted.isEmpty ? null : sorted.first;
    final pending = [
      for (final i in items.value ?? const <ShoppingItem>[])
        if (list != null && i.listId == list.id && !i.checked) i,
    ]..sort((a, b) {
        final c = a.createdAt.compareTo(b.createdAt);
        return c != 0 ? c : a.position.compareTo(b.position);
      });
    final loading = (!lists.hasValue || !items.hasValue) && !(lists.hasError || items.hasError);
    final title = '${list?.name ?? 'Mercado'} — ${pending.isEmpty ? 'lista vazia' : plural(pending.length, 'item', 'itens')}';

    return OrgCard(
      key: const Key('shopping-card'),
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              children: [
                Icon(Icons.shopping_cart_outlined, size: 20, color: org.accentText),
                const SizedBox(width: 12),
                Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
                TextButton(
                  key: const Key('shopping-open'),
                  onPressed: () => context.go('/compras'),
                  child: const Text('Abrir'),
                ),
              ],
            ),
          ),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else if (!lists.hasValue || !items.hasValue)
            const EmptyHint('Não foi possível carregar a lista.')
          else
            for (final i in pending.take(3))
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 2, 8, 2),
                child: Text(
                  i.quantity.isEmpty ? i.name : '${i.name} · ${i.quantity}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge,
                ),
              ),
          if (pending.length > 3)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('+ ${pending.length - 3} na lista',
                  style: theme.textTheme.bodySmall?.copyWith(color: org.inkMuted)),
            ),
        ],
      ),
    );
  }
}
