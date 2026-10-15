import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/domain/calendar_event.dart';
import 'package:organizacional/domain/event_tag.dart';
import 'package:organizacional/domain/recurrence.dart';

CalendarEvent _ev({String id = 'e1', String? tagId, String? spaceId, DateTime? start, String? seriesId}) =>
    CalendarEvent(
      id: id,
      title: 'Aula',
      startsAt: start ?? DateTime(2026, 10, 12, 18, 30),
      endsAt: (start ?? DateTime(2026, 10, 12, 18, 30)).add(const Duration(hours: 1)),
      tagId: tagId,
      spaceId: spaceId,
      seriesId: seriesId,
    );

void main() {
  group('EventTag', () {
    const tag = EventTag(
        id: 't1', name: 'Aula', color: '#3E63DD', role: EventTagRole.main, position: 2);

    test('ida e volta pelo mapa (sem user_id)', () {
      expect(EventTag.fromMap(tag.toMap()), tag);
      expect(tag.toMap(), {
        'id': 't1',
        'name': 'Aula',
        'color': '#3E63DD',
        'role': 'main',
        'position': 2,
      });
    });

    test('role ausente ou desconhecido vira normal e position ausente vira 0', () {
      final t = EventTag.fromMap({'id': 't', 'name': 'X', 'color': '#112233', 'role': 'extra'});
      expect(t.role, EventTagRole.normal);
      expect(t.position, 0);
      expect(EventTag.fromMap({'id': 't', 'name': 'X', 'color': '#112233'}).role, EventTagRole.normal);
    });

    test('os cinco papéis têm nome em pt-BR', () {
      expect(EventTagRole.values.map((r) => r.name), ['main', 'secondary', 'seasonal', 'meeting', 'normal']);
      expect(EventTagRole.values.map((r) => r.label), ['Principal', 'Secundária', 'Sazonal', 'Reunião', 'Comum']);
    });

    test('copyWith troca só o que foi pedido; == e hashCode olham todos os campos', () {
      final c = tag.copyWith(name: 'Faculdade', role: EventTagRole.normal);
      expect(c.name, 'Faculdade');
      expect(c.role, EventTagRole.normal);
      expect(c.color, tag.color);
      expect(c.id, tag.id);
      expect(c, isNot(tag));
      expect(tag.copyWith(), tag);
      expect(tag.copyWith().hashCode, tag.hashCode);
      expect(tag.copyWith(position: 3), isNot(tag));
    });
  });

  group('CalendarEvent.tagId', () {
    test('ida e volta pelo mapa com tag_id', () {
      final e = _ev(tagId: 't1');
      expect(e.toMap()['tag_id'], 't1');
      expect(CalendarEvent.fromMap(e.toMap()), e);
      expect(CalendarEvent.fromMap(e.toMap()).tagId, 't1');
    });

    test('sem tag_id no mapa fica nulo e é gravado como null', () {
      final map = _ev().toMap();
      expect(map.containsKey('tag_id'), isTrue);
      expect(map['tag_id'], isNull);
      map.remove('tag_id');
      expect(CalendarEvent.fromMap(map).tagId, isNull);
    });

    test('copyWith troca e clearTag limpa; == considera o tagId', () {
      final e = _ev(tagId: 't1');
      expect(e.copyWith(title: 'Outro').tagId, 't1');
      expect(e.copyWith(tagId: 't2').tagId, 't2');
      expect(e.copyWith(clearTag: true).tagId, isNull);
      expect(e, isNot(e.copyWith(tagId: 't2')));
      expect(e.hashCode, isNot(e.copyWith(tagId: 't2').hashCode));
    });

    test('withoutSpace mantém a etiqueta', () {
      expect(_ev(tagId: 't1', spaceId: 's1').withoutSpace().tagId, 't1');
    });
  });

  group('séries preservam e aplicam a etiqueta', () {
    List<CalendarEvent> weekly(String? tagId) => SeriesOps.buildSeries(
          _ev(tagId: tagId),
          Recurrence(freq: RepeatFreq.weekly, count: 4),
          () => 'id${_n++}',
        );

    test('buildSeries copia o tagId do modelo para todas as ocorrências', () {
      final s = weekly('t1');
      expect(s, hasLength(4));
      expect(s.map((e) => e.tagId).toSet(), {'t1'});
      expect(weekly(null).map((e) => e.tagId).toSet(), {null});
    });

    test('applyEdit one: só a ocorrência editada recebe a etiqueta nova', () {
      final s = weekly('t1');
      final up = SeriesOps.applyEdit(s, s[1], s[1].copyWith(tagId: 't2'), SeriesScope.one);
      expect(up, hasLength(1));
      expect(up.single.tagId, 't2');
    });

    test('applyEdit all: a etiqueta vai para todas', () {
      final s = weekly('t1');
      final up = SeriesOps.applyEdit(s, s[2], s[2].copyWith(tagId: 't2'), SeriesScope.all);
      expect(up.map((e) => e.tagId).toSet(), {'t2'});
      expect(up, hasLength(4));
    });

    test('applyEdit following: só este e os seguintes mudam de etiqueta', () {
      final s = weekly('t1');
      final up = SeriesOps.applyEdit(s, s[2], s[2].copyWith(tagId: 't2'), SeriesScope.following,
          newSeriesId: () => 'nova');
      expect(up.map((e) => e.id), [s[2].id, s[3].id]);
      expect(up.map((e) => e.tagId).toSet(), {'t2'});
    });

    test('applyEdit all: "Sem etiqueta" limpa a etiqueta de todas', () {
      final s = weekly('t1');
      final up = SeriesOps.applyEdit(s, s[0], s[0].copyWith(clearTag: true), SeriesScope.all);
      expect(up.map((e) => e.tagId).toSet(), {null});
    });

    test('applyEdit all sem mexer na etiqueta mantém a mesma em todas', () {
      final s = weekly('t1');
      final up = SeriesOps.applyEdit(s, s[0], s[0].copyWith(title: 'Novo'), SeriesScope.all);
      expect(up.map((e) => e.tagId).toSet(), {'t1'});
    });
  });
}

int _n = 0;
