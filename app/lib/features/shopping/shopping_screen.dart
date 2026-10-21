import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/sync_providers.dart';
import '../../data/repository.dart';
import '../../data/shopping_repository.dart';
import '../../domain/ids.dart';
import '../../domain/shopping.dart';
import '../../ui/common.dart';
import '../../ui/org_theme.dart';
import '../../ui/org_widgets.dart';
import 'shopping_item_sheet.dart';
import 'shopping_providers.dart';

/// Rota `/compras`: listas de compras com seções, frequentes e modo "no mercado".
class ShoppingScreen extends ConsumerStatefulWidget {
  const ShoppingScreen({super.key});

  @override
  ConsumerState<ShoppingScreen> createState() => _ShoppingScreenState();
}

class _ShoppingScreenState extends ConsumerState<ShoppingScreen> {
  final _name = TextEditingController();
  final _qty = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Primeiro uso: cria "Mercado" sozinha (não faz nada se já houver lista).
    // Só depois da carga inicial da nuvem: antes, as listas dela ainda não chegaram e criaria "Mercado" em duplicidade.
    ref.read(syncReadyProvider).then((_) => ref.read(shoppingRepositoryProvider).ensureDefaultList()).then<void>(
      (_) {},
      onError: (Object _) {
        if (mounted) showError(context, 'Não foi possível abrir suas listas.');
      },
    );
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _qty.dispose();
    super.dispose();
  }

  ShoppingRepository get _repo => ref.read(shoppingRepositoryProvider);

  Future<void> _add(ShoppingList list, List<ShoppingItem> items, {String? name, ShopSection? section}) async {
    final text = (name ?? _name.text).trim();
    if (text.isEmpty) return;
    if (findDuplicate(text, list.id, items) != null) {
      showError(context, 'Já está na lista');
      _name.clear();
      _qty.clear();
      return;
    }
    try {
      await _repo.addItem(listId: list.id, name: text, quantity: _qty.text, section: section);
      _name.clear();
      _qty.clear();
    } on RepositoryException {
      if (mounted) showError(context, 'Não foi possível adicionar. O texto continua no campo.');
    }
  }

  Future<void> _check(ShoppingItem i) async {
    try {
      await _repo.setChecked(i.id, !i.checked);
    } on RepositoryException {
      if (mounted) showError(context, 'Não foi possível marcar o item.');
    }
  }

  Future<void> _finish(ShoppingList list, int count) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Finalizar compra'),
        content: Text('Apagar $count ${count == 1 ? 'item marcado' : 'itens marcados'} da lista ${list.name}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            key: const Key('shop-finish-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Finalizar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final n = await _repo.finishShopping(list.id);
      if (mounted) showError(context, 'Compra finalizada: ${plural(n, 'item apagado', 'itens apagados')}.');
    } on RepositoryException {
      if (mounted) showError(context, 'Não foi possível finalizar a compra.');
    }
  }

  Future<void> _nameDialog({ShoppingList? list, required int nextPosition}) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _ListNameDialog(initial: list?.name ?? '', isNew: list == null),
    );
    final text = name?.trim() ?? '';
    if (text.isEmpty || !mounted) return;
    final saved = list?.copyWith(name: text) ?? ShoppingList(id: newId(), name: text, position: nextPosition);
    try {
      await _repo.upsertList(saved);
      if (list == null) ref.read(shoppingSelectedListProvider.notifier).select(saved.id);
    } on RepositoryException catch (e) {
      if (mounted) {
        showError(context, e.duplicate ? 'Já existe uma lista "$text".' : 'Não foi possível salvar a lista.');
      }
    }
  }

  Future<void> _deleteList(ShoppingList list) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Apagar "${list.name}"?'),
        content: const Text('Os itens da lista também serão apagados.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            key: const Key('shop-list-delete-ok'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _repo.deleteList(list.id);
      ref.read(shoppingSelectedListProvider.notifier).select(null);
    } on RepositoryException {
      if (mounted) showError(context, 'Não foi possível apagar a lista.');
    }
  }

  Future<void> _editOrder(ShoppingList list) async {
    final order = await showDialog<List<ShopSection>>(
      context: context,
      builder: (_) => _SectionOrderDialog(initial: _fullOrder(list.sectionOrder)),
    );
    if (order == null || !mounted) return;
    try {
      await _repo.upsertList(list.copyWith(sectionOrder: order));
    } on RepositoryException {
      if (mounted) showError(context, 'Não foi possível salvar a ordem.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final lists = ref.watch(shoppingListsProvider);
    final allItems = ref.watch(shoppingItemsProvider);
    final frequent = ref.watch(frequentItemsProvider).value ?? const <FrequentItem>[];
    final gutter = MediaQuery.sizeOf(context).width < 720 ? 16.0 : 24.0;
    return Scaffold(
      body: SafeArea(
        child: asyncView(lists, (listData) => asyncView(allItems, (itemData) {
              if (listData.isEmpty) return const Center(child: CircularProgressIndicator());
              final sorted = [...listData]..sort((a, b) => a.position.compareTo(b.position));
              final selectedId = ref.watch(shoppingSelectedListProvider);
              final list = sorted.firstWhere((l) => l.id == selectedId, orElse: () => sorted.first);
              final inList = itemData.where((i) => i.listId == list.id).toList();
              final unchecked = inList.where((i) => !i.checked).toList();
              final cart = inList.where((i) => i.checked).toList()
                ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
              final groups = groupBySection(unchecked, list.sectionOrder);
              final again = buyAgain(frequent, inList);
              final suggestions = suggest(_name.text, frequent)
                  .where((f) => findDuplicate(f.name, list.id, inList) == null)
                  .toList();
              final nextPosition = sorted.last.position + 1;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PageHeader(
                    title: 'Compras',
                    subtitle: list.name,
                    actions: [
                      IconButton(
                        key: const Key('shop-order'),
                        tooltip: 'Ordem das seções',
                        icon: const Icon(Icons.swap_vert),
                        onPressed: () => _editOrder(list),
                      ),
                      IconButton(
                        key: const Key('shop-new-list'),
                        tooltip: 'Nova lista',
                        icon: const Icon(Icons.playlist_add),
                        onPressed: () => _nameDialog(nextPosition: nextPosition),
                      ),
                      PopupMenuButton<String>(
                        key: const Key('shop-list-menu'),
                        tooltip: 'Mais opções da lista',
                        onSelected: (v) => v == 'rename'
                            ? _nameDialog(list: list, nextPosition: nextPosition)
                            : _deleteList(list),
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'rename', child: Text('Renomear lista')),
                          if (sorted.length > 1) const PopupMenuItem(value: 'delete', child: Text('Apagar lista')),
                        ],
                      ),
                    ],
                  ),
                  if (sorted.length > 1)
                    SingleChildScrollView(
                      key: const Key('shop-lists'),
                      scrollDirection: Axis.horizontal,
                      padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 8),
                      child: Row(
                        children: [
                          for (final l in sorted)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                key: Key('shop-list-${l.id}'),
                                label: Text(l.name),
                                selected: l.id == list.id,
                                onSelected: (_) => ref.read(shoppingSelectedListProvider.notifier).select(l.id),
                              ),
                            ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: gutter),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            key: const Key('shop-add-field'),
                            controller: _name,
                            maxLength: 80,
                            textInputAction: TextInputAction.done,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: const InputDecoration(hintText: 'Adicionar item', counterText: ''),
                            onSubmitted: (_) => _add(list, inList),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 96,
                          child: TextField(
                            key: const Key('shop-qty-field'),
                            controller: _qty,
                            maxLength: 30,
                            textInputAction: TextInputAction.done,
                            decoration: const InputDecoration(hintText: 'Qtd.', counterText: ''),
                            onSubmitted: (_) => _add(list, inList),
                          ),
                        ),
                        IconButton.filled(
                          key: const Key('shop-add-button'),
                          tooltip: 'Adicionar',
                          icon: const Icon(Icons.add),
                          onPressed: () => _add(list, inList),
                        ),
                      ],
                    ),
                  ),
                  if (suggestions.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 0),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final f in suggestions)
                            ActionChip(
                              key: Key('shop-suggest-${foldName(f.name)}'),
                              label: Text(f.name),
                              onPressed: () => _add(list, inList, name: f.name),
                            ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 24),
                      children: [
                        if (again.isNotEmpty) ...[
                          const SectionHeader('Comprar de novo'),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              for (final f in again)
                                ActionChip(
                                  key: Key('shop-again-${foldName(f.name)}'),
                                  avatar: const Icon(Icons.add, size: 18),
                                  label: Text(f.name),
                                  onPressed: () => _add(list, inList, name: f.name, section: f.section),
                                ),
                            ],
                          ),
                        ],
                        if (inList.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 24),
                            child: EmptyHint('Lista vazia. Escreva o nome de um item acima para começar.'),
                          ),
                        for (final (section, items) in groups) ...[
                          SectionHeader(section.label),
                          for (final i in items) _ItemRow(item: i, onCheck: _check),
                        ],
                        if (cart.isNotEmpty) ...[
                          SectionHeader('No carrinho (${cart.length})'),
                          for (final i in cart) _ItemRow(item: i, onCheck: _check),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: FilledButton.icon(
                              key: const Key('shop-finish'),
                              onPressed: () => _finish(list, cart.length),
                              icon: const Icon(Icons.check),
                              label: const Text('Finalizar compra'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            })),
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.onCheck});

  final ShoppingItem item;
  final Future<void> Function(ShoppingItem) onCheck;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final org = context.org;
    final style = item.checked
        ? theme.textTheme.bodyLarge?.copyWith(decoration: TextDecoration.lineThrough, color: org.inkMuted)
        : theme.textTheme.bodyLarge;
    return InkWell(
      key: Key('shop-item-${item.id}'),
      borderRadius: BorderRadius.circular(org.radiusSm),
      onTap: () => showShoppingItemSheet(context, item),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            Checkbox(
              key: Key('shop-check-${item.id}'),
              value: item.checked,
              onChanged: (_) => onCheck(item),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name, style: style),
                    if (item.quantity.isNotEmpty)
                      Text(item.quantity, style: theme.textTheme.bodySmall?.copyWith(color: org.inkMuted)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ordem completa (as seções que faltam na ordem salva vão para o fim, na ordem padrão).
List<ShopSection> _fullOrder(List<ShopSection>? saved) => [
      ...?saved,
      for (final s in ShopSection.values)
        if (!(saved?.contains(s) ?? false)) s,
    ];

class _SectionOrderDialog extends StatefulWidget {
  const _SectionOrderDialog({required this.initial});

  final List<ShopSection> initial;

  @override
  State<_SectionOrderDialog> createState() => _SectionOrderDialogState();
}

class _SectionOrderDialogState extends State<_SectionOrderDialog> {
  late final List<ShopSection> _order = [...widget.initial];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ordem das seções'),
      contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
      content: SizedBox(
        width: 320,
        child: ReorderableListView(
          key: const Key('shop-order-list'),
          shrinkWrap: true,
          buildDefaultDragHandles: false,
          onReorderItem: (from, to) => setState(() => _order.insert(to, _order.removeAt(from))),
          children: [
            for (var i = 0; i < _order.length; i++)
              ListTile(
                key: ValueKey(_order[i]),
                title: Text(_order[i].label),
                trailing: ReorderableDragStartListener(
                  index: i,
                  child: Padding(
                    key: Key('shop-order-handle-${_order[i].name}'),
                    padding: const EdgeInsets.all(12),
                    child: const Icon(Icons.drag_handle),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          key: const Key('shop-order-save'),
          onPressed: () => Navigator.pop(context, _order),
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}

class _ListNameDialog extends StatefulWidget {
  const _ListNameDialog({required this.initial, required this.isNew});

  final String initial;
  final bool isNew;

  @override
  State<_ListNameDialog> createState() => _ListNameDialogState();
}

class _ListNameDialogState extends State<_ListNameDialog> {
  late final _field = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isNew ? 'Nova lista' : 'Renomear lista'),
      content: TextField(
        key: const Key('shop-list-name-field'),
        controller: _field,
        autofocus: true,
        maxLength: 40,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(labelText: 'Nome', counterText: ''),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          key: const Key('shop-list-name-ok'),
          onPressed: () => Navigator.pop(context, _field.text),
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}
