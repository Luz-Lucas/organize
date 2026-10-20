import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/app/providers.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/data/memory_settings_repository.dart';
import 'package:organizacional/domain/calendar_event.dart';
import 'package:organizacional/domain/event_tag.dart';
import 'package:organizacional/domain/shopping.dart';
import 'package:organizacional/domain/task_item.dart';
import 'package:organizacional/widgets/widget_background.dart';
import 'package:organizacional/widgets/widget_sink.dart';
import 'package:organizacional/widgets/widget_sync.dart';

class FakeSink implements WidgetSink {
  final saved = <Map<String, String>>[];
  int refreshes = 0;
  @override
  Future<void> save(Map<String, String> data) async => saved.add(data);
  @override
  Future<void> refresh() async => refreshes++;
  @override
  Future<String?> read(String key) async => stored[key];
  final stored = <String, String>{};
}

class FakeSource implements WidgetDataSource {
  FakeSource({this.fail = false});
  final bool fail;
  @override
  Future<List<CalendarEvent>> events(DateTime from, DateTime to) async {
    if (fail) throw Exception('sem rede');
    return [
      CalendarEvent(
          id: 'e1', title: 'M02', startsAt: DateTime(2026, 10, 11, 14), endsAt: DateTime(2026, 10, 11, 15)),
    ];
  }

  @override
  Future<List<TaskItem>> openTasks() async {
    if (fail) throw Exception('sem rede');
    return [const TaskItem(id: 't1', title: 'Estudar')];
  }

  @override
  Future<String> themeId() async => 'safira';

  @override
  Future<List<EventTag>> tags() async => const [];

  @override
  Future<List<ShoppingList>> shoppingLists() async => const [];

  @override
  Future<List<ShoppingItem>> shoppingItems() async => const [];
}

void main() {
  final now = DateTime(2026, 10, 11, 12);

  testWidgets('inserir tarefa grava w_tasks após o debounce', (tester) async {
    final repo = MemoryRepository();
    final sink = FakeSink();
    final container = ProviderContainer(overrides: [
      repositoryProvider.overrideWithValue(repo),
      settingsRepositoryProvider.overrideWithValue(MemorySettingsRepository()),
      clockProvider.overrideWithValue(() => now),
      widgetSinkProvider.overrideWithValue(sink),
    ]);
    addTearDown(container.dispose);
    container.listen(widgetSyncProvider, (_, _) {});
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    final before = sink.saved.length;

    await repo.upsertTask(const TaskItem(id: 'x', title: 'Nova tarefa'));
    await tester.pump();
    expect(sink.saved.length, before, reason: 'debounce ainda não venceu');
    await tester.pump(const Duration(seconds: 3));

    expect(sink.saved.length, before + 1);
    final tasks = jsonDecode(sink.saved.last['w_tasks']!) as List;
    expect(tasks.single['title'], 'Nova tarefa');
    expect(sink.refreshes, sink.saved.length);
  });

  testWidgets('a transparência salva no aparelho vai junto do resumo (w_bg_alpha)', (tester) async {
    final sink = FakeSink()..stored['w_bg_pct'] = '50';
    final container = ProviderContainer(overrides: [
      repositoryProvider.overrideWithValue(MemoryRepository()),
      settingsRepositoryProvider.overrideWithValue(MemorySettingsRepository()),
      clockProvider.overrideWithValue(() => now),
      widgetSinkProvider.overrideWithValue(sink),
    ]);
    addTearDown(container.dispose);
    container.listen(widgetSyncProvider, (_, _) {});
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    expect(sink.saved, isNotEmpty);
    expect(sink.saved.last['w_bg_alpha'], '128');
    expect(sink.saved.last.containsKey('w_theme'), isTrue);
  });

  test('fetchSnapshot: dados viram resumo ok', () async {
    final s = await fetchSnapshot(FakeSource(), now);
    expect(s['w_state'], 'ok');
    expect((jsonDecode(s['w_events']!) as List).length, 1);
    expect((jsonDecode(s['w_tasks']!) as List).single['id'], 't1');
    expect(jsonDecode(s['w_theme']!)['surface'], '#081826');
  });

  test('fetchSnapshot: falha devolve só w_state=error', () async {
    final s = await fetchSnapshot(FakeSource(fail: true), now);
    expect(s, {'w_state': 'error'});
  });

  test('fetchSnapshot não toca em w_bg_alpha (preferência do aparelho)', () async {
    final s = await fetchSnapshot(FakeSource(), now);
    expect(s.containsKey('w_bg_alpha'), isFalse);
  });
}
