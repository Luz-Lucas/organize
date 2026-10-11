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
}
