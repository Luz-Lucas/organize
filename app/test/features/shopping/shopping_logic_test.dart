import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/domain/shopping.dart';

final _t0 = DateTime(2026, 10, 19, 9);

ShoppingItem _item(String id, String name, ShopSection s,
        {bool checked = false, int position = 0, DateTime? at, String listId = 'l1'}) =>
    ShoppingItem(
      id: id,
      listId: listId,
      name: name,
      section: s,
      checked: checked,
      position: position,
      createdAt: at ?? _t0,
    );

FrequentItem _freq(String name, ShopSection s, int times, [DateTime? at]) =>
    FrequentItem(name: name, section: s, times: times, lastAddedAt: at ?? _t0);

void main() {
  group('ShopSection', () {
    test('ordem padrão e rótulos', () {
      expect(ShopSection.values.map((s) => s.name), [
        'hortifruti', 'padaria', 'acougue', 'frios', 'mercearia',
        'bebidas', 'limpeza', 'higiene', 'congelados', 'outros',
      ]);
      expect(ShopSection.hortifruti.label, 'Hortifrúti');
      expect(ShopSection.frios.label, 'Frios e laticínios');
      expect(ShopSection.acougue.label, 'Açougue');
    });

    test('fromName aceita nulo e desconhecido como outros', () {
      expect(ShopSection.fromName('padaria'), ShopSection.padaria);
      expect(ShopSection.fromName(null), ShopSection.outros);
      expect(ShopSection.fromName('xyz'), ShopSection.outros);
    });
  });

  group('modelos', () {
    test('ShoppingList fromMap/toMap com ordem de seções', () {
      final l = ShoppingList.fromMap({
        'id': 'l1', 'name': 'Mercado', 'position': 2, 'section_order': ['padaria', 'hortifruti'],
      });
      expect(l.sectionOrder, [ShopSection.padaria, ShopSection.hortifruti]);
      expect(l.toMap()['section_order'], ['padaria', 'hortifruti']);
      final sem = ShoppingList.fromMap({'id': 'l2', 'name': 'Farmácia'});
      expect(sem.sectionOrder, isNull);
      expect(sem.toMap()['section_order'], isNull);
    });

    test('ShoppingItem fromMap tolera seção nula e toMap só manda colunas da tabela', () {
      final i = ShoppingItem.fromMap({
        'id': 'i1', 'list_id': 'l1', 'name': 'Leite', 'quantity': null, 'section': null,
        'checked': false, 'position': 0, 'created_at': '2026-10-19T12:00:00Z',
      });
      expect(i.section, ShopSection.outros);
      expect(i.quantity, '');
      expect(i.toMap().keys.toSet(), {'id', 'list_id', 'name', 'quantity', 'section', 'checked', 'position'});
    });

    test('FrequentItem fromMap', () {
      final f = FrequentItem.fromMap({
        'name': 'Leite', 'section': 'frios', 'times': 3, 'last_added_at': '2026-10-19T12:00:00Z',
      });
      expect(f.section, ShopSection.frios);
      expect(f.times, 3);
    });
  });

  group('foldName / findDuplicate', () {
    test('compara sem acento, caixa e espaços', () {
      expect(foldName('  Pão   Francês '), 'pao frances');
    });

    test('só considera itens não marcados da mesma lista', () {
      final items = [
        _item('1', 'Leite', ShopSection.frios),
        _item('2', 'Pão', ShopSection.padaria, checked: true),
        _item('3', 'Arroz', ShopSection.mercearia, listId: 'outra'),
      ];
      expect(findDuplicate('  leite ', 'l1', items)?.id, '1');
      expect(findDuplicate('pao', 'l1', items), isNull);
      expect(findDuplicate('arroz', 'l1', items), isNull);
    });
  });

  group('groupBySection', () {
    final items = [
      _item('1', 'Leite', ShopSection.frios, position: 1),
      _item('2', 'Banana', ShopSection.hortifruti),
      _item('3', 'Queijo', ShopSection.frios, position: 0),
      _item('4', 'Pão', ShopSection.padaria),
    ];

    test('ordem padrão, só grupos com itens, itens por posição', () {
      final g = groupBySection(items, null);
      expect(g.map((e) => e.$1), [ShopSection.hortifruti, ShopSection.padaria, ShopSection.frios]);
      expect(g.last.$2.map((i) => i.name), ['Queijo', 'Leite']);
    });

    test('ordem personalizada; seções que faltam na ordem vão no fim, na ordem padrão', () {
      final g = groupBySection(items, [ShopSection.frios, ShopSection.padaria]);
      expect(g.map((e) => e.$1), [ShopSection.frios, ShopSection.padaria, ShopSection.hortifruti]);
    });

    test('lista vazia dá nenhum grupo', () {
      expect(groupBySection(const [], null), isEmpty);
    });
  });

  group('buyAgain', () {
    test('exclui o que está na lista não marcado, ordena por vezes e recência, limita', () {
      final f = [
        _freq('Leite', ShopSection.frios, 5),
        _freq('Pão', ShopSection.padaria, 5, _t0.add(const Duration(days: 1))),
        _freq('Arroz', ShopSection.mercearia, 2),
        _freq('Café', ShopSection.bebidas, 9),
      ];
      final inList = [
        _item('1', 'leite', ShopSection.frios),
        _item('2', 'Arroz', ShopSection.mercearia, checked: true),
      ];
      expect(buyAgain(f, inList).map((e) => e.name), ['Café', 'Pão', 'Arroz']);
      expect(buyAgain(f, inList, max: 2).map((e) => e.name), ['Café', 'Pão']);
    });
  });

  group('suggest', () {
    final f = [
      _freq('Leite', ShopSection.frios, 5),
      _freq('Leite condensado', ShopSection.mercearia, 1),
      _freq('Pão de leite', ShopSection.padaria, 9),
      _freq('Água sanitária', ShopSection.limpeza, 2),
    ];

    test('prefixo antes de contém, sem acento', () {
      expect(suggest('lei', f).map((e) => e.name), ['Leite', 'Leite condensado', 'Pão de leite']);
      expect(suggest('agua', f).map((e) => e.name), ['Água sanitária']);
    });

    test('vazio não sugere e respeita o máximo', () {
      expect(suggest('  ', f), isEmpty);
      expect(suggest('l', f, max: 2), hasLength(2));
    });
  });
}
