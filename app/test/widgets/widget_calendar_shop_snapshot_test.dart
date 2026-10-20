import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/domain/calendar_event.dart';
import 'package:organizacional/domain/event_tag.dart';
import 'package:organizacional/domain/shopping.dart';
import 'package:organizacional/widgets/widget_snapshot.dart';

final _now = DateTime(2026, 10, 20, 12);

CalendarEvent _ev(String id, DateTime s, DateTime e, {bool allDay = false, String? tagId, String? location}) =>
    CalendarEvent(id: id, title: 'Ev $id', startsAt: s, endsAt: e, allDay: allDay, tagId: tagId, location: location);

ShoppingItem _it(String id, String name, ShopSection sec,
        {String listId = 'l1', bool checked = false, String q = '', int pos = 0}) =>
    ShoppingItem(
        id: id,
        listId: listId,
        name: name,
        quantity: q,
        section: sec,
        checked: checked,
        position: pos,
        createdAt: DateTime(2026, 10, 1));

Map<String, String> _build({
  Iterable<CalendarEvent>? cal,
  Iterable<ShoppingList>? lists,
  Iterable<ShoppingItem>? items,
  String state = 'ok',
  List<EventTag> tags = const [],
}) =>
    buildWidgetSnapshot(
        now: _now,
        events: const [],
        tasks: const [],
        themeId: 'violeta',
        state: state,
        tags: tags,
        calendarEvents: cal,
        shoppingLists: lists,
        shoppingItems: items);

