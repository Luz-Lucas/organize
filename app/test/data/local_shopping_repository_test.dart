import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/local_shopping_repository.dart';
import 'package:organizacional/data/repository.dart';
import 'package:organizacional/domain/shopping.dart';
import 'package:organizacional/sync/local_store.dart';

void main() {
  late DateTime clock;
  late LocalStore store;
  late LocalFirstShoppingRepository repo;

  DateTime now() => clock;

  setUp(() {
    clock = DateTime.utc(2026, 10, 21, 12);
    store = LocalStore.inMemory(now: now);
    repo = LocalFirstShoppingRepository(store, now: now);
  });
  tearDown(() => store.close());

  Future<List<ShoppingItem>> items() => repo.watchItems().first;

  test('ensureDefaultList cria Mercado uma vez só', () async {
    final a = await repo.ensureDefaultList();
    final b = await repo.ensureDefaultList();
    expect(a.name, 'Mercado');
    expect(b.id, a.id);
    expect(await repo.watchLists().first, hasLength(1));
  });

  test('ensureDefaultList devolve a primeira lista por posição quando já há listas', () async {
    await repo.upsertList(const ShoppingList(id: 'b', name: 'Farmácia', position: 1));
    await repo.upsertList(const ShoppingList(id: 'a', name: 'Feira', position: 0));
    expect((await repo.ensureDefaultList()).id, 'a');
    expect(await repo.watchLists().first, hasLength(2));
  });

  test('listas saem por posição e a ordem das seções é gravada', () async {
    await repo.upsertList(const ShoppingList(id: 'b', name: 'B', position: 1));
    await repo.upsertList(const ShoppingList(id: 'a', name: 'A', sectionOrder: [ShopSection.padaria, ShopSection.outros]));
    final ls = await repo.watchLists().first;
    expect(ls.map((l) => l.id), ['a', 'b']);
    expect(ls.first.sectionOrder, [ShopSection.padaria, ShopSection.outros]);
  });

  test('item novo sem seção grava section nulo e aparece como Outros', () async {
    final l = await repo.ensureDefaultList();
    await repo.addItem(listId: l.id, name: ' Leite ', quantity: ' 2 ');
    final item = (await items()).single;
    expect(item.name, 'Leite');
    expect(item.quantity, '2');
    expect(item.section, ShopSection.outros);
    expect(item.checked, isFalse);
    final raw = (await store.all('shopping_items')).single;
    expect(raw.containsKey('section'), isTrue);
    expect(raw['section'], isNull);
    // O que vai para a nuvem também leva a seção nula: o gatilho do banco decide.
    final sent = store.pendingOutbox().where((e) => e.tbl == 'shopping_items').single.data!;
    expect(sent['section'], isNull);
  });

  test('item novo com seção grava o nome dela', () async {
    final l = await repo.ensureDefaultList();
    await repo.addItem(listId: l.id, name: 'Pão', section: ShopSection.padaria);
    expect((await items()).single.section, ShopSection.padaria);
    expect((await store.all('shopping_items')).single['section'], 'padaria');
  });

  test('itens saem na ordem em que foram criados', () async {
    final l = await repo.ensureDefaultList();
    await repo.addItem(listId: l.id, name: 'A');
    await repo.addItem(listId: l.id, name: 'B');
    await repo.addItem(listId: l.id, name: 'C');
    expect((await items()).map((i) => i.name), ['A', 'B', 'C']);
  });

  test('frequentes: cópia otimista conta cada item novo, sem enfileirar nada', () async {
    final l = await repo.ensureDefaultList();
    await repo.addItem(listId: l.id, name: 'Leite', section: ShopSection.frios);
    await repo.addItem(listId: l.id, name: 'leite');
    final f = await repo.watchFrequent().first;
    expect(f, hasLength(1));
    expect(f.single.name, 'leite');
    expect(f.single.times, 2);
    expect(f.single.section, ShopSection.frios);
    expect(store.pendingOutbox().where((e) => e.tbl == 'shopping_frequent'), isEmpty);
  });

  test('frequentes vindos da nuvem aparecem e não duplicam com a cópia otimista', () async {
    final l = await repo.ensureDefaultList();
    await repo.addItem(listId: l.id, name: 'Tapioca');
    // A nuvem devolve a linha de verdade (outro id) com a seção que o gatilho escolheu.
    await store.applyRemoteUpsert('shopping_frequent', {
      'id': 'real-1',
      'name_key': 'tapioca',
      'name': 'Tapioca',
      'section': 'mercearia',
      'times': 1,
      'last_added_at': clock.toIso8601String(),
    });
    final f = await repo.watchFrequent().first;
    expect(f, hasLength(1));
    expect(f.single.section, ShopSection.mercearia);
  });

  test('corrigir a seção de um item atualiza o frequente', () async {
    final l = await repo.ensureDefaultList();
    await repo.addItem(listId: l.id, name: 'Tapioca');
    final item = (await items()).single;
    await repo.updateItem(item.copyWith(section: ShopSection.mercearia));
    expect((await repo.watchFrequent().first).single.section, ShopSection.mercearia);
    expect((await items()).single.section, ShopSection.mercearia);
  });

  test('setChecked e updateItem mudam só o que pedem e não forçam a seção do item pendente', () async {
    final l = await repo.ensureDefaultList();
    await repo.addItem(listId: l.id, name: 'Coisa');
    final id = (await items()).single.id;
    await repo.setChecked(id, true);
    expect((await items()).single.checked, isTrue);
    await repo.updateItem((await items()).single.copyWith(quantity: '3', position: 4));
    final item = (await items()).single;
    expect((item.quantity, item.position, item.checked), ('3', 4, true));
    // A seção continua nula na fila: quem decide é o banco.
    expect(store.pendingOutbox().where((e) => e.tbl == 'shopping_items').single.data!['section'], isNull);
  });

  test('setChecked/updateItem/deleteItem de item que não existe não fazem nada', () async {
    await repo.setChecked('nada', true);
    await repo.updateItem(ShoppingItem(id: 'nada', listId: 'x', name: 'N', createdAt: DateTime(2026)));
    await repo.deleteItem('nada');
    expect(await store.all('shopping_items'), isEmpty);
    expect(store.pendingNow, 0);
  });

  test('finishShopping apaga só os marcados da lista e conta', () async {
    final l = await repo.ensureDefaultList();
    final outra = ShoppingList(id: 'o', name: 'Outra', position: 1);
    await repo.upsertList(outra);
    await repo.addItem(listId: l.id, name: 'A');
    await repo.addItem(listId: l.id, name: 'B');
    await repo.addItem(listId: l.id, name: 'C');
    await repo.addItem(listId: outra.id, name: 'D');
    final all = await items();
    await repo.setChecked(all[0].id, true);
    await repo.setChecked(all[1].id, true);
    await repo.setChecked(all[3].id, true);
    expect(await repo.finishShopping(l.id), 2);
    expect((await items()).map((i) => i.name), ['C', 'D']);
    expect(await repo.finishShopping(l.id), 0);
  });

  test('apagar a lista leva os itens junto; nome de lista é único sem caixa', () async {
    final l = await repo.ensureDefaultList();
    await repo.addItem(listId: l.id, name: 'A');
    await expectLater(
      repo.upsertList(const ShoppingList(id: 'x', name: 'mercado')),
      throwsA(isA<RepositoryException>().having((e) => e.duplicate, 'duplicate', true)),
    );
    await repo.deleteList(l.id);
    expect(await items(), isEmpty);
    expect(await repo.watchLists().first, isEmpty);
  });

  test('renomear a própria lista não conta como duplicada', () async {
    final l = await repo.ensureDefaultList();
    await repo.upsertList(l.copyWith(name: 'MERCADO'));
    expect((await repo.watchLists().first).single.name, 'MERCADO');
  });

  test('apagar a lista tira da fila os itens que nem foram enviados', () async {
    final l = await repo.ensureDefaultList();
    await repo.addItem(listId: l.id, name: 'A');
    await repo.deleteList(l.id);
    final queue = store.pendingOutbox();
    expect(queue.where((e) => e.op == OutboxOp.upsert), isEmpty);
  });
}
