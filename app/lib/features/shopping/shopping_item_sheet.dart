import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repository.dart';
import '../../domain/shopping.dart';
import '../../ui/common.dart';
import 'shopping_providers.dart';

/// Edita nome, quantidade e seção de um item (ou apaga). Corrigir a seção faz o banco lembrar.
Future<void> showShoppingItemSheet(BuildContext context, ShoppingItem item) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ShoppingItemSheet(item: item),
    );

class ShoppingItemSheet extends ConsumerStatefulWidget {
  const ShoppingItemSheet({super.key, required this.item});

  final ShoppingItem item;

  @override
  ConsumerState<ShoppingItemSheet> createState() => _ShoppingItemSheetState();
}

class _ShoppingItemSheetState extends ConsumerState<ShoppingItemSheet> {
  late final _name = TextEditingController(text: widget.item.name);
  late final _qty = TextEditingController(text: widget.item.quantity);
  late ShopSection _section = widget.item.section;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _qty.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() op, String failure) async {
    setState(() => _busy = true);
    try {
      await op();
      if (mounted) Navigator.of(context).pop();
    } on RepositoryException {
      if (mounted) {
        setState(() => _busy = false);
        showError(context, failure);
      }
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    await _run(
      () => ref.read(shoppingRepositoryProvider).updateItem(
            widget.item.copyWith(name: name, quantity: _qty.text.trim(), section: _section),
          ),
      'Não foi possível salvar o item.',
    );
  }

  Future<void> _delete() => _run(
        () => ref.read(shoppingRepositoryProvider).deleteItem(widget.item.id),
        'Não foi possível apagar o item.',
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('shop-edit-name'),
              controller: _name,
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Item', counterText: ''),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('shop-edit-qty'),
              controller: _qty,
              maxLength: 30,
              decoration: const InputDecoration(labelText: 'Quantidade (ex.: 2 kg)', counterText: ''),
            ),
            const SizedBox(height: 16),
            Text('Seção', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final s in ShopSection.values)
                  ChoiceChip(
                    key: Key('shop-section-${s.name}'),
                    label: Text(s.label),
                    selected: _section == s,
                    onSelected: (_) => setState(() => _section = s),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton.icon(
                  key: const Key('shop-edit-delete'),
                  onPressed: _busy ? null : _delete,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Apagar'),
                ),
                FilledButton(
                  key: const Key('shop-edit-save'),
                  onPressed: _busy ? null : _save,
                  child: const Text('Salvar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
