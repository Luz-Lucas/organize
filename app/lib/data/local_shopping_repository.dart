import 'dart:async';

import '../domain/ids.dart';
import '../domain/json.dart';
import '../domain/shopping.dart';
import '../sync/local_store.dart';
import 'repository.dart';
import 'shopping_repository.dart';

const _lists = 'shopping_lists';
const _items = 'shopping_items';
const _frequent = 'shopping_frequent';

/// Compras local-primeiro: lê e grava no [LocalStore] (a tela muda na hora, sem rede) e o `SyncEngine`
/// leva a fila à nuvem.
///
/// O que o banco deriva (seção do item novo, tabela de frequentes) aparece aqui de forma provisória e
/// se corrige quando a nuvem devolve a linha. `shopping_frequent` é só leitura: nunca entra na fila.
class LocalFirstShoppingRepository implements ShoppingRepository {
  LocalFirstShoppingRepository(this._store, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final LocalStore _store;
  final DateTime Function() _now;
  int _seq = 0;

  /// Escritas que leem antes de gravar rodam uma de cada vez.
  Future<void> _serial = Future.value();

  Future<T> _exclusive<T>(Future<T> Function() op) {
    final done = _serial.then((_) => op());
    _serial = done.then<void>((_) {}, onError: (_) {});
    return done;
  }

  static const _itemColumns = ['id', 'list_id', 'name', 'quantity', 'section', 'checked', 'position'];

  /// Só as colunas graváveis do item, com a seção como está guardada (nula = o banco ainda vai escolher).
  static Map<String, dynamic> _itemRow(Map<String, dynamic> raw) =>
      {for (final c in _itemColumns) if (raw.containsKey(c)) c: raw[c]};

  static int _listOrder(Map<String, dynamic> a, Map<String, dynamic> b) {
    final p = ((a['position'] as num?) ?? 0).compareTo((b['position'] as num?) ?? 0);
    if (p != 0) return p;
    final at = parseDate(a['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bt = parseDate(b['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0);
    final c = at.compareTo(bt);
    return c != 0 ? c : (a['id'] as String).compareTo(b['id'] as String);
  }

  // ---------------------------------------------------------------- listas

  @override
  Stream<List<ShoppingList>> watchLists() =>
      _store.watch(_lists).map((rows) => [for (final r in [...rows]..sort(_listOrder)) ShoppingList.fromMap(r)]);

  @override
  Future<ShoppingList> ensureDefaultList() async {
    late ShoppingList result;
    await _exclusive(() async {
      final rows = (await _store.all(_lists))..sort(_listOrder);
      if (rows.isNotEmpty) {
        result = ShoppingList.fromMap(rows.first);
        return;
      }
      result = ShoppingList(id: newId(), name: 'Mercado');
      await _store.put(_lists, {...result.toMap(), 'created_at': _stamp()});
    });
    return result;
  }

  @override
  Future<void> upsertList(ShoppingList l) => _exclusive(() async {
        final lists = await _store.all(_lists);
        final clash = lists.any((o) => o['id'] != l.id && (o['name'] as String).toLowerCase() == l.name.toLowerCase());
        if (clash) {
          throw const RepositoryException(
              'duplicate key value violates unique constraint "shopping_lists_user_name"',
              duplicate: true);
        }
        final isNew = !lists.any((o) => o['id'] == l.id);
        await _store.put(_lists, {...l.toMap(), if (isNew) 'created_at': _stamp()});
      });

  @override
  Future<void> deleteList(String id) => _exclusive(() async {
        final itemIds = [
          for (final r in await _store.all(_items))
            if (r['list_id'] == id) r['id'] as String,
        ];
        await _store.removeMany(_items, itemIds);
        await _store.remove(_lists, id);
      });

  // ---------------------------------------------------------------- itens

  @override
  Stream<List<ShoppingItem>> watchItems() => _store.watch(_items).map((rows) {
        final items = rows.map(ShoppingItem.fromMap).toList()
          ..sort((a, b) {
            final c = a.createdAt.compareTo(b.createdAt);
            return c != 0 ? c : a.id.compareTo(b.id);
          });
        return items;
      });

  String _stamp() => _now().toUtc().add(Duration(microseconds: _seq++)).toIso8601String();

  @override
  Future<void> addItem({
    required String listId,
    required String name,
    String quantity = '',
    ShopSection? section,
  }) =>
      _exclusive(() async {
        final item = ShoppingItem(
          id: newId(),
          listId: listId,
          name: name.trim(),
          quantity: quantity.trim(),
          createdAt: _now(),
        );
        final stamp = _stamp();
        await _store.put(_items, {
          ..._itemRow({...item.toMap(), 'section': section?.name}),
          'created_at': stamp,
        });
        await _countFrequent(item.name, section, stamp);
      });

  @override
  Future<void> updateItem(ShoppingItem i) => _exclusive(() async {
        final raw = await _store.get(_items, i.id);
        if (raw == null) return;
        final old = ShopSection.fromName(raw['section']);
        // Seção ainda nula (o banco não escolheu) e a tela continua em Outros: segue nula.
        final keepNull = raw['section'] == null && i.section == ShopSection.outros;
        await _store.put(_items, {
          ..._itemRow(raw),
          'name': i.name,
          'quantity': i.quantity,
          'section': keepNull ? null : i.section.name,
          'checked': i.checked,
          'position': i.position,
        });
        if (old != i.section) await _relearnFrequent(i.name, i.section);
      });

  @override
  Future<void> setChecked(String id, bool checked) => _exclusive(() async {
        final raw = await _store.get(_items, id);
        if (raw == null) return;
        await _store.put(_items, {..._itemRow(raw), 'checked': checked});
      });

  @override
  Future<void> deleteItem(String id) async {
    if (await _store.get(_items, id) != null) await _store.remove(_items, id);
  }

  @override
  Future<int> finishShopping(String listId) => _exclusive(() async {
        final ids = [
          for (final r in await _store.all(_items))
            if (r['list_id'] == listId && r['checked'] == true) r['id'] as String,
        ];
        await _store.removeMany(_items, ids);
        return ids.length;
      });

  // ---------------------------------------------------------------- frequentes

  @override
  Stream<List<FrequentItem>> watchFrequent() => _store.watch(_frequent).map((rows) {
        // A cópia otimista (id "local:…") e a linha que a nuvem devolve podem coexistir por um instante:
        // vale uma por nome, a que tem mais usos (e, empatando, a da nuvem).
        final best = <String, Map<String, dynamic>>{};
        for (final r in rows) {
          final key = foldName(r['name'] as String);
          final cur = best[key];
          if (cur == null || _better(r, cur)) best[key] = r;
        }
        return best.values.map(FrequentItem.fromMap).toList();
      });

  static bool _isLocal(Map<String, dynamic> r) => (r['id'] as String).startsWith('local:');

  static bool _better(Map<String, dynamic> a, Map<String, dynamic> b) {
    final t = ((a['times'] as num?) ?? 1).compareTo((b['times'] as num?) ?? 1);
    if (t != 0) return t > 0;
    return !_isLocal(a) && _isLocal(b);
  }

  Future<Map<String, dynamic>?> _frequentByName(String name) async {
    final key = foldName(name);
    Map<String, dynamic>? found;
    for (final r in await _store.all(_frequent)) {
      if (foldName(r['name'] as String) != key) continue;
      if (found == null || _better(r, found)) found = r;
    }
    return found;
  }

  /// O banco conta cada item novo no frequente (e lembra a seção); aqui é só uma cópia provisória para as
  /// sugestões funcionarem sem rede. Entra por `applyRemoteUpsert` porque `shopping_frequent` nunca vai à fila.
  Future<void> _countFrequent(String name, ShopSection? section, String stamp) async {
    final known = await _frequentByName(name);
    final resolved = section?.name ?? known?['section'] ?? ShopSection.outros.name;
    final key = foldName(name);
    await _store.applyRemoteUpsert(_frequent, {
      ...?known,
      'id': known?['id'] ?? 'local:$key',
      'name_key': key,
      'name': name,
      'section': resolved,
      'times': (((known?['times']) as num?) ?? 0).toInt() + 1,
      'last_added_at': stamp,
    });
  }

  /// Corrigir a seção de um item faz o banco lembrar a nova para o mesmo nome.
  Future<void> _relearnFrequent(String name, ShopSection section) async {
    final known = await _frequentByName(name);
    if (known == null || known['section'] == section.name) return;
    await _store.applyRemoteUpsert(_frequent, {...known, 'section': section.name});
  }
}