void main() {
  group('janela do calendário', () {
    test('do 1º dia do mês anterior ao fim do mês seguinte', () {
      expect(calendarWindowStart(DateTime(2026, 10, 20)), DateTime(2026, 9, 1));
      expect(calendarWindowEnd(DateTime(2026, 10, 20)), DateTime(2026, 12, 1));
    });

    test('vira o ano', () {
      expect(calendarWindowStart(DateTime(2026, 1, 5)), DateTime(2025, 12, 1));
      expect(calendarWindowEnd(DateTime(2026, 12, 5)), DateTime(2027, 2, 1));
    });
  });

  group('w_cal_events / w_cal_range', () {
    test('compacta os eventos da janela, com cor da etiqueta', () {
      final s = _build(
        cal: [
          _ev('a', DateTime(2026, 10, 22, 9), DateTime(2026, 10, 22, 10), tagId: 't1', location: 'sala 3'),
          _ev('dentro', DateTime(2026, 9, 3), DateTime(2026, 9, 3, 1)),
          _ev('fora', DateTime(2026, 8, 31, 10), DateTime(2026, 8, 31, 11)),
          _ev('fora2', DateTime(2026, 12, 1, 0), DateTime(2026, 12, 1, 1)),
          _ev('dia', DateTime(2026, 11, 30), DateTime(2026, 12, 1), allDay: true),
        ],
        tags: const [EventTag(id: 't1', name: 'Aula', color: '#3e63dd', role: EventTagRole.main)],
      );
      final list = (jsonDecode(s['w_cal_events']!) as List).cast<Map<String, dynamic>>();
      expect(list.map((e) => e['id']), ['dentro', 'a', 'dia']);
      final a = list[1];
      expect(a.keys.toSet(), {'id', 'title', 'start', 'end', 'allDay', 'tagColor'});
      expect(a['start'], DateTime(2026, 10, 22, 9).millisecondsSinceEpoch);
      expect(a['end'], DateTime(2026, 10, 22, 10).millisecondsSinceEpoch);
      expect(a['allDay'], false);
      expect(a['tagColor'], '#3E63DD');
      expect(list[0]['tagColor'], isNull);
      expect(list[2]['allDay'], true);
    });

    test('evento que atravessa a virada da janela entra', () {
      final s = _build(cal: [_ev('x', DateTime(2026, 8, 31, 22), DateTime(2026, 9, 1, 2))]);
      expect((jsonDecode(s['w_cal_events']!) as List), hasLength(1));
    });

    test('w_cal_range guarda from/to em millis', () {
      final s = _build(cal: const []);
      final r = jsonDecode(s['w_cal_range']!) as Map<String, dynamic>;
      expect(r['from'], DateTime(2026, 9, 1).millisecondsSinceEpoch);
      expect(r['to'], DateTime(2026, 12, 1).millisecondsSinceEpoch);
    });

    test('sem dados (null) as chaves não são escritas, preservando o último resumo', () {
      final s = _build();
      expect(s.containsKey('w_cal_events'), isFalse);
      expect(s.containsKey('w_cal_range'), isFalse);
    });

    test('signed_out esvazia o calendário', () {
      final s = _build(state: 'signed_out', cal: [_ev('a', DateTime(2026, 10, 22), DateTime(2026, 10, 22, 1))]);
      expect(s['w_cal_events'], '[]');
      expect(s.containsKey('w_cal_range'), isTrue);
    });
  });

  group('w_shop', () {
    final lists = [
      const ShoppingList(id: 'l2', name: 'Feira', position: 1),
      const ShoppingList(id: 'l1', name: 'Mercado', position: 0),
    ];

    Map<String, dynamic> shop(Map<String, String> s) => jsonDecode(s['w_shop']!) as Map<String, dynamic>;

    test('primeira lista por position, só itens não marcados, agrupados na ordem padrão', () {
      final s = _build(lists: lists, items: [
        _it('1', 'Arroz', ShopSection.mercearia, q: '2 kg'),
        _it('2', 'Maçã', ShopSection.hortifruti, pos: 1),
        _it('3', 'Alface', ShopSection.hortifruti, pos: 0),
        _it('4', 'Leite', ShopSection.frios, checked: true),
        _it('5', 'Outra lista', ShopSection.padaria, listId: 'l2'),
      ]);
      final w = shop(s);
      expect(w['listId'], 'l1');
      expect(w['listName'], 'Mercado');
      final secs = (w['sections'] as List).cast<Map<String, dynamic>>();
      expect(secs.map((e) => e['name']), ['hortifruti', 'mercearia']);
      expect(secs[0]['label'], 'Hortifrúti');
      expect((secs[0]['items'] as List).map((i) => i['id']), ['3', '2']);
      expect(secs[1]['items'], [
        {'id': '1', 'name': 'Arroz', 'quantity': '2 kg'}
      ]);
    });

    test('respeita section_order da lista', () {
      final s = _build(
        lists: [
          const ShoppingList(
              id: 'l1', name: 'Mercado', sectionOrder: [ShopSection.mercearia, ShopSection.hortifruti]),
        ],
        items: [_it('1', 'Arroz', ShopSection.mercearia), _it('2', 'Maçã', ShopSection.hortifruti)],
      );
      expect((shop(s)['sections'] as List).map((e) => e['name']), ['mercearia', 'hortifruti']);
    });

    test('nenhuma lista (nunca abriu Compras) vira lista vazia, sem erro', () {
      final s = _build(lists: const [], items: const []);
      final w = shop(s);
      expect(w['listId'], isNull);
      expect(w['sections'], isEmpty);
    });

    test('lista sem itens pendentes', () {
      final s = _build(lists: lists, items: [_it('4', 'Leite', ShopSection.frios, checked: true)]);
      expect(shop(s)['sections'], isEmpty);
      expect(shop(s)['listName'], 'Mercado');
    });

    test('sem dados (null) a chave não é escrita', () {
      expect(_build().containsKey('w_shop'), isFalse);
      expect(_build(lists: lists).containsKey('w_shop'), isFalse);
    });

    test('signed_out esvazia a lista', () {
      final s = _build(state: 'signed_out', lists: lists, items: [_it('1', 'Arroz', ShopSection.mercearia)]);
      expect(shop(s)['sections'], isEmpty);
    });
  });
}
