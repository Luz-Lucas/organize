import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/data/repository.dart';
import 'package:organizacional/domain/calendar_event.dart';
import 'package:organizacional/domain/note.dart';
import 'package:organizacional/domain/notice.dart';
import 'package:organizacional/domain/space.dart';
import 'package:organizacional/domain/task_item.dart';

void main() {
  late MemoryRepository repo;
  setUp(() => repo = MemoryRepository());

  test('watch emite o estado atual e cada mudança', () async {
    final emissions = <List<Space>>[];
    final sub = repo.watchSpaces().listen(emissions.add);
    await Future<void>.delayed(Duration.zero);
    await repo.upsertSpace(const Space(id: 's1', name: 'Cálculo I', kind: SpaceKind.materia));
    await Future<void>.delayed(Duration.zero);
    expect(emissions.map((e) => e.length), [0, 1]);
    await sub.cancel();
  });

  test('excluir espaço apaga notas e tarefas e mantém eventos sem espaço', () async {
    await repo.upsertSpace(const Space(id: 's1', name: 'Cálculo I'));
    await repo.upsertNote(const Note(id: 'n1', title: 'Limites', spaceId: 's1'));
    await repo.upsertTask(const TaskItem(id: 't1', title: 'Lista 1', spaceId: 's1'));
    await repo.upsertEvent(CalendarEvent(
      id: 'e1',
      title: 'Aula',
      startsAt: DateTime(2026, 9, 28, 8),
      endsAt: DateTime(2026, 9, 28, 10),
      spaceId: 's1',
    ));
    await repo.deleteSpace('s1');
    expect(await repo.watchNotes().first, isEmpty);
    expect(await repo.watchTasks().first, isEmpty);
    final events = await repo.watchEvents(from: DateTime(2026, 9, 1)).first;
    expect(events.single.spaceId, isNull);
  });

  test('título de nota duplicado (caixa/espaços) lança duplicate', () async {
    await repo.upsertNote(const Note(id: 'n1', title: 'Cálculo I'));
    await expectLater(
      repo.upsertNote(const Note(id: 'n2', title: '  cálculo   i ')),
      throwsA(isA<RepositoryException>().having((e) => e.duplicate, 'duplicate', isTrue)),
    );
  });

  test('regravar a própria nota com o mesmo título não é duplicata', () async {
    await repo.upsertNote(const Note(id: 'n1', title: 'Cálculo I'));
    await repo.upsertNote(const Note(id: 'n1', title: 'Cálculo I', body: 'novo'));
    expect((await repo.watchNotes().first).single.body, 'novo');
  });

  test('failWrites simula queda de conexão', () async {
    repo.failWrites = true;
    await expectLater(
      repo.upsertTask(const TaskItem(id: 't1', title: 'x')),
      throwsA(isA<RepositoryException>()),
    );
    expect(await repo.watchTasks().first, isEmpty);
  });

  test('watchEvents ignora eventos que terminaram antes de from', () async {
    await repo.upsertEvent(CalendarEvent(
      id: 'velho',
      title: 'Velho',
      startsAt: DateTime(2026, 9, 1, 8),
      endsAt: DateTime(2026, 9, 1, 9),
    ));
    await repo.upsertEvent(CalendarEvent(
      id: 'novo',
      title: 'Novo',
      startsAt: DateTime(2026, 9, 28, 8),
      endsAt: DateTime(2026, 9, 28, 9),
    ));
    final events = await repo.watchEvents(from: DateTime(2026, 9, 28)).first;
    expect(events.map((e) => e.id), ['novo']);
  });

  test('avisos: upsert, ordem por criação desc, delete e falha de escrita', () async {
    await repo.upsertNotice(Notice(id: 'a', title: 'A', createdAt: DateTime(2026, 10, 1)));
    await repo.upsertNotice(Notice(id: 'b', title: 'B', createdAt: DateTime(2026, 10, 2)));
    expect((await repo.watchNotices().first).map((n) => n.id), ['b', 'a']);
    await repo.deleteNotice('b');
    expect((await repo.watchNotices().first).map((n) => n.id), ['a']);
    repo.failWrites = true;
    await expectLater(repo.upsertNotice(const Notice(id: 'c', title: 'C')), throwsA(isA<RepositoryException>()));
  });

  CalendarEvent ev(String id, int day, {String? seriesId}) => CalendarEvent(
        id: id,
        title: id,
        startsAt: DateTime(2026, 10, day, 8),
        endsAt: DateTime(2026, 10, day, 9),
        seriesId: seriesId,
      );

  test('upsertEvents grava em lote com uma só emissão; deleteEvents apaga em lote', () async {
    final emissions = <int>[];
    final sub = repo.watchEvents(from: DateTime(2026, 10, 1)).listen((l) => emissions.add(l.length));
    await Future<void>.delayed(Duration.zero);
    await repo.upsertEvents([ev('a', 1), ev('b', 2), ev('c', 3)]);
    await Future<void>.delayed(Duration.zero);
    expect(emissions, [0, 3]);
    await repo.deleteEvents(['a', 'c', 'inexistente']);
    await Future<void>.delayed(Duration.zero);
    expect(emissions, [0, 3, 1]);
    await sub.cancel();
  });

  test('upsertEvents/deleteEvents respeitam failWrites', () async {
    repo.failWrites = true;
    await expectLater(repo.upsertEvents([ev('a', 1)]), throwsA(isA<RepositoryException>()));
    await expectLater(repo.deleteEvents(['a']), throwsA(isA<RepositoryException>()));
  });

  test('deleteSeries apaga a série inteira ou só a partir de um instante, sem tocar nas outras', () async {
    await repo.upsertEvents([
      ev('a', 1, seriesId: 's1'),
      ev('b', 10, seriesId: 's1'),
      ev('c', 20, seriesId: 's1'),
      ev('x', 12, seriesId: 's2'),
      ev('solto', 15),
    ]);
    final emissions = <int>[];
    final sub = repo.watchEvents(from: DateTime(2026, 10, 1)).listen((l) => emissions.add(l.length));
    await Future<void>.delayed(Duration.zero);

    await repo.deleteSeries('s1', from: DateTime(2026, 10, 10, 8)); // inclusive
    await Future<void>.delayed(Duration.zero);
    expect((await repo.listSeries('s1')).map((e) => e.id), ['a']);
    expect(emissions, [5, 3]);

    await repo.deleteSeries('s1');
    expect(await repo.listSeries('s1'), isEmpty);
    expect((await repo.listSeries('s2')).map((e) => e.id), ['x']);
    expect((await repo.watchEvents(from: DateTime(2026, 10, 1)).first).map((e) => e.id), ['x', 'solto']);
    await sub.cancel();
  });

  test('deleteSeries de série inexistente não faz nada e respeita failWrites', () async {
    await repo.upsertEvents([ev('a', 1, seriesId: 's1')]);
    await repo.deleteSeries('nada');
    expect(await repo.listSeries('s1'), hasLength(1));
    repo.failWrites = true;
    await expectLater(repo.deleteSeries('s1'), throwsA(isA<RepositoryException>()));
  });

  test('listSeries devolve só as ocorrências da série, em ordem, mesmo as já passadas', () async {
    await repo.upsertEvents([
      ev('c', 20, seriesId: 's1'),
      ev('a', 1, seriesId: 's1'),
      ev('x', 5, seriesId: 's2'),
      ev('solto', 6),
    ]);
    expect((await repo.listSeries('s1')).map((e) => e.id), ['a', 'c']);
    expect(await repo.listSeries('nada'), isEmpty);
  });
}
