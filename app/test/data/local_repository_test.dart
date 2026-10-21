import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/local_repository.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/data/repository.dart';
import 'package:organizacional/domain/calendar_event.dart';
import 'package:organizacional/domain/event_tag.dart';
import 'package:organizacional/domain/note.dart';
import 'package:organizacional/domain/space.dart';
import 'package:organizacional/domain/task_item.dart';
import 'package:organizacional/sync/local_store.dart';

import 'repository_contract.dart';

CalendarEvent _ev(String id, int day, {String? seriesId, String? tagId, String? spaceId}) => CalendarEvent(
      id: id,
      title: id,
      startsAt: DateTime(2026, 10, day, 8),
      endsAt: DateTime(2026, 10, day, 9),
      seriesId: seriesId,
      tagId: tagId,
      spaceId: spaceId,
    );

void main() {
  group('contrato (MemoryRepository, para provar que o contrato é o mesmo)', () {
    repositoryContract(MemoryRepository.new);
  });

  group('contrato (LocalFirstRepository)', () {
    final stores = <LocalStore>[];
    tearDown(() async {
      for (final s in stores) {
        await s.close();
      }
      stores.clear();
    });
    repositoryContract(() {
      final store = LocalStore.inMemory();
      stores.add(store);
      return LocalFirstRepository(store);
    });
  });

  group('LocalFirstRepository', () {
    late DateTime clock;
    late LocalStore store;
    late LocalFirstRepository repo;

    DateTime tickClock() => clock = clock.add(const Duration(seconds: 1));

    setUp(() {
      clock = DateTime.utc(2026, 10, 21, 12);
      store = LocalStore.inMemory(now: tickClock);
      repo = LocalFirstRepository(store, now: tickClock);
    });
    tearDown(() => store.close());

    List<String> queue() => [for (final e in store.pendingOutbox()) '${e.op.name} ${e.tbl} ${e.id}'];

    group('a escrita entra na fila de envio', () {
      test('upsert de tarefa, nota, espaço, evento e etiqueta gera um item cada', () async {
        await repo.upsertSpace(const Space(id: 's1', name: 'A'));
        await repo.upsertNote(const Note(id: 'n1', title: 'Nota'));
        await repo.upsertTask(const TaskItem(id: 't1', title: 'Tarefa'));
        await repo.upsertEvent(_ev('e1', 1));
        await repo.upsertTag(const EventTag(id: 'g1', name: 'Aula', color: '#112233'));
        expect(queue(), [
          'upsert spaces s1',
          'upsert notes n1',
          'upsert tasks t1',
          'upsert events e1',
          'upsert event_tags g1',
        ]);
        expect(await store.watchPending().first, 5);
      });

      test('a linha enviada é o toMap do modelo, com client_updated_at', () async {
        final e = _ev('e1', 1, seriesId: 'sx');
        await repo.upsertEvent(e);
        final data = store.pendingOutbox().single.data!;
        expect(data['id'], 'e1');
        expect(data['starts_at'], e.startsAt.toUtc().toIso8601String());
        expect(data['series_id'], 'sx');
        expect(data['client_updated_at'], isNotNull);
      });

      test('apagar enfileira delete (e descarta o upsert pendente da mesma linha)', () async {
        await repo.upsertTask(const TaskItem(id: 't1', title: 'x'));
        await repo.upsertTask(const TaskItem(id: 't2', title: 'y'));
        await repo.deleteTask('t1');
        expect(queue(), ['upsert tasks t2', 'delete tasks t1']);
      });

      test('upsertTasks/upsertEvents/deleteTasks/deleteEvents em lote', () async {
        await repo.upsertTasks([
          const TaskItem(id: 'a', title: 'x'),
          const TaskItem(id: 'b', title: 'x'),
        ]);
        await repo.upsertEvents([_ev('c', 1), _ev('d', 2)]);
        expect(store.pendingNow, 4);
        await repo.deleteEvents(['c']);
        await repo.deleteTasks(['a', 'b']);
        expect(queue(), ['upsert events d', 'delete events c', 'delete tasks a', 'delete tasks b']);
      });

      test('deleteSeries enfileira um delete por ocorrência apagada', () async {
        await repo.upsertEvents([_ev('a', 1, seriesId: 's'), _ev('b', 10, seriesId: 's'), _ev('c', 20, seriesId: 's')]);
        await repo.deleteSeries('s', from: DateTime(2026, 10, 10, 8));
        expect(queue(), ['upsert events a', 'delete events b', 'delete events c']);
      });

      test('reorderTags enfileira uma gravação por etiqueta, com a nova posição', () async {
        await repo.upsertTag(const EventTag(id: 'a', name: 'A', color: '#112233'));
        await repo.upsertTag(const EventTag(id: 'b', name: 'B', color: '#112233', position: 1));
        store.ackOutbox(store.pendingOutbox());
        await repo.reorderTags([
          const EventTag(id: 'b', name: 'B', color: '#112233', position: 1),
          const EventTag(id: 'a', name: 'A', color: '#112233'),
        ]);
        final sent = {for (final e in store.pendingOutbox()) e.id: e.data!['position']};
        expect(sent, {'b': 0, 'a': 1});
      });

      test('nota duplicada é recusada sem entrar na fila', () async {
        await repo.upsertNote(const Note(id: 'n1', title: 'Cálculo'));
        await expectLater(
          repo.upsertNote(const Note(id: 'n2', title: 'cálculo')),
          throwsA(isA<RepositoryException>()),
        );
        expect(queue(), ['upsert notes n1']);
      });

      test('escrever não lança RepositoryException por falta de rede (não há rede no caminho)', () async {
        await repo.upsertTask(const TaskItem(id: 't', title: 'x'));
        await repo.deleteTask('t');
        await repo.upsertEvents([_ev('e', 1)]);
        await repo.deleteSeries('nada');
        expect(queue(), ['delete tasks t', 'upsert events e']);
      });
    });

    group('cascatas que o banco faria', () {
      test('excluir espaço enfileira: caderno sem espaço, evento sem espaço, apagamentos e por último o espaço', () async {
        await repo.upsertSpace(const Space(id: 's1', name: 'A'));
        await repo.upsertNote(const Note(id: 'c1', title: 'Caderno', spaceId: 's1', kind: NoteKind.notebook));
        await repo.upsertNote(const Note(id: 'n1', title: 'Limites', spaceId: 's1'));
        await repo.upsertTask(const TaskItem(id: 't1', title: 'x', spaceId: 's1'));
        await repo.upsertEvent(_ev('e1', 1, spaceId: 's1'));
        store.ackOutbox(store.pendingOutbox());

        await repo.deleteSpace('s1');
        final q = queue();
        expect(q.last, 'delete spaces s1');
        expect(q, containsAll(['upsert notes c1', 'upsert events e1', 'delete notes n1', 'delete tasks t1']));
        final notebook = store.pendingOutbox().firstWhere((e) => e.id == 'c1').data!;
        expect(notebook['space_id'], isNull);
        expect(notebook['title'], 'Caderno'); // linha inteira: o servidor faria INSERT se a linha não existisse
        expect(notebook['kind'], 'notebook');
        final event = store.pendingOutbox().firstWhere((e) => e.id == 'e1').data!;
        expect(event['space_id'], isNull);
        expect(event['title'], 'e1');
      });

      test('excluir espaço sem nada dentro só enfileira o delete do espaço', () async {
        await repo.upsertSpace(const Space(id: 's1', name: 'A'));
        store.ackOutbox(store.pendingOutbox());
        await repo.deleteSpace('s1');
        expect(queue(), ['delete spaces s1']);
      });

      test('excluir nota apaga as filhas (parent_id) e solta as tarefas ligadas a elas', () async {
        await repo.upsertNote(const Note(id: 'pai', title: 'Pai'));
        await repo.upsertNote(const Note(id: 'filha', title: 'Filha', parentId: 'pai'));
        await repo.upsertNote(const Note(id: 'neta', title: 'Neta', parentId: 'filha'));
        await repo.upsertNote(const Note(id: 'outra', title: 'Outra'));
        await store.put('tasks', const TaskItem(id: 't1', title: 'x', noteId: 'neta').toMap());
        await store.put('tasks', const TaskItem(id: 't2', title: 'y', noteId: 'outra').toMap());

        await repo.deleteNote('pai');
        expect((await repo.watchNotes().first).map((n) => n.id), ['outra']);
        final tasks = {for (final t in await repo.watchTasks().first) t.id: t.noteId};
        expect(tasks, {'t1': null, 't2': 'outra'});
      });

      test('excluir espaço apaga também as filhas das notas apagadas', () async {
        await repo.upsertSpace(const Space(id: 's1', name: 'A'));
        await repo.upsertNote(const Note(id: 'pai', title: 'Pai', spaceId: 's1'));
        await repo.upsertNote(const Note(id: 'filha', title: 'Filha', parentId: 'pai')); // sem espaço, mas filha
        await repo.deleteSpace('s1');
        expect(await repo.watchNotes().first, isEmpty);
      });

      test('excluir etiqueta enfileira o evento sem etiqueta (linha inteira) antes do delete', () async {
        await repo.upsertTag(const EventTag(id: 'a', name: 'Aula', color: '#112233'));
        await repo.upsertEvent(_ev('e1', 1, tagId: 'a'));
        store.ackOutbox(store.pendingOutbox());
        await repo.deleteTag('a');
        expect(queue(), ['upsert events e1', 'delete event_tags a']);
        expect(store.pendingOutbox().first.data!['tag_id'], isNull);
        expect(store.pendingOutbox().first.data!['title'], 'e1');
      });

      test('a mudança de uma cascata chega numa só emissão do stream', () async {
        await repo.upsertSpace(const Space(id: 's1', name: 'A'));
        await repo.upsertNote(const Note(id: 'n1', title: 'x', spaceId: 's1'));
        await repo.upsertTask(const TaskItem(id: 't1', title: 'x', spaceId: 's1'));
        final seen = <String>[];
        final sub = repo.watchTasks().listen((t) => seen.add('t${t.length}'));
        final sub2 = repo.watchSpaces().listen((s) => seen.add('s${s.length}'));
        await Future<void>.delayed(Duration.zero);
        seen.clear();
        await repo.deleteSpace('s1');
        await Future<void>.delayed(Duration.zero);
        expect(seen, unorderedEquals(['t0', 's0']));
        await sub.cancel();
        await sub2.cancel();
      });
    });

    group('ordenação das tarefas', () {
      test('por criação: o que o servidor devolveu (created_at) e o que nasceu aqui', () async {
        await store.putMany('tasks', [
          {...const TaskItem(id: 'zz', title: 'velha').toMap(), 'created_at': '2026-01-01T00:00:00+00:00'},
        ]);
        await repo.upsertTask(const TaskItem(id: 'a', title: 'nova 1'));
        await repo.upsertTask(const TaskItem(id: 'b', title: 'nova 2'));
        await repo.upsertTasks([const TaskItem(id: 'd', title: 'lote 1'), const TaskItem(id: 'c', title: 'lote 2')]);
        expect((await repo.watchTasks().first).map((t) => t.id), ['zz', 'a', 'b', 'd', 'c']);
      });

      test('editar uma tarefa não muda a posição dela', () async {
        await repo.upsertTask(const TaskItem(id: 'b', title: '1'));
        await repo.upsertTask(const TaskItem(id: 'a', title: '2'));
        await repo.upsertTask(const TaskItem(id: 'b', title: '1 editada'));
        expect((await repo.watchTasks().first).map((t) => t.id), ['b', 'a']);
      });
    });

    test('campos que só o servidor preenche sobrevivem a uma edição local', () async {
      await store.put('notes', {...const Note(id: 'n1', title: 'Um').toMap(), 'created_at': '2026-01-01T00:00:00Z', 'user_id': 'u'});
      await repo.upsertNote(const Note(id: 'n1', title: 'Um', body: 'texto'));
      final row = (await store.get('notes', 'n1'))!;
      expect(row['created_at'], '2026-01-01T00:00:00Z');
      expect(row['user_id'], 'u');
      expect(row['body'], 'texto');
    });

    test('lê o que a sincronização gravou (linha do servidor com campos extras e data com offset)', () async {
      await store.applyRemoteUpsert('events', {
        'id': 'r1',
        'user_id': 'u',
        'title': 'Remoto',
        'starts_at': '2026-10-05T11:00:00+00:00',
        'ends_at': '2026-10-05T12:00:00+00:00',
        'all_day': false,
        'created_at': '2026-10-01T00:00:00+00:00',
        'client_updated_at': '2026-10-01T00:00:00+00:00',
      });
      final events = await repo.watchEvents(from: DateTime.utc(2026, 10, 5, 11, 30)).first;
      expect(events.single.id, 'r1');
      expect(events.single.startsAt.isAtSameMomentAs(DateTime.utc(2026, 10, 5, 11)), isTrue);
    });

    group('seedEventTags (precisa do servidor)', () {
      test('sem função de servidor devolve 0 e não cria nada', () async {
        expect(await repo.seedEventTags(), 0);
        expect(await repo.watchTags().first, isEmpty);
        expect(store.pendingNow, 0);
      });

      test('chama a função injetada e devolve a contagem', () async {
        var calls = 0;
        final r = LocalFirstRepository(store, seedEventTagsRemote: () async {
          calls++;
          return 4;
        });
        expect(await r.seedEventTags(), 4);
        expect(calls, 1);
        expect(store.pendingNow, 0);
      });

      test('falha de rede devolve 0 sem lançar', () async {
        final r = LocalFirstRepository(store, seedEventTagsRemote: () async => throw Exception('sem rede'));
        expect(await r.seedEventTags(), 0);
        final r2 = LocalFirstRepository(store,
            seedEventTagsRemote: () async => throw const RepositoryException('Falha de conexão: x'));
        expect(await r2.seedEventTags(), 0);
      });
    });
  });
}
