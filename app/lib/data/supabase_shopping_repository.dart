import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/shopping.dart';
import 'repository.dart';
import 'shopping_repository.dart';

class SupabaseShoppingRepository implements ShoppingRepository {
  SupabaseShoppingRepository(this._db);

  final SupabaseClient _db;

  Stream<List<T>> _watch<T>(
    String table,
    T Function(Map<String, dynamic>) fromMap,
    String orderBy,
  ) =>
      _db
          .from(table)
          .stream(primaryKey: ['id'])
          .order(orderBy, ascending: true)
          .map((rows) => rows.map(fromMap).toList());

  Future<T> _guard<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on PostgrestException catch (e) {
      throw RepositoryException(e.message, duplicate: e.code == '23505');
    } on RepositoryException {
      rethrow;
    } catch (e) {
      throw RepositoryException('Falha de conexão: $e');
    }
  }

  @override
  Stream<List<ShoppingList>> watchLists() => _watch('shopping_lists', ShoppingList.fromMap, 'position');

  Future<ShoppingList?> _firstList() async {
    final rows = await _db.from('shopping_lists').select().order('position').order('created_at').limit(1);
    return rows.isEmpty ? null : ShoppingList.fromMap(rows.first);
  }

  @override
  Future<ShoppingList> ensureDefaultList() => _guard(() async {
        final existing = await _firstList();
        if (existing != null) return existing;
        try {
          final row = await _db.from('shopping_lists').insert({'name': 'Mercado'}).select().single();
          return ShoppingList.fromMap(row);
        } on PostgrestException catch (e) {
          // Outro aparelho criou "Mercado" ao mesmo tempo: usa a que já existe.
          if (e.code == '23505') {
            final again = await _firstList();
            if (again != null) return again;
          }
          rethrow;
        }
      });

  @override
  Future<void> upsertList(ShoppingList l) =>
      _guard(() async => await _db.from('shopping_lists').upsert(l.toMap()));

  @override
  Future<void> deleteList(String id) =>
      _guard(() async => await _db.from('shopping_lists').delete().eq('id', id));

  @override
  Stream<List<ShoppingItem>> watchItems() => _watch('shopping_items', ShoppingItem.fromMap, 'created_at');

  @override
  Future<void> addItem({
    required String listId,
    required String name,
    String quantity = '',
    ShopSection? section,
  }) =>
      _guard(() async => await _db.from('shopping_items').insert({
            'list_id': listId,
            'name': name.trim(),
            'quantity': quantity.trim(),
            // Seção nula: o gatilho do banco escolhe (frequente, palavra-chave ou Outros).
            if (section != null) 'section': section.name,
          }));

  @override
  Future<void> updateItem(ShoppingItem i) => _guard(() async => await _db.from('shopping_items').update({
        'name': i.name,
        'quantity': i.quantity,
        'section': i.section.name,
        'checked': i.checked,
        'position': i.position,
      }).eq('id', i.id));

  @override
  Future<void> setChecked(String id, bool checked) =>
      _guard(() async => await _db.from('shopping_items').update({'checked': checked}).eq('id', id));

  @override
  Future<void> deleteItem(String id) =>
      _guard(() async => await _db.from('shopping_items').delete().eq('id', id));

  @override
  Future<int> finishShopping(String listId) => _guard(() async {
        final rows = await _db
            .from('shopping_items')
            .delete()
            .eq('list_id', listId)
            .eq('checked', true)
            .select('id');
        return rows.length;
      });

  @override
  Stream<List<FrequentItem>> watchFrequent() =>
      _watch('shopping_frequent', FrequentItem.fromMap, 'last_added_at');
}
