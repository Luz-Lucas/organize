import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/shopping_repository.dart';
import 'package:organizacional/domain/shopping.dart';
import 'package:organizacional/widgets/widget_shop_action.dart';

Future<(MemoryShoppingRepository, String)> _repoWithItem() async {
  final repo = MemoryShoppingRepository();
  final list = await repo.ensureDefaultList();
  await repo.addItem(
    listId: list.id,
    name: 'Arroz',
    section: ShopSection.mercearia,
  );
  final item = (await repo.watchItems().first).single;
  return (repo, item.id);
}

void main() {
  test('shopCheckUri e shopCheckIdFromUri são inversos', () {
    final uri = shopCheckUri('abc-123');
    expect(uri.toString(), 'organizacional://mercado/check?id=abc-123');
    expect(shopCheckIdFromUri(uri), 'abc-123');
  });

  test('outros links não são toque de item', () {
    expect(shopCheckIdFromUri(null), isNull);
    expect(shopCheckIdFromUri(Uri.parse('organizacional://compras')), isNull);
    expect(
      shopCheckIdFromUri(Uri.parse('organizacional://mercado/check')),
      isNull,
    );
    expect(
      shopCheckIdFromUri(Uri.parse('organizacional://mercado/check?id=')),
      isNull,
    );
    expect(shopCheckIdFromUri(Uri.parse('https://mercado/check?id=x')), isNull);
  });

  test('tocar no item marca como comprado no repositório', () async {
    final (repo, id) = await _repoWithItem();
    final ok = await handleWidgetInteraction(
      shopCheckUri(id),
      () async => repo,
    );
    expect(ok, isTrue);
    expect((await repo.watchItems().first).single.checked, isTrue);
  });

  test('sem sessão (repositório nulo) não faz nada e não trava', () async {
    final ok = await handleWidgetInteraction(
      shopCheckUri('x'),
      () async => null,
    );
    expect(ok, isFalse);
  });

  test('sem rede: a falha é engolida e devolve false', () async {
    final (repo, id) = await _repoWithItem();
    repo.failWrites = true;
    final ok = await handleWidgetInteraction(
      shopCheckUri(id),
      () async => repo,
    );
    expect(ok, isFalse);
    expect((await repo.watchItems().first).single.checked, isFalse);
  });

  test('erro ao obter o cliente também é engolido', () async {
    final ok = await handleWidgetInteraction(
      shopCheckUri('x'),
      () async => throw Exception('sem plugin'),
    );
    expect(ok, isFalse);
  });

  test('uri que não é de marcar item nem consulta o repositório', () async {
    var called = false;
    final ok = await handleWidgetInteraction(
      Uri.parse('organizacional://agenda'),
      () async {
        called = true;
        return null;
      },
    );
    expect(ok, isFalse);
    expect(called, isFalse);
  });
}
