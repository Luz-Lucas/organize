import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/shopping_repository.dart';
import 'package:organizacional/data/repository.dart';
import 'package:organizacional/domain/shopping.dart';

void main() {
  test('ensureDefaultList cria Mercado uma vez só', () async {
    final repo = MemoryShoppingRepository();
    final a = await repo.ensureDefaultList();
    final b = await repo.ensureDefaultList();
    expect(a.name, 'Mercado');
    expect(b.id, a.id);
    expect((await repo.watchLists().first), hasLength(1));
  });

  test('seção nula: lembra a do frequente pelo nome; senão outros', () async {
    final repo = MemoryShoppingRepository();
    final l = await repo.ensureDefaultList();
    await repo.addItem(listId: l.id, name: 'Leite', section: ShopSection.frios);
    await repo.addItem(listId: l.id, name: 'leite');
    await repo.addItem(listId: l.id, name: 'Coisa');
    final items = await repo.watchItems().first;
    expect(items.firstWhere((i) => i.name == 'leite').section, ShopSection.frios);
    expect(items.firstWhere((i) => i.name == 'Coisa').section, ShopSection.outros);
    final f = (await repo.watchFrequent().first).firstWhere((f) => f.name == 'leite');
    expect(f.times, 2);
  });

  test('corrigir a seção de um item atualiza o frequente', () async {
    final repo = MemoryShoppingRepository();
    final l = await repo.ensureDefaultList();
    await repo.addItem(listId: l.id, name: 'Tapioca');
    final item = (await repo.watchItems().first).single;
    await repo.updateItem(item.copyWith(section: ShopSection.mercearia));
    await repo.addItem(listId: l.id, name: 'tapioca');
    final items = await repo.watchItems().first;
    expect(items.last.section, ShopSection.mercearia);
  });

  test('finishShopping apaga só os marcados da lista e conta', () async {
    final repo = MemoryShoppingRepository();
    final l = await repo.ensureDefaultList();
    await repo.addItem(listId: l.id, name: 'A');
    await repo.addItem(listId: l.id, name: 'B');
    await repo.addItem(listId: l.id, name: 'C');
    final items = await repo.watchItems().first;
    await repo.setChecked(items[0].id, true);
    await repo.setChecked(items[1].id, true);
    expect(await repo.finishShopping(l.id), 2);
    expect((await repo.watchItems().first).map((i) => i.name), ['C']);
  });

  test('apagar a lista leva os itens junto; nome de lista é único sem caixa', () async {
    final repo = MemoryShoppingRepository();
    final l = await repo.ensureDefaultList();
    await repo.addItem(listId: l.id, name: 'A');
    await expectLater(
      repo.upsertList(const ShoppingList(id: 'x', name: 'mercado')),
      throwsA(isA<RepositoryException>().having((e) => e.duplicate, 'duplicate', true)),
    );
    await repo.deleteList(l.id);
    expect(await repo.watchItems().first, isEmpty);
  });

  test('failWrites simula queda de conexão', () async {
    final repo = MemoryShoppingRepository();
    final l = await repo.ensureDefaultList();
    repo.failWrites = true;
    await expectLater(repo.addItem(listId: l.id, name: 'A'), throwsA(isA<RepositoryException>()));
  });
}
