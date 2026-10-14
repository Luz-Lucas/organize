import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/data/repository.dart';
import 'package:organizacional/domain/calendar_event.dart';
import 'package:organizacional/domain/event_tag.dart';

CalendarEvent _ev(String id, {String? tagId}) => CalendarEvent(
      id: id,
      title: 'Evento $id',
      startsAt: DateTime(2026, 9, 28, 8),
      endsAt: DateTime(2026, 9, 28, 9),
      tagId: tagId,
    );

void main() {
  late MemoryRepository repo;
  setUp(() => repo = MemoryRepository());

  Future<List<EventTag>> tags() => repo.watchTags().first;

  test('watchTags emite o estado atual e cada mudança, ordenado por posição', () async {
    final emissions = <List<EventTag>>[];
    final sub = repo.watchTags().listen(emissions.add);
    await Future<void>.delayed(Duration.zero);
    await repo.upsertTag(const EventTag(id: 'b', name: 'B', color: '#112233', position: 1));
    await repo.upsertTag(const EventTag(id: 'a', name: 'A', color: '#112233', position: 0));
    await Future<void>.delayed(Duration.zero);
    expect(emissions.map((e) => e.length), [0, 1, 2]);
    expect(emissions.last.map((t) => t.id), ['a', 'b']);
    await sub.cancel();
  });

  test('upsertTag substitui pelo id (renomear e recolorir)', () async {
    await repo.upsertTag(const EventTag(id: 'a', name: 'Aula', color: '#112233'));
    await repo.upsertTag(const EventTag(id: 'a', name: 'Faculdade', color: '#445566', role: EventTagRole.main));
    final l = await tags();
    expect(l, hasLength(1));
    expect(l.single.name, 'Faculdade');
    expect(l.single.color, '#445566');
  });

  test('nome repetido (sem diferenciar caixa) é duplicado, como no banco', () async {
    await repo.upsertTag(const EventTag(id: 'a', name: 'Aula', color: '#112233'));
    await expectLater(
      repo.upsertTag(const EventTag(id: 'b', name: ' aula ', color: '#112233')),
      throwsA(isA<RepositoryException>().having((e) => e.duplicate, 'duplicate', isTrue)),
    );
    expect(await tags(), hasLength(1));
  });

  test('deleteTag deixa os eventos sem etiqueta (set null) e não os apaga', () async {
    await repo.upsertTag(const EventTag(id: 'a', name: 'Aula', color: '#112233'));
    await repo.upsertTag(const EventTag(id: 'b', name: 'Academia', color: '#445566'));
    await repo.upsertEvents([_ev('e1', tagId: 'a'), _ev('e2', tagId: 'b'), _ev('e3')]);
    await repo.deleteTag('a');
    expect((await tags()).map((t) => t.id), ['b']);
    final events = {for (final e in await repo.watchEvents(from: DateTime(2026, 9, 1)).first) e.id: e.tagId};
    expect(events, {'e1': null, 'e2': 'b', 'e3': null});
  });

  test('reorderTags regrava as posições 0..n-1 na ordem dada', () async {
    for (final id in ['a', 'b', 'c']) {
      await repo.upsertTag(EventTag(id: id, name: id.toUpperCase(), color: '#112233', position: 'abc'.indexOf(id)));
    }
    final current = await tags();
    await repo.reorderTags([current[2], current[0], current[1]]);
    final l = await tags();
    expect(l.map((t) => t.id), ['c', 'a', 'b']);
    expect(l.map((t) => t.position), [0, 1, 2]);
  });

  test('upsertEvent e upsertEvents preservam o tagId', () async {
    await repo.upsertEvent(_ev('e1', tagId: 't1'));
    await repo.upsertEvents([_ev('e2', tagId: 't2'), _ev('e3')]);
    final events = {for (final e in await repo.watchEvents(from: DateTime(2026, 9, 1)).first) e.id: e.tagId};
    expect(events, {'e1': 't1', 'e2': 't2', 'e3': null});
  });

  test('seedEventTags cria as quatro etiquetas iniciais, na ordem, e é idempotente', () async {
    expect(await repo.seedEventTags(), 4);
    final l = await tags();
    expect(l.map((t) => t.name), ['Aula', 'Academia', 'Sazonal', 'Reunião']);
    expect(l.map((t) => t.role),
        [EventTagRole.main, EventTagRole.secondary, EventTagRole.seasonal, EventTagRole.meeting]);
    expect(l.map((t) => t.position), [0, 1, 2, 3]);
    expect(l.every((t) => RegExp(r'^#[0-9A-F]{6}$').hasMatch(t.color)), isTrue);
    expect(l.map((t) => t.color).toSet(), hasLength(4));
    expect(await repo.seedEventTags(), 0);
    expect(await tags(), hasLength(4));
  });

  test('seedEventTags só cria os papéis que faltam', () async {
    await repo.upsertTag(const EventTag(id: 'x', name: 'Faculdade', color: '#010203', role: EventTagRole.main));
    expect(await repo.seedEventTags(), 3);
    final l = await tags();
    expect(l.where((t) => t.role == EventTagRole.main).single.name, 'Faculdade');
  });

  test('com a conexão caída, escritas de etiqueta falham', () async {
    repo.failWrites = true;
    await expectLater(repo.upsertTag(const EventTag(id: 'a', name: 'A', color: '#112233')),
        throwsA(isA<RepositoryException>()));
    await expectLater(repo.deleteTag('a'), throwsA(isA<RepositoryException>()));
    await expectLater(repo.reorderTags(const []), throwsA(isA<RepositoryException>()));
    await expectLater(repo.seedEventTags(), throwsA(isA<RepositoryException>()));
  });
}
