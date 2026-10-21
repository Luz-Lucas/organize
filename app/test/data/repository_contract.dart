import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/repository.dart';
import 'package:organizacional/domain/calendar_event.dart';
import 'package:organizacional/domain/event_tag.dart';
import 'package:organizacional/domain/note.dart';
import 'package:organizacional/domain/space.dart';
import 'package:organizacional/domain/task_item.dart';

CalendarEvent _ev(String id, int day, {String? seriesId, String? tagId, String? spaceId}) => CalendarEvent(
      id: id,
      title: id,
      startsAt: DateTime(2026, 10, day, 8),
      endsAt: DateTime(2026, 10, day, 9),
      seriesId: seriesId,
      tagId: tagId,
      spaceId: spaceId,
    );

TaskItem _task(String id, int day, {String? series = 's1'}) =>
    TaskItem(id: id, title: 'Lab', dueAt: DateTime(2026, 10, day, 23, 59), seriesId: series);

/// O que todo `Repository` precisa cumprir (o em memória e o local-primeiro).
/// [make] cria um repositório vazio a cada teste.
void repositoryContract(Repository Function() make) {
  late Repository repo;
  setUp(() => repo = make());

  Future<void> tick() => Future<void>.delayed(Duration.zero);
  Future<List<EventTag>> tags() => repo.watchTags().first;

  group('espaços, notas e tarefas', () {
    test('watch emite o estado atual e cada mudança', () async {
      final emissions = <List<Space>>[];
      final sub = repo.watchSpaces().listen(emissions.add);
      await tick();
      await repo.upsertSpace(const Space(id: 's1', name: 'Cálculo I', kind: SpaceKind.materia));
      await tick();
      expect(emissions.map((e) => e.length), [0, 1]);
      await sub.cancel();
    });

    test('espaços saem ordenados por posição', () async {
      await repo.upsertSpace(const Space(id: 'b', name: 'B', position: 1));
      await repo.upsertSpace(const Space(id: 'a', name: 'A', position: 0));
      expect((await repo.watchSpaces().first).map((s) => s.id), ['a', 'b']);
    });

    test('notas saem ordenadas por título', () async {
      await repo.upsertNote(const Note(id: '1', title: 'Zebra'));
      await repo.upsertNote(const Note(id: '2', title: 'Abelha'));
      expect((await repo.watchNotes().first).map((n) => n.id), ['2', '1']);
    });

    test('excluir espaço nunca apaga cadernos: ficam sem espaço (como o gatilho do banco)', () async {
      await repo.upsertSpace(const Space(id: 's1', name: 'Cálculo I'));
      await repo.upsertNote(const Note(id: 'c1', title: 'Caderno', spaceId: 's1', kind: NoteKind.notebook));
      await repo.upsertNote(const Note(id: 'n1', title: 'Limites', spaceId: 's1'));
      await repo.deleteSpace('s1');
      final notes = await repo.watchNotes().first;
      expect(notes.map((n) => n.id), ['c1']);
      expect(notes.single.spaceId, isNull);
    });

    test('excluir espaço apaga notas e tarefas e mantém eventos sem espaço', () async {
      await repo.upsertSpace(const Space(id: 's1', name: 'Cálculo I'));
      await repo.upsertNote(const Note(id: 'n1', title: 'Limites', spaceId: 's1'));
      await repo.upsertTask(const TaskItem(id: 't1', title: 'Lista 1', spaceId: 's1'));
      await repo.upsertEvent(_ev('e1', 28, spaceId: 's1'));
      await repo.deleteSpace('s1');
      expect(await repo.watchSpaces().first, isEmpty);
      expect(await repo.watchNotes().first, isEmpty);
      expect(await repo.watchTasks().first, isEmpty);
      final events = await repo.watchEvents(from: DateTime(2026, 9, 1)).first;
      expect(events.single.spaceId, isNull);
    });

    test('excluir um espaço não mexe no que é de outro', () async {
      await repo.upsertSpace(const Space(id: 's1', name: 'A'));
      await repo.upsertSpace(const Space(id: 's2', name: 'B'));
      await repo.upsertNote(const Note(id: 'n1', title: 'Um', spaceId: 's1'));
      await repo.upsertNote(const Note(id: 'n2', title: 'Dois', spaceId: 's2'));
      await repo.upsertTask(const TaskItem(id: 't2', title: 'x', spaceId: 's2'));
      await repo.deleteSpace('s1');
      expect((await repo.watchNotes().first).map((n) => n.id), ['n2']);
      expect((await repo.watchTasks().first).map((t) => t.id), ['t2']);
    });

    test('título de nota duplicado (caixa/espaços) lança duplicate', () async {
      await repo.upsertNote(const Note(id: 'n1', title: 'Cálculo I'));
      await expectLater(
        repo.upsertNote(const Note(id: 'n2', title: '  cálculo   i ')),
        throwsA(isA<RepositoryException>().having((e) => e.duplicate, 'duplicate', isTrue)),
      );
      expect(await repo.watchNotes().first, hasLength(1));
    });

    test('regravar a própria nota com o mesmo título não é duplicata', () async {
      await repo.upsertNote(const Note(id: 'n1', title: 'Cálculo I'));
      await repo.upsertNote(const Note(id: 'n1', title: 'Cálculo I', body: 'novo'));
      expect((await repo.watchNotes().first).single.body, 'novo');
    });

    test('deleteNote e deleteTask removem só o id', () async {
      await repo.upsertNote(const Note(id: 'n1', title: 'Um'));
      await repo.upsertNote(const Note(id: 'n2', title: 'Dois'));
      await repo.upsertTask(const TaskItem(id: 't1', title: 'x'));
      await repo.upsertTask(const TaskItem(id: 't2', title: 'y'));
      await repo.deleteNote('n1');
      await repo.deleteTask('t2');
      expect((await repo.watchNotes().first).map((n) => n.id), ['n2']);
      expect((await repo.watchTasks().first).map((t) => t.id), ['t1']);
    });
  });

  group('eventos', () {
    test('watchEvents ignora eventos que terminaram antes de from e ordena por início', () async {
      await repo.upsertEvent(CalendarEvent(
        id: 'velho',
        title: 'Velho',
        startsAt: DateTime(2026, 9, 1, 8),
        endsAt: DateTime(2026, 9, 1, 9),
      ));
      await repo.upsertEvent(_ev('tarde', 29));
      await repo.upsertEvent(_ev('cedo', 28));
      final events = await repo.watchEvents(from: DateTime(2026, 9, 28)).first;
      expect(events.map((e) => e.id), ['cedo', 'tarde']);
    });

    test('evento que termina exatamente em from ainda aparece', () async {
      await repo.upsertEvent(_ev('e', 10));
      final events = await repo.watchEvents(from: DateTime(2026, 10, 10, 9)).first;
      expect(events.map((e) => e.id), ['e']);
    });

    test('upsertEvents grava em lote com uma só emissão; deleteEvents apaga em lote', () async {
      final emissions = <int>[];
      final sub = repo.watchEvents(from: DateTime(2026, 10, 1)).listen((l) => emissions.add(l.length));
      await tick();
      await repo.upsertEvents([_ev('a', 1), _ev('b', 2), _ev('c', 3)]);
      await tick();
      expect(emissions, [0, 3]);
      await repo.deleteEvents(['a', 'c', 'inexistente']);
      await tick();
      expect(emissions, [0, 3, 1]);
      await sub.cancel();
    });

    test('listas vazias não fazem nada', () async {
      await repo.upsertEvents(const []);
      await repo.deleteEvents(const []);
      await repo.upsertTasks(const []);
      await repo.deleteTasks(const []);
      await repo.reorderTags(const []);
    });

    test('deleteSeries apaga a série inteira ou só a partir de um instante, sem tocar nas outras', () async {
      await repo.upsertEvents([
        _ev('a', 1, seriesId: 's1'),
        _ev('b', 10, seriesId: 's1'),
        _ev('c', 20, seriesId: 's1'),
        _ev('x', 12, seriesId: 's2'),
        _ev('solto', 15),
      ]);
      final emissions = <int>[];
      final sub = repo.watchEvents(from: DateTime(2026, 10, 1)).listen((l) => emissions.add(l.length));
      await tick();

      await repo.deleteSeries('s1', from: DateTime(2026, 10, 10, 8)); // inclusive
      await tick();
      expect((await repo.listSeries('s1')).map((e) => e.id), ['a']);
      expect(emissions, [5, 3]);

      await repo.deleteSeries('s1');
      expect(await repo.listSeries('s1'), isEmpty);
      expect((await repo.listSeries('s2')).map((e) => e.id), ['x']);
      expect((await repo.watchEvents(from: DateTime(2026, 10, 1)).first).map((e) => e.id), ['x', 'solto']);
      await sub.cancel();
    });

    test('deleteSeries de série inexistente não faz nada', () async {
      await repo.upsertEvents([_ev('a', 1, seriesId: 's1')]);
      await repo.deleteSeries('nada');
      expect(await repo.listSeries('s1'), hasLength(1));
    });

    test('listSeries devolve só as ocorrências da série, em ordem, mesmo as já passadas', () async {
      await repo.upsertEvents([
        _ev('c', 20, seriesId: 's1'),
        _ev('a', 1, seriesId: 's1'),
        _ev('x', 5, seriesId: 's2'),
        _ev('solto', 6),
      ]);
      expect((await repo.listSeries('s1')).map((e) => e.id), ['a', 'c']);
      expect(await repo.listSeries('nada'), isEmpty);
    });

    test('o evento sai igual ao que entrou (datas, recorrência, lembretes)', () async {
      final e = _ev('e1', 12, seriesId: 'sx', tagId: 't1').copyWith(location: 'Sala 3', allDay: true, reminders: [10, 60]);
      await repo.upsertEvent(e);
      expect((await repo.listSeries('sx')).single, e);
    });
  });

  group('séries de tarefas', () {
    test('upsertTasks grava todas de uma vez e deleteTasks remove só os ids', () async {
      await repo.upsertTasks([_task('a', 20), _task('b', 27), _task('c', 28, series: null)]);
      expect((await repo.watchTasks().first).length, 3);
      await repo.deleteTasks(['a', 'c']);
      expect((await repo.watchTasks().first).map((t) => t.id), ['b']);
    });

    test('listTaskSeries devolve só a série, por prazo (sem prazo por último)', () async {
      await repo.upsertTasks([
        _task('c', 4),
        _task('a', 20),
        _task('x', 21, series: 'outra'),
        _task('b', 27),
        const TaskItem(id: 'sem', title: 'Lab', seriesId: 's1'),
      ]);
      expect((await repo.listTaskSeries('s1')).map((t) => t.id), ['c', 'a', 'b', 'sem']);
      expect(await repo.listTaskSeries('nada'), isEmpty);
    });

    test('a tarefa sai igual à que entrou', () async {
      final t = _task('a', 20).copyWith(description: 'texto', priority: TaskPriority.alta, reminders: [30]);
      await repo.upsertTask(t);
      expect((await repo.watchTasks().first).single, t);
    });
  });

  group('etiquetas', () {
    test('watchTags emite o estado atual e cada mudança, ordenado por posição', () async {
      final emissions = <List<EventTag>>[];
      final sub = repo.watchTags().listen(emissions.add);
      await tick();
      await repo.upsertTag(const EventTag(id: 'b', name: 'B', color: '#112233', position: 1));
      await repo.upsertTag(const EventTag(id: 'a', name: 'A', color: '#112233', position: 0));
      await tick();
      expect(emissions.last.map((t) => t.id), ['a', 'b']);
      expect(emissions.first, isEmpty);
      await sub.cancel();
    });

    test('upsertTag substitui pelo id (renomear e recolorir)', () async {
      await repo.upsertTag(const EventTag(id: 'a', name: 'Aula', color: '#112233'));
      await repo.upsertTag(const EventTag(id: 'a', name: 'Faculdade', color: '#445566', role: EventTagRole.main));
      final l = await tags();
      expect(l, hasLength(1));
      expect(l.single.name, 'Faculdade');
      expect(l.single.color, '#445566');
      expect(l.single.role, EventTagRole.main);
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
      await repo.upsertEvents([_ev('e1', 1, tagId: 'a'), _ev('e2', 2, tagId: 'b'), _ev('e3', 3)]);
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
      await repo.upsertEvent(_ev('e1', 1, tagId: 't1'));
      await repo.upsertEvents([_ev('e2', 2, tagId: 't2'), _ev('e3', 3)]);
      final events = {for (final e in await repo.watchEvents(from: DateTime(2026, 9, 1)).first) e.id: e.tagId};
      expect(events, {'e1': 't1', 'e2': 't2', 'e3': null});
    });
  });
}
