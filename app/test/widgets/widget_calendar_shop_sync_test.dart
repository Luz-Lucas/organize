import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/app/providers.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/data/memory_settings_repository.dart';
import 'package:organizacional/data/shopping_repository.dart';
import 'package:organizacional/domain/calendar_event.dart';
import 'package:organizacional/domain/event_tag.dart';
import 'package:organizacional/domain/shopping.dart';
import 'package:organizacional/domain/task_item.dart';
import 'package:organizacional/features/shopping/shopping_providers.dart';
import 'package:organizacional/widgets/widget_background.dart';
import 'package:organizacional/widgets/widget_sync.dart';

import 'widget_sync_test.dart' show FakeSink;

final _now = DateTime(2026, 10, 20, 12);

class _Source implements WidgetDataSource {
  _Source({this.failShopping = false, this.failEvents = false});
  final bool failShopping;
  final bool failEvents;
  final eventRanges = <(DateTime, DateTime)>[];

  @override
  Future<List<CalendarEvent>> events(DateTime from, DateTime to) async {
    eventRanges.add((from, to));
    if (failEvents) throw Exception('sem rede');
    return [
      CalendarEvent(id: 'hoje', title: 'Hoje', startsAt: DateTime(2026, 10, 20, 9), endsAt: DateTime(2026, 10, 20, 10)),
      CalendarEvent(id: 'mes', title: 'Mês que vem', startsAt: DateTime(2026, 11, 25, 9), endsAt: DateTime(2026, 11, 25, 10)),
    ];
  }

  @override
  Future<List<TaskItem>> openTasks() async => const [];

  @override
  Future<String> themeId() async => 'violeta';

  @override
  Future<List<EventTag>> tags() async => const [];

  @override
  Future<List<ShoppingList>> shoppingLists() async {
    if (failShopping) throw Exception('sem rede');
    return const [ShoppingList(id: 'l1', name: 'Mercado')];
  }

  @override
  Future<List<ShoppingItem>> shoppingItems() async {
    if (failShopping) throw Exception('sem rede');
    return [
      ShoppingItem(id: 'i1', listId: 'l1', name: 'Arroz', section: ShopSection.mercearia, createdAt: DateTime(2026, 10, 1)),
    ];
  }
}

void main() {
  test('fetchSnapshot busca uma vez a janela do calendário e grava calendário e mercado', () async {
    final src = _Source();
    final s = await fetchSnapshot(src, _now);
    expect(s['w_state'], 'ok');
    expect(src.eventRanges, [(DateTime(2026, 9, 1), DateTime(2026, 12, 1))]);
    expect((jsonDecode(s['w_cal_events']!) as List).map((e) => e['id']), ['hoje', 'mes']);
    // O w_events (14 dias) continua filtrado pela janela própria.
    expect((jsonDecode(s['w_events']!) as List).map((e) => e['id']), ['hoje']);
    final shop = jsonDecode(s['w_shop']!) as Map<String, dynamic>;
    expect(shop['listName'], 'Mercado');
    expect(((shop['sections'] as List).single['items'] as List).single['name'], 'Arroz');
  });

  test('falha só no mercado não derruba o resumo: w_shop some e o último fica', () async {
    final s = await fetchSnapshot(_Source(failShopping: true), _now);
    expect(s['w_state'], 'ok');
    expect(s.containsKey('w_shop'), isFalse);
    expect(s.containsKey('w_cal_events'), isTrue);
  });

  test('falha nos eventos continua devolvendo só o erro', () async {
    expect(await fetchSnapshot(_Source(failEvents: true), _now), {'w_state': 'error'});
  });

  testWidgets('com o app aberto: evento do mês seguinte e item de compras vão para o resumo', (tester) async {
    final repo = MemoryRepository();
    final shop = MemoryShoppingRepository();
    final sink = FakeSink();
    final container = ProviderContainer(overrides: [
      repositoryProvider.overrideWithValue(repo),
      shoppingRepositoryProvider.overrideWithValue(shop),
      settingsRepositoryProvider.overrideWithValue(MemorySettingsRepository()),
      clockProvider.overrideWithValue(() => _now),
      widgetSinkProvider.overrideWithValue(sink),
    ]);
    addTearDown(container.dispose);
    container.listen(widgetSyncProvider, (_, _) {});
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    final list = await shop.ensureDefaultList();
    await shop.addItem(listId: list.id, name: 'Leite', section: ShopSection.frios);
    await repo.upsertEvent(CalendarEvent(
        id: 'nov', title: 'Prova', startsAt: DateTime(2026, 11, 25, 9), endsAt: DateTime(2026, 11, 25, 10)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    final last = sink.saved.last;
    expect((jsonDecode(last['w_cal_events']!) as List).map((e) => e['id']), ['nov']);
    final w = jsonDecode(last['w_shop']!) as Map<String, dynamic>;
    expect(w['listId'], list.id);
    expect(((w['sections'] as List).single['items'] as List).single['name'], 'Leite');
    expect(widgetSyncDebounce, const Duration(seconds: 2));
  });

  testWidgets('sem repositório de compras o resto do resumo sai igual (sem w_shop)', (tester) async {
    final sink = FakeSink();
    final container = ProviderContainer(overrides: [
      repositoryProvider.overrideWithValue(MemoryRepository()),
      settingsRepositoryProvider.overrideWithValue(MemorySettingsRepository()),
      clockProvider.overrideWithValue(() => _now),
      widgetSinkProvider.overrideWithValue(sink),
    ]);
    addTearDown(container.dispose);
    container.listen(widgetSyncProvider, (_, _) {});
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    expect(sink.saved, isNotEmpty);
    expect(sink.saved.last.containsKey('w_shop'), isFalse);
    expect(sink.saved.last['w_cal_events'], '[]');
  });
}
