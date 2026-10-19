import 'dart:async';

import '../domain/ids.dart';
import '../domain/shopping.dart';
import 'repository.dart';

abstract interface class ShoppingRepository {
  Stream<List<ShoppingList>> watchLists();

  /// Devolve a primeira lista; se não houver nenhuma, cria "Mercado".
  Future<ShoppingList> ensureDefaultList();
  Future<void> upsertList(ShoppingList l);

  /// Apaga a lista e os itens dela.
  Future<void> deleteList(String id);

  /// Itens de todas as listas.
  Stream<List<ShoppingItem>> watchItems();

  /// [section] nula = o banco decide (frequente pelo nome, senão palavras-chave, senão Outros).
  Future<void> addItem({
    required String listId,
    required String name,
    String quantity = '',
    ShopSection? section,
  });
  Future<void> updateItem(ShoppingItem i);
  Future<void> setChecked(String id, bool checked);
  Future<void> deleteItem(String id);

  /// Apaga os itens marcados da lista e devolve quantos eram.
  Future<int> finishShopping(String listId);
  Stream<List<FrequentItem>> watchFrequent();
}

/// Implementação em memória para testes. Reproduz os gatilhos do banco: seção nula vira a do
/// frequente (senão Outros), cada item novo conta no frequente e corrigir a seção atualiza o frequente.
class MemoryShoppingRepository implements ShoppingRepository {
  MemoryShoppingRepository({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final _lists = <String, ShoppingList>{};
  final _items = <String, ShoppingItem>{};
  final _frequent = <String, FrequentItem>{};
  final _changes = StreamController<void>.broadcast(sync: true);
  int _seq = 0;

  /// Quando true, toda escrita falha, simulando uma queda de conexão.
  bool failWrites = false;

  Stream<List<T>> _watch<T>(List<T> Function() snapshot) {
    StreamSubscription<void>? sub;
    late final StreamController<List<T>> controller;
    controller = StreamController<List<T>>(
      onListen: () {
        controller.add(snapshot());
        sub = _changes.stream.listen((_) => controller.add(snapshot()));
      },
      onCancel: () {
        sub?.cancel();
        controller.close();
      },
    );
    return controller.stream;
  }

  void _check() {
    if (failWrites) throw const RepositoryException('Sem conexão (simulado)');
  }

  void _notify() => _changes.add(null);

  @override
  Stream<List<ShoppingList>> watchLists() => _watch(
      () => _lists.values.toList()..sort((a, b) => a.position.compareTo(b.position)));

  @override
  Future<ShoppingList> ensureDefaultList() async {
    if (_lists.isNotEmpty) {
      return (_lists.values.toList()..sort((a, b) => a.position.compareTo(b.position))).first;
    }
    _check();
    final l = ShoppingList(id: newId(), name: 'Mercado');
    _lists[l.id] = l;
    _notify();
    return l;
  }

  @override
  Future<void> upsertList(ShoppingList l) async {
    _check();
    final clash = _lists.values
        .any((o) => o.id != l.id && o.name.toLowerCase() == l.name.toLowerCase());
    if (clash) {
      throw const RepositoryException(
          'duplicate key value violates unique constraint "shopping_lists_user_name"',
          duplicate: true);
    }
    _lists[l.id] = l;
    _notify();
  }

  @override
  Future<void> deleteList(String id) async {
    _check();
    _lists.remove(id);
    _items.removeWhere((_, i) => i.listId == id);
    _notify();
  }

  @override
  Stream<List<ShoppingItem>> watchItems() => _watch(() => _items.values.toList());

  @override
  Future<void> addItem({
    required String listId,
    required String name,
    String quantity = '',
    ShopSection? section,
  }) async {
    _check();
    final key = foldName(name);
    final known = _frequent[key];
    final resolved = section ?? known?.section ?? ShopSection.outros;
    final item = ShoppingItem(
      id: newId(),
      listId: listId,
      name: name.trim(),
      quantity: quantity.trim(),
      section: resolved,
      createdAt: _now().add(Duration(microseconds: _seq++)),
    );
    _items[item.id] = item;
    _frequent[key] = FrequentItem(
      name: item.name,
      section: resolved,
      times: (known?.times ?? 0) + 1,
      lastAddedAt: item.createdAt,
    );
    _notify();
  }

  @override
  Future<void> updateItem(ShoppingItem i) async {
    _check();
    final old = _items[i.id];
    if (old == null) return;
    _items[i.id] = i;
    if (old.section != i.section) {
      final key = foldName(i.name);
      final f = _frequent[key];
      if (f != null) {
        _frequent[key] = FrequentItem(
            name: f.name, section: i.section, times: f.times, lastAddedAt: f.lastAddedAt);
      }
    }
    _notify();
  }

  @override
  Future<void> setChecked(String id, bool checked) async {
    _check();
    final i = _items[id];
    if (i == null) return;
    _items[id] = i.copyWith(checked: checked);
    _notify();
  }

  @override
  Future<void> deleteItem(String id) async {
    _check();
    _items.remove(id);
    _notify();
  }

  @override
  Future<int> finishShopping(String listId) async {
    _check();
    final ids = [for (final i in _items.values) if (i.listId == listId && i.checked) i.id];
    for (final id in ids) {
      _items.remove(id);
    }
    _notify();
    return ids.length;
  }

  @override
  Stream<List<FrequentItem>> watchFrequent() => _watch(() => _frequent.values.toList());
}
