import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/domain/calendar_event.dart';
import 'package:organizacional/domain/recurrence.dart';

Recurrence _r(RepeatFreq f, {Set<int> days = const {}, DateTime? until, int? count}) =>
    Recurrence(freq: f, days: days, until: until, count: count);

List<String> _ymd(List<DateTime> l) =>
    l.map((d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}').toList();

void main() {
  // 2026-10-12 é segunda-feira.
  final first = DateTime(2026, 10, 12, 18, 30);

  group('expandStarts', () {
    test('none devolve só o primeiro', () {
      expect(_r(RepeatFreq.none, count: 5).expandStarts(first), [first]);
    });

    test('daily com count', () {
      final s = _r(RepeatFreq.daily, count: 3).expandStarts(first);
      expect(_ymd(s), ['2026-10-12', '2026-10-13', '2026-10-14']);
      expect(s.every((d) => d.hour == 18 && d.minute == 30), isTrue);
    });

    test('daily com until inclusivo', () {
      final s = _r(RepeatFreq.daily, until: DateTime(2026, 10, 14)).expandStarts(first);
      expect(_ymd(s), ['2026-10-12', '2026-10-13', '2026-10-14']);
    });

    test('until e count juntos: vale o que acabar primeiro', () {
      final s = _r(RepeatFreq.daily, until: DateTime(2026, 10, 20), count: 2).expandStarts(first);
      expect(s.length, 2);
      final t = _r(RepeatFreq.daily, until: DateTime(2026, 10, 13), count: 9).expandStarts(first);
      expect(t.length, 2);
    });

    test('until antes do primeiro não gera nada', () {
      expect(_r(RepeatFreq.daily, until: DateTime(2026, 10, 11)).expandStarts(first), isEmpty);
    });

    test('weekdays pula sábado e domingo', () {
      final s = _r(RepeatFreq.weekdays, count: 6).expandStarts(DateTime(2026, 10, 15, 9));
      expect(_ymd(s), ['2026-10-15', '2026-10-16', '2026-10-19', '2026-10-20', '2026-10-21', '2026-10-22']);
    });

    test('weekly com ter e qui', () {
      final s = _r(RepeatFreq.weekly, days: {2, 4}, count: 4).expandStarts(first);
      expect(_ymd(s), ['2026-10-13', '2026-10-15', '2026-10-20', '2026-10-22']);
    });

    test('weekly sem dias usa o dia da semana do primeiro', () {
      final s = _r(RepeatFreq.weekly, count: 3).expandStarts(first);
      expect(_ymd(s), ['2026-10-12', '2026-10-19', '2026-10-26']);
    });

    test('weekly não inclui dias da semana do primeiro antes dele', () {
      // Quarta 14/10, dias seg+qua: segunda 12/10 da mesma semana já passou.
      final s = _r(RepeatFreq.weekly, days: {1, 3}, count: 3).expandStarts(DateTime(2026, 10, 14, 8));
      expect(_ymd(s), ['2026-10-14', '2026-10-19', '2026-10-21']);
    });

    test('biweekly pula uma semana (semana de segunda a domingo)', () {
      final s = _r(RepeatFreq.biweekly, days: {1, 3}, count: 4).expandStarts(first);
      expect(_ymd(s), ['2026-10-12', '2026-10-14', '2026-10-26', '2026-10-28']);
    });

    test('monthly no mesmo dia', () {
      final s = _r(RepeatFreq.monthly, count: 3).expandStarts(first);
      expect(_ymd(s), ['2026-10-12', '2026-11-12', '2026-12-12']);
    });

    test('monthly dia 31 só nos meses que têm dia 31', () {
      final s = _r(RepeatFreq.monthly, count: 5).expandStarts(DateTime(2026, 10, 31, 8));
      expect(_ymd(s), ['2026-10-31', '2026-12-31', '2027-01-31', '2027-03-31', '2027-05-31']);
    });

    test('limite duro de 366 ocorrências', () {
      final s = _r(RepeatFreq.daily, count: 1000).expandStarts(first);
      expect(s.length, 366);
    });

    test('limite duro de 1 ano a partir do primeiro (inclusive)', () {
      final s = _r(RepeatFreq.weekly, until: DateTime(2030, 1, 1)).expandStarts(first);
      expect(s.last, DateTime(2027, 10, 11, 18, 30));
      expect(s.length, 53);
      final d = _r(RepeatFreq.daily, until: DateTime(2030, 1, 1)).expandStarts(first);
      expect(d.length, 366);
      expect(d.last, DateTime(2027, 10, 12, 18, 30));
    });

    test('sem until nem count vale o limite duro', () {
      expect(_r(RepeatFreq.daily).expandStarts(first).length, 366);
    });
  });

  group('Recurrence mapa', () {
    test('ida e volta', () {
      final r = _r(RepeatFreq.weekly, days: {4, 2}, until: DateTime(2026, 12, 15));
      expect(r.toMap(), {'freq': 'weekly', 'days': [2, 4], 'until': '2026-12-15', 'count': null});
      expect(Recurrence.fromMap(r.toMap()), r);
      final c = _r(RepeatFreq.daily, count: 7);
      expect(Recurrence.fromMap(c.toMap()), c);
    });

    test('freq desconhecida vira none', () {
      expect(Recurrence.fromMap({'freq': 'zzz'}).freq, RepeatFreq.none);
    });
  });

  test('rótulos pt-BR', () {
    expect(RepeatFreq.none.label, 'Não repete');
    expect(RepeatFreq.daily.label, 'Todo dia');
    expect(RepeatFreq.weekdays.label, 'Dias úteis (seg–sex)');
    expect(RepeatFreq.weekly.label, 'Toda semana');
    expect(RepeatFreq.biweekly.label, 'A cada 2 semanas');
    expect(RepeatFreq.monthly.label, 'Todo mês');
  });

  test('resumo em texto', () {
    final r = _r(RepeatFreq.weekly, days: {2, 4}, until: DateTime(2026, 12, 15));
    final starts = r.expandStarts(DateTime(2026, 10, 13, 18));
    expect(r.summary(DateTime(2026, 10, 13, 18)),
        'Toda semana às ter e qui, até 15 dez · ${starts.length} ocorrências');
    expect(_r(RepeatFreq.daily, count: 1).summary(first), contains('1 ocorrência'));
    expect(_r(RepeatFreq.daily, count: 1).summary(first), isNot(contains('ocorrências')));
    expect(_r(RepeatFreq.daily, until: DateTime(2026, 10, 1)).summary(first), 'Nenhuma ocorrência no período');
  });

  group('SeriesOps', () {
    var n = 0;
    String gen() => 'id${++n}';
    setUp(() => n = 0);

    CalendarEvent template() => CalendarEvent(
          id: 'tpl',
          title: 'Aula',
          startsAt: DateTime(2026, 10, 13, 18),
          endsAt: DateTime(2026, 10, 13, 19, 40),
          location: 'Sala 1',
          spaceId: 's1',
        );

    List<CalendarEvent> weekly4() =>
        SeriesOps.buildSeries(template(), _r(RepeatFreq.weekly, days: {2, 4}, count: 4), gen);

    test('buildSeries: mesmo seriesId, duração e campos; template.id no primeiro', () {
      final s = weekly4();
      expect(s.length, 4);
      expect(s.map((e) => e.seriesId).toSet().length, 1);
      expect(s.first.seriesId, isNotNull);
      expect(s.first.id, 'tpl');
      expect(s.map((e) => e.id).toSet().length, 4);
      expect(_ymd(s.map((e) => e.startsAt).toList()), ['2026-10-13', '2026-10-15', '2026-10-20', '2026-10-22']);
      for (final e in s) {
        expect(e.endsAt.difference(e.startsAt), const Duration(hours: 1, minutes: 40));
        expect(e.title, 'Aula');
        expect(e.location, 'Sala 1');
        expect(e.spaceId, 's1');
        expect(e.recurrence, isNotNull);
      }
    });

    test('buildSeries: evento que vira o dia mantém a duração', () {
      final t = CalendarEvent(
        id: 'p',
        title: 'Plantão',
        startsAt: DateTime(2026, 10, 12, 22),
        endsAt: DateTime(2026, 10, 13, 2),
      );
      final s = SeriesOps.buildSeries(t, _r(RepeatFreq.daily, count: 3), gen);
      expect(s[2].startsAt, DateTime(2026, 10, 14, 22));
      expect(s[2].endsAt, DateTime(2026, 10, 15, 2));
    });

    test('buildSeries: ocorrência que não cai no instante do template recebe id novo', () {
      // Template numa segunda, mas a regra só vale na terça.
      final t = CalendarEvent(
          id: 'tpl', title: 'x', startsAt: DateTime(2026, 10, 12, 8), endsAt: DateTime(2026, 10, 12, 9));
      final s = SeriesOps.buildSeries(t, _r(RepeatFreq.weekly, days: {2}, count: 2), gen);
      expect(s.first.seriesId, 'id1');
      expect(s.map((e) => e.id), ['id2', 'id3']);
    });

    CalendarEvent edited(CalendarEvent target, {String? title, Duration shift = Duration.zero, Duration? len}) =>
        CalendarEvent(
          id: target.id,
          title: title ?? target.title,
          startsAt: target.startsAt.add(shift),
          endsAt: target.startsAt.add(shift).add(len ?? target.endsAt.difference(target.startsAt)),
          location: target.location,
          spaceId: target.spaceId,
          seriesId: target.seriesId,
          recurrence: target.recurrence,
        );

    test('applyEdit one: só o alvo e ele sai da série', () {
      final s = weekly4();
      final up = SeriesOps.applyEdit(s, s[1], edited(s[1], title: 'Prova'), SeriesScope.one);
      expect(up.length, 1);
      expect(up.single.id, s[1].id);
      expect(up.single.title, 'Prova');
      expect(up.single.seriesId, isNull);
      expect(up.single.recurrence, isNull);
    });

    test('applyEdit all: campos e deslocamento de horário em todas', () {
      final s = weekly4();
      final up = SeriesOps.applyEdit(
          s, s[2], edited(s[2], title: 'Aula B', shift: const Duration(hours: 1), len: const Duration(hours: 2)),
          SeriesScope.all);
      expect(up.length, 4);
      expect(up.map((e) => e.seriesId).toSet(), {s.first.seriesId});
      for (var i = 0; i < 4; i++) {
        expect(up[i].id, s[i].id);
        expect(up[i].title, 'Aula B');
        expect(up[i].startsAt, DateTime(s[i].startsAt.year, s[i].startsAt.month, s[i].startsAt.day, 19));
        expect(up[i].endsAt.difference(up[i].startsAt), const Duration(hours: 2));
      }
    });

    test('applyEdit all: mudar o dia do alvo desloca a série inteira', () {
      final s = weekly4();
      final up = SeriesOps.applyEdit(s, s[0], edited(s[0], shift: const Duration(days: 1)), SeriesScope.all);
      expect(_ymd(up.map((e) => e.startsAt).toList()), ['2026-10-14', '2026-10-16', '2026-10-21', '2026-10-23']);
    });

    test('applyEdit following: só os >= alvo, com seriesId novo', () {
      final s = weekly4();
      final up = SeriesOps.applyEdit(
          s, s[2], edited(s[2], title: 'Nova', shift: const Duration(minutes: 30)), SeriesScope.following,
          newSeriesId: () => 'nova-serie');
      expect(up.map((e) => e.id), [s[2].id, s[3].id]);
      expect(up.map((e) => e.seriesId).toSet(), {'nova-serie'});
      expect(up.map((e) => e.title).toSet(), {'Nova'});
      expect(up[0].startsAt, DateTime(2026, 10, 20, 18, 30));
      expect(up[1].startsAt, DateTime(2026, 10, 22, 18, 30));
    });

    test('applyEdit following no primeiro mantém o seriesId (equivale a todos)', () {
      final s = weekly4();
      final up = SeriesOps.applyEdit(s, s[0], edited(s[0], title: 'Z'), SeriesScope.following,
          newSeriesId: () => 'nova');
      expect(up.length, 4);
      expect(up.map((e) => e.seriesId).toSet(), {s.first.seriesId});
    });

    test('deleteIds one/following/all', () {
      final s = weekly4();
      expect(SeriesOps.deleteIds(s, s[1], SeriesScope.one), [s[1].id]);
      expect(SeriesOps.deleteIds(s, s[1], SeriesScope.following), [s[1].id, s[2].id, s[3].id]);
      expect(SeriesOps.deleteIds(s, s[1], SeriesScope.all), s.map((e) => e.id).toList());
    });

    test('embaralhar a lista não muda o resultado de following', () {
      final s = weekly4();
      final shuffled = [s[3], s[0], s[2], s[1]];
      expect(SeriesOps.deleteIds(shuffled, s[2], SeriesScope.following).toSet(), {s[2].id, s[3].id});
    });
  });

  test('CalendarEvent guarda seriesId/recurrence no mapa e withoutSpace preserva', () {
    final e = CalendarEvent(
      id: 'e',
      title: 'x',
      startsAt: DateTime(2026, 10, 12, 8),
      endsAt: DateTime(2026, 10, 12, 9),
      spaceId: 's',
      seriesId: 'ser',
      recurrence: _r(RepeatFreq.daily, count: 2),
    );
    final m = e.toMap();
    expect(m['series_id'], 'ser');
    expect(m['recurrence'], {'freq': 'daily', 'days': <int>[], 'until': null, 'count': 2});
    expect(CalendarEvent.fromMap(m), e);
    final w = e.withoutSpace();
    expect(w.spaceId, isNull);
    expect(w.seriesId, 'ser');
    expect(w.recurrence, e.recurrence);
    expect(CalendarEvent.fromMap({...m, 'series_id': null, 'recurrence': null}).seriesId, isNull);
    expect(e.copyWith(clearSeries: true).seriesId, isNull);
    expect(e.copyWith(clearSeries: true).recurrence, isNull);
  });
}
