import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/shopping_repository.dart';
import '../../domain/shopping.dart';

/// Os testes passam a memória; `main.dart` troca pela Supabase.
final shoppingRepositoryProvider = Provider<ShoppingRepository>(
  (ref) => throw UnimplementedError('shoppingRepositoryProvider precisa de override'),
);

final shoppingListsProvider =
    StreamProvider<List<ShoppingList>>((ref) => ref.watch(shoppingRepositoryProvider).watchLists());

/// Itens de todas as listas.
final shoppingItemsProvider =
    StreamProvider<List<ShoppingItem>>((ref) => ref.watch(shoppingRepositoryProvider).watchItems());

final frequentItemsProvider =
    StreamProvider<List<FrequentItem>>((ref) => ref.watch(shoppingRepositoryProvider).watchFrequent());

/// Lista aberta na tela Compras (`null` = a primeira). Fica fora do widget para sobreviver à troca de aba.
class ShoppingSelectedList extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? listId) => state = listId;
}

final shoppingSelectedListProvider =
    NotifierProvider<ShoppingSelectedList, String?>(ShoppingSelectedList.new);
