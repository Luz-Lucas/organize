import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/domain/calendar_event.dart';
import 'package:organizacional/domain/ids.dart';
import 'package:organizacional/domain/note.dart';
import 'package:organizacional/domain/space.dart';
import 'package:organizacional/domain/task_item.dart';

void main() {
  test('newId gera uuids diferentes', () {
    expect(newId(), isNot(newId()));
    expect(newId(), hasLength(36));
  });

  test('Space ida e volta pelo mapa', () {
    const s = Space(id: 's1', name: 'Cálculo I', kind: SpaceKind.materia, position: 2);
    expect(Space.fromMap(s.toMap()), s);
    expect(s.toMap()['kind'], 'materia');
  });

  test('Note ida e volta pelo mapa', () {
    const n = Note(id: 'n1', title: 'Limites', body: '# Limites', spaceId: 's1');
    expect(Note.fromMap(n.toMap()), n);
  });

  test('TaskItem ida e volta com datas locais', () {
    final t = TaskItem(
      id: 't1',
      title: 'Lista 1',
      status: TaskStatus.doing,
      dueAt: DateTime(2026, 9, 28, 23, 59),
      spaceId: 's1',
    );
    expect(TaskItem.fromMap(t.toMap()), t);
  });

  test('datas vão para o banco em UTC', () {
    final t = TaskItem(id: 't1', title: 'x', dueAt: DateTime.utc(2026, 9, 28, 12));
    expect(t.toMap()['due_at'], '2026-09-28T12:00:00.000Z');
  });

  test('toggled marca e desmarca conclusão', () {
    final now = DateTime(2026, 9, 28, 10);
    const t = TaskItem(id: 't1', title: 'x');
    final done = t.toggled(now);
    expect(done.isDone, isTrue);
    expect(done.completedAt, now);
    final undone = done.toggled(now);
    expect(undone.status, TaskStatus.todo);
    expect(undone.completedAt, isNull);
  });

  test('CalendarEvent ida e volta e withoutSpace', () {
    final e = CalendarEvent(
      id: 'e1',
      title: 'Aula',
      startsAt: DateTime(2026, 9, 28, 8),
      endsAt: DateTime(2026, 9, 28, 9, 40),
      location: 'Sala 12',
      spaceId: 's1',
    );
    expect(CalendarEvent.fromMap(e.toMap()), e);
    expect(e.withoutSpace().spaceId, isNull);
    expect(e.withoutSpace().title, 'Aula');
  });

  test('fromMap aceita timestamp do Postgres com offset e converte para local', () {
    final e = CalendarEvent.fromMap({
      'id': 'e1',
      'title': 'Aula',
      'starts_at': '2026-09-28T11:00:00+00:00',
      'ends_at': '2026-09-28T12:40:00+00:00',
      'all_day': false,
      'location': null,
      'space_id': null,
      'source': 'google',
      'external_id': 'abc',
    });
    expect(e.startsAt.toUtc(), DateTime.utc(2026, 9, 28, 11));
    expect(e.startsAt.isUtc, isFalse);
    expect(e.source, 'google');
    expect(e.externalId, 'abc');
  });

  test('moved define e limpa completedAt', () {
    final now = DateTime(2026, 10, 11, 9);
    const t = TaskItem(id: 't', title: 'x');
    final done = t.moved(TaskStatus.done, now);
    expect([done.status, done.completedAt], [TaskStatus.done, now]);
    final back = done.moved(TaskStatus.todo, now);
    expect([back.status, back.completedAt], [TaskStatus.todo, null]);
    expect(t.moved(TaskStatus.doing, now).completedAt, isNull);
  });
  group('prioridade da tarefa', () {
    test('padrão é média e rótulos em português', () {
      const t = TaskItem(id: 't', title: 'x');
      expect(t.priority, TaskPriority.media);
      expect(TaskPriority.values.map((p) => p.label), ['Baixa', 'Média', 'Alta']);
    });

    test('ida e volta preserva a prioridade e usa o nome no banco', () {
      for (final p in TaskPriority.values) {
        final t = TaskItem(id: 't', title: 'x', priority: p);
        expect(t.toMap()['priority'], p.name);
        expect(TaskItem.fromMap(t.toMap()), t);
        expect(TaskItem.fromMap(t.toMap()).priority, p);
      }
    });

    test('valor ausente ou desconhecido vira média', () {
      final base = const TaskItem(id: 't', title: 'x').toMap();
      expect(TaskItem.fromMap({...base}..remove('priority')).priority, TaskPriority.media);
      expect(TaskItem.fromMap({...base, 'priority': null}).priority, TaskPriority.media);
      expect(TaskItem.fromMap({...base, 'priority': 'urgente'}).priority, TaskPriority.media);
    });

    test('moved e toggled mantêm a prioridade; igualdade considera a prioridade', () {
      final now = DateTime(2026, 10, 11, 9);
      const t = TaskItem(id: 't', title: 'x', priority: TaskPriority.alta);
      expect(t.moved(TaskStatus.doing, now).priority, TaskPriority.alta);
      expect(t.toggled(now).priority, TaskPriority.alta);
      expect(t == const TaskItem(id: 't', title: 'x'), isFalse);
      expect(t.hashCode == const TaskItem(id: 't', title: 'x').hashCode, isFalse);
    });
  });
}
