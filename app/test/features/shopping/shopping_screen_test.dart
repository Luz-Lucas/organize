import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:organizacional/app/providers.dart';
import 'package:organizacional/data/shopping_repository.dart';
import 'package:organizacional/domain/shopping.dart';
import 'package:organizacional/features/shopping/shopping_card.dart';
import 'package:organizacional/features/shopping/shopping_providers.dart';
import 'package:organizacional/features/shopping/shopping_screen.dart';
import 'package:organizacional/ui/org_theme.dart';

Future<void> _pump(
  WidgetTester tester,
  ShoppingRepository repo, {
  Widget? home,
  Size size = const Size(800, 900),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => home ?? const ShoppingScreen()),
    GoRoute(path: '/compras', builder: (_, _) => const ShoppingScreen()),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      shoppingRepositoryProvider.overrideWithValue(repo),
      clockProvider.overrideWithValue(() => DateTime(2026, 10, 19, 10)),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      theme: buildOrgTheme(orgThemes.first, googleFonts: false),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<ShoppingList> _list(ShoppingRepository repo) => repo.ensureDefaultList();

Future<void> _add(WidgetTester tester, String name, {String qty = ''}) async {
  await tester.enterText(find.byKey(const Key('shop-add-field')), name);
  if (qty.isNotEmpty) await tester.enterText(find.byKey(const Key('shop-qty-field')), qty);
  await tester.tap(find.byKey(const Key('shop-add-button')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('primeira abertura cria a lista Mercado sozinha', (tester) async {
    final repo = MemoryShoppingRepository();
    await _pump(tester, repo);
    final lists = await repo.watchLists().first;
    expect(lists.map((l) => l.name), ['Mercado']);
    expect(find.text('Mercado'), findsWidgets);
    expect(find.textContaining('vazia'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('adiciona item com quantidade', (tester) async {
    final repo = MemoryShoppingRepository();
    await _pump(tester, repo);
    await _add(tester, 'Leite', qty: '2 L');
    expect(find.text('Leite'), findsOneWidget);
    expect(find.text('2 L'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('shop-add-field'))).controller!.text, isEmpty);
  });

  testWidgets('item sem seção cai em Outros e aparece agrupado', (tester) async {
    final repo = MemoryShoppingRepository();
    await _pump(tester, repo);
    await _add(tester, 'Coisa');
    expect(find.text('Outros'), findsOneWidget);
  });

  testWidgets('duplicado não repete e avisa', (tester) async {
    final repo = MemoryShoppingRepository();
    await _pump(tester, repo);
    await _add(tester, 'Leite');
    await _add(tester, ' leite ');
    expect(find.text('Já está na lista'), findsOneWidget);
    expect((await repo.watchItems().first), hasLength(1));
  });

  testWidgets('sugere itens frequentes ao digitar e um toque adiciona', (tester) async {
    final repo = MemoryShoppingRepository();
    final l = await _list(repo);
    await repo.addItem(listId: l.id, name: 'Leite', section: ShopSection.frios);
    await repo.addItem(listId: l.id, name: 'Leite condensado');
    for (final i in await repo.watchItems().first) {
      await repo.setChecked(i.id, true);
    }
    await repo.finishShopping(l.id);
    await _pump(tester, repo);
    await tester.enterText(find.byKey(const Key('shop-add-field')), 'lei');
    await tester.pump();
    expect(find.byKey(const Key('shop-suggest-leite')), findsOneWidget);
    expect(find.byKey(const Key('shop-suggest-leite condensado')), findsOneWidget);
    await tester.tap(find.byKey(const Key('shop-suggest-leite')));
    await tester.pumpAndSettle();
    final items = await repo.watchItems().first;
    expect(items.single.name, 'Leite');
    expect(items.single.section, ShopSection.frios);
  });

  testWidgets('marcar leva para No carrinho e finalizar apaga os marcados', (tester) async {
    final repo = MemoryShoppingRepository();
    await _pump(tester, repo);
    await _add(tester, 'Leite');
    await _add(tester, 'Pão');
    expect(find.textContaining('No carrinho'), findsNothing);
    final leite = (await repo.watchItems().first).firstWhere((i) => i.name == 'Leite');
    await tester.tap(find.byKey(Key('shop-check-${leite.id}')));
    await tester.pumpAndSettle();
    expect(find.textContaining('No carrinho'), findsOneWidget);
    final cart = tester.getTopLeft(find.textContaining('No carrinho')).dy;
    final pao = (await repo.watchItems().first).firstWhere((i) => i.name == 'Pão');
    expect(tester.getTopLeft(find.byKey(Key('shop-item-${pao.id}'))).dy, lessThan(cart));
    expect(tester.getTopLeft(find.byKey(Key('shop-item-${leite.id}'))).dy, greaterThan(cart));

    await tester.tap(find.byKey(const Key('shop-finish')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Apagar 1'), findsOneWidget);
    await tester.tap(find.byKey(const Key('shop-finish-confirm')));
    await tester.pumpAndSettle();
    expect((await repo.watchItems().first).map((i) => i.name), ['Pão']);
    expect(find.textContaining('No carrinho'), findsNothing);
  });

  testWidgets('desmarcar traz de volta para a lista', (tester) async {
    final repo = MemoryShoppingRepository();
    final l = await _list(repo);
    await repo.addItem(listId: l.id, name: 'Leite');
    final id = (await repo.watchItems().first).single.id;
    await repo.setChecked(id, true);
    await _pump(tester, repo);
    expect(find.textContaining('No carrinho'), findsOneWidget);
    await tester.tap(find.byKey(Key('shop-check-$id')));
    await tester.pumpAndSettle();
    expect(find.textContaining('No carrinho'), findsNothing);
  });

  testWidgets('corrigir a seção move o item e o app lembra para o próximo', (tester) async {
    final repo = MemoryShoppingRepository();
    await _pump(tester, repo);
    await _add(tester, 'Tapioca');
    await tester.tap(find.text('Tapioca'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shop-section-mercearia')));
    await tester.enterText(find.byKey(const Key('shop-edit-qty')), '500 g');
    await tester.tap(find.byKey(const Key('shop-edit-save')));
    await tester.pumpAndSettle();
    expect(find.text('Mercearia'), findsOneWidget);
    expect(find.text('Outros'), findsNothing);
    expect(find.text('500 g'), findsOneWidget);
    // o banco/memória lembram a seção: depois de finalizar, "tapioca" volta em Mercearia
    final id = (await repo.watchItems().first).single.id;
    await repo.setChecked(id, true);
    await repo.finishShopping((await repo.watchLists().first).single.id);
    await _add(tester, 'tapioca');
    expect((await repo.watchItems().first).single.section, ShopSection.mercearia);
  });

  testWidgets('Comprar de novo recoloca o frequente', (tester) async {
    final repo = MemoryShoppingRepository();
    final l = await _list(repo);
    await repo.addItem(listId: l.id, name: 'Café', section: ShopSection.bebidas);
    await repo.setChecked((await repo.watchItems().first).single.id, true);
    await repo.finishShopping(l.id);
    await _pump(tester, repo);
    expect(find.text('Comprar de novo'), findsOneWidget);
    await tester.tap(find.byKey(const Key('shop-again-cafe')));
    await tester.pumpAndSettle();
    expect((await repo.watchItems().first).single.name, 'Café');
    expect(find.text('Comprar de novo'), findsNothing);
  });

  testWidgets('editar: apagar remove o item', (tester) async {
    final repo = MemoryShoppingRepository();
    await _pump(tester, repo);
    await _add(tester, 'Leite');
    await tester.tap(find.text('Leite'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shop-edit-delete')));
    await tester.pumpAndSettle();
    expect(await repo.watchItems().first, isEmpty);
  });

  testWidgets('várias listas: criar, alternar e itens separados', (tester) async {
    final repo = MemoryShoppingRepository();
    await _pump(tester, repo);
    await _add(tester, 'Leite');
    await tester.tap(find.byKey(const Key('shop-new-list')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('shop-list-name-field')), 'Farmácia');
    await tester.tap(find.byKey(const Key('shop-list-name-ok')));
    await tester.pumpAndSettle();
    final lists = await repo.watchLists().first;
    expect(lists.map((l) => l.name), ['Mercado', 'Farmácia']);
    // a nova lista abre selecionada e vazia (Leite só aparece como sugestão de "Comprar de novo")
    final leite = (await repo.watchItems().first).single;
    expect(find.byKey(Key('shop-item-${leite.id}')), findsNothing);
    await _add(tester, 'Dipirona');
    final dip = (await repo.watchItems().first).firstWhere((i) => i.name == 'Dipirona');
    await tester.tap(find.byKey(Key('shop-list-${lists.first.id}')));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('shop-item-${leite.id}')), findsOneWidget);
    expect(find.byKey(Key('shop-item-${dip.id}')), findsNothing);
  });

  testWidgets('lista duplicada avisa', (tester) async {
    final repo = MemoryShoppingRepository();
    await _pump(tester, repo);
    await tester.tap(find.byKey(const Key('shop-new-list')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('shop-list-name-field')), 'mercado');
    await tester.tap(find.byKey(const Key('shop-list-name-ok')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Já existe uma lista'), findsOneWidget);
    expect((await repo.watchLists().first), hasLength(1));
  });

  testWidgets('ordem das seções arrastável e gravada na lista', (tester) async {
    final repo = MemoryShoppingRepository();
    await _pump(tester, repo);
    await tester.tap(find.byKey(const Key('shop-order')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shop-order-list')), findsOneWidget);
    // arrasta "Hortifrúti" (1º) para depois de "Padaria"
    await tester.drag(find.byKey(const Key('shop-order-handle-hortifruti')), const Offset(0, 130));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shop-order-save')));
    await tester.pumpAndSettle();
    final order = (await repo.watchLists().first).single.sectionOrder!;
    expect(order.first, ShopSection.padaria);
    expect(order.indexOf(ShopSection.hortifruti), 1);
    expect(order, hasLength(ShopSection.values.length));
  });

  testWidgets('segue a ordem personalizada da lista', (tester) async {
    final repo = MemoryShoppingRepository();
    final l = await _list(repo);
    await repo.upsertList(l.copyWith(sectionOrder: [ShopSection.padaria, ShopSection.hortifruti]));
    await repo.addItem(listId: l.id, name: 'Banana', section: ShopSection.hortifruti);
    await repo.addItem(listId: l.id, name: 'Pão', section: ShopSection.padaria);
    await _pump(tester, repo);
    expect(tester.getTopLeft(find.text('Padaria')).dy, lessThan(tester.getTopLeft(find.text('Hortifrúti')).dy));
  });

  testWidgets('queda de conexão ao adicionar avisa e mantém o texto', (tester) async {
    final repo = MemoryShoppingRepository();
    await _pump(tester, repo);
    repo.failWrites = true;
    await _add(tester, 'Leite');
    expect(find.textContaining('Não foi possível adicionar'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('shop-add-field'))).controller!.text, 'Leite');
  });

  testWidgets('360 dp com texto grande e muitos itens sem overflow', (tester) async {
    final repo = MemoryShoppingRepository();
    final l = await _list(repo);
    for (final s in ShopSection.values) {
      await repo.addItem(
          listId: l.id,
          name: 'Um item com nome bem comprido de ${s.label} para forçar quebra de linha',
          quantity: '2 pacotes grandes',
          section: s);
    }
    await repo.setChecked((await repo.watchItems().first).first.id, true);
    await _pump(tester, repo, size: const Size(360, 740), textScale: 2);
    await tester.enterText(find.byKey(const Key('shop-add-field')), 'um');
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('shop-order')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('shop-order-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Um item com nome').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  group('ShoppingCard', () {
    testWidgets('mostra a contagem e os 3 primeiros itens', (tester) async {
      final repo = MemoryShoppingRepository();
      final l = await _list(repo);
      for (final n in ['Leite', 'Pão', 'Banana', 'Arroz']) {
        await repo.addItem(listId: l.id, name: n, quantity: n == 'Leite' ? '2 L' : '');
      }
      await repo.setChecked((await repo.watchItems().first).last.id, true);
      await _pump(tester, repo, home: const Scaffold(body: ShoppingCard()), size: const Size(360, 740));
      expect(find.byKey(const Key('shopping-card')), findsOneWidget);
      expect(find.text('Mercado — 3 itens'), findsOneWidget);
      expect(find.textContaining('Leite'), findsOneWidget);
      expect(find.text('Arroz'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('vazio e botão Abrir leva a /compras', (tester) async {
      final repo = MemoryShoppingRepository();
      await _pump(tester, repo, home: const Scaffold(body: ShoppingCard()));
      expect(find.text('Mercado — lista vazia'), findsOneWidget);
      await tester.tap(find.byKey(const Key('shopping-open')));
      await tester.pumpAndSettle();
      expect(find.byType(ShoppingScreen), findsOneWidget);
    });
  });
}
