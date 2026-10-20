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
import 'package:organizacional/widgets/widget_snapshot.dart';
import 'package:organizacional/widgets/widget_sync.dart';

import 'widget_sync_test.dart' show FakeSink;

final _now = DateTime(2026, 10, 11, 12);

const _aula = EventTag(id: 't1', name: 'Aula', color: '#3e63dd', role: EventTagRole.main);

CalendarEvent _ev(String id, {String? tagId}) => CalendarEvent(
    id: id,
    title: 'Evento $id',
    startsAt: DateTime(2026, 10, 11, 14),
    endsAt: DateTime(2026, 10, 11, 15),
    tagId: tagId);

List<Map<String, dynamic>> _events(Map<String, String> snap) =>
    (jsonDecode(snap['w_events']!) as List).cast<Map<String, dynamic>>();

class _TagSource implements WidgetDataSource {
  _TagSource({this.failTags = false});
  final bool failTags;

  @override
  Future<List<CalendarEvent>> events(DateTime from, DateTime to) async => [_ev('e1', tagId: 't1'), _ev('e2')];

  @override
  Future<List<TaskItem>> openTasks() async => const [];

  @override
  Future<String> themeId() async => 'violeta';

  @override
  Future<List<EventTag>> tags() async {
    if (failTags) throw Exception('sem rede');
    return [_aula];
  }

  @override
  Future<List<ShoppingList>> shoppingLists() async => const [];

  @override
  Future<List<ShoppingItem>> shoppingItems() async => const [];
}

void main() {
  test('w_events leva tagColor (#RRGGBB maiúsculo) só nos eventos com etiqueta conhecida', () {
    final snap = buildWidgetSnapshot(
      now: _now,
      events: [_ev('e1', tagId: 't1'), _ev('e2'), _ev('e3', tagId: 'apagada')],
      tasks: const [],
      themeId: 'violeta',
      tags: const [_aula],
    );
    final byId = {for (final e in _events(snap)) e['id']: e};
    expect(byId['e1']!['tagColor'], '#3E63DD');
    expect(byId['e2']!.containsKey('tagColor'), isTrue);
    expect(byId['e2']!['tagColor'], isNull);
    expect(byId['e3']!['tagColor'], isNull);
  });

  test('sem passar etiquetas nenhum evento ganha cor', () {
    final snap = buildWidgetSnapshot(now: _now, events: [_ev('e1', tagId: 't1')], tasks: const [], themeId: 'violeta');
    expect(_events(snap).single['tagColor'], isNull);
  });

  test('etiqueta com cor inválida não vira tagColor', () {
    final snap = buildWidgetSnapshot(
      now: _now,
      events: [_ev('e1', tagId: 't1')],
      tasks: const [],
      themeId: 'violeta',
      tags: const [EventTag(id: 't1', name: 'X', color: 'azul')],
    );
    expect(_events(snap).single['tagColor'], isNull);
  });

  test('fetchSnapshot busca as etiquetas e grava tagColor', () async {
    final snap = await fetchSnapshot(_TagSource(), _now);
    expect(snap['w_state'], 'ok');
    final byId = {for (final e in _events(snap)) e['id']: e};
    expect(byId['e1']!['tagColor'], '#3E63DD');
    expect(byId['e2']!['tagColor'], isNull);
  });

  test('falha ao buscar etiquetas não derruba o resumo: só some a cor', () async {
    final snap = await fetchSnapshot(_TagSource(failTags: true), _now);
    expect(snap['w_state'], 'ok');
    expect(_events(snap), hasLength(2));
    expect(_events(snap).every((e) => e['tagColor'] == null), isTrue);
  });

  testWidgets('com o app aberto, o resumo grava tagColor das etiquetas', (tester) async {
    final repo = MemoryRepository();
    await repo.upsertTag(_aula);
    await repo.upsertEvent(_ev('e1', tagId: 't1'));
    final sink = FakeSink();
    final container = ProviderContainer(overrides: [
      repositoryProvider.overrideWithValue(repo),
      settingsRepositoryProvider.overrideWithValue(MemorySettingsRepository()),
      clockProvider.overrideWithValue(() => _now),
      widgetSinkProvider.overrideWithValue(sink),
    ]);
    addTearDown(container.dispose);
    container.listen(widgetSyncProvider, (_, _) {});
    container.listen(eventTagsProvider, (_, _) {});
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(sink.saved, isNotEmpty);
    expect(_events(sink.saved.last).single['tagColor'], '#3E63DD');
  });
}
