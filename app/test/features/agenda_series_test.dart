import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/calendar_event.dart';
import 'package:organizacional/domain/recurrence.dart';

import '../helpers.dart';

final _from = DateTime(2026, 9, 1);

/// Registra as exclusões de série e proíbe a exclusão por lista de ids.
class _SpyRepo extends MemoryRepository {
  final seriesDeletes = <(String, DateTime?)>[];

  @override
  Future<void> deleteSeries(String seriesId, {DateTime? from}) {
    seriesDeletes.add((seriesId, from));
    return super.deleteSeries(seriesId, from: from);
  }

  @override
  Future<void> deleteEvents(List<String> ids) => throw StateError('deleteEvents não deve ser usado');
}

/// Terças e quintas às 18:00 a partir de 29/09/2026, 4 ocorrências:
/// 29/09, 01/10, 06/10, 08/10 (a semana aberta na tela é 27/09–03/10).
List<CalendarEvent> _serie() {
  var n = 0;
  return SeriesOps.buildSeries(
    CalendarEvent(
      id: 'tpl',
      title: 'Cálculo',
      startsAt: DateTime(2026, 9, 29, 18),
      endsAt: DateTime(2026, 9, 29, 19, 40),
    ),
    Recurrence(freq: RepeatFreq.weekly, days: {2, 4}, count: 4),
    () => 's${++n}',
  );
}

Future<MemoryRepository> _repoWithSeries() async {
  final repo = MemoryRepository();
  await repo.upsertEvents(_serie());
  return repo;
}

Future<List<CalendarEvent>> _all(MemoryRepository repo) => repo.watchEvents(from: _from).first;

Finder _block(CalendarEvent e) =>
    find.byKey(ValueKey('event-block-${e.id}-${e.startsAt.toIso8601String().substring(0, 10)}'));

Future<void> _openFromWeek(WidgetTester tester, CalendarEvent e) async {
  await tester.tap(_block(e));
  await tester.pumpAndSettle();
  expect(find.text('Editar evento'), findsOneWidget);
}

void main() {
  group('criar série', () {
    testWidgets('semanal ter+qui por quantidade cria as ocorrências com o mesmo seriesId', (tester) async {
      final repo = MemoryRepository();
      await pumpApp(tester, repo, location: '/agenda');
      await tester.tap(find.byKey(const Key('new-event')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('event-title')), 'Monitoria');

      expect(find.byKey(const Key('event-repeat-summary')), findsNothing);
      await tester.tap(find.byKey(const Key('event-repeat')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Toda semana').last);
      await tester.pumpAndSettle();

      // O dia do início (segunda, 28/09) vem marcado; escolhe ter+qui e tira a segunda.
      expect(tester.widget<FilterChip>(find.byKey(const Key('event-repeat-day-1'))).selected, isTrue);
      await tester.tap(find.byKey(const Key('event-repeat-day-2')));
      await tester.tap(find.byKey(const Key('event-repeat-day-4')));
      await tester.tap(find.byKey(const Key('event-repeat-day-1')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('event-repeat-mode-count')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('event-repeat-count')), '4');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('event-repeat-summary')), findsOneWidget);
      expect(find.textContaining('Toda semana às ter e qui'), findsOneWidget);
      expect(find.textContaining('4 ocorrências'), findsOneWidget);

      await tester.tap(find.byKey(const Key('event-save')));
      await tester.pumpAndSettle();

      final events = await _all(repo);
      expect(events.map((e) => e.startsAt), [
        DateTime(2026, 9, 29, 8),
        DateTime(2026, 10, 1, 8),
        DateTime(2026, 10, 6, 8),
        DateTime(2026, 10, 8, 8),
      ]);
      expect(events.map((e) => e.seriesId).toSet().length, 1);
      expect(events.first.seriesId, isNotNull);
      expect(events.every((e) => e.title == 'Monitoria'), isTrue);
      expect(events.every((e) => e.endsAt.difference(e.startsAt) == const Duration(hours: 1, minutes: 40)),
          isTrue);
    });

    testWidgets('padrão "Até" (início + 3 meses) cria a série semanal', (tester) async {
      final repo = MemoryRepository();
      await pumpApp(tester, repo, location: '/agenda');
      await tester.tap(find.byKey(const Key('new-event')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('event-title')), 'Corrida');
      await tester.tap(find.byKey(const Key('event-repeat')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Toda semana').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('event-repeat-until')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('event-repeat-until')), matching: find.textContaining('28')),
          findsOneWidget); // 28 de dez
      await tester.tap(find.byKey(const Key('event-save')));
      await tester.pumpAndSettle();
      final events = await _all(repo);
      // Segundas de 28/09 a 28/12/2026 (inclusive): 14 ocorrências.
      expect(events, hasLength(14));
      expect(events.last.startsAt, DateTime(2026, 12, 28, 8));
    });

    testWidgets('quantidade fora de 1 a 366 mostra erro e não grava nada', (tester) async {
      final repo = MemoryRepository();
      await pumpApp(tester, repo, location: '/agenda');
      await tester.tap(find.byKey(const Key('new-event')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('event-title')), 'X');
      await tester.tap(find.byKey(const Key('event-repeat')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Todo dia').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('event-repeat-mode-count')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('event-repeat-count')), '400');
      await tester.tap(find.byKey(const Key('event-save')));
      await tester.pumpAndSettle();
      expect(find.text('Informe de 1 a 366 repetições.'), findsOneWidget);
      expect(await _all(repo), isEmpty);
    });

    testWidgets('sem repetição salva um evento comum, sem seriesId', (tester) async {
      final repo = MemoryRepository();
      await pumpApp(tester, repo, location: '/agenda');
      await tester.tap(find.byKey(const Key('new-event')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('event-title')), 'Avulso');
      await tester.tap(find.byKey(const Key('event-save')));
      await tester.pumpAndSettle();
      final e = (await _all(repo)).single;
      expect(e.seriesId, isNull);
      expect(e.recurrence, isNull);
    });

    testWidgets('o seletor "Repetir" não aparece ao editar', (tester) async {
      final repo = await _repoWithSeries();
      await pumpApp(tester, repo, location: '/agenda');
      await _openFromWeek(tester, _serie().first);
      expect(find.byKey(const Key('event-repeat')), findsNothing);
    });
  });

  group('excluir', () {
    testWidgets('"este e os seguintes" remove só os >= e Desfazer restaura todos', (tester) async {
      final repo = await _repoWithSeries();
      final s = _serie();
      await pumpApp(tester, repo, location: '/agenda');
      await _openFromWeek(tester, s[1]); // 01/10
      await tester.tap(find.byKey(ValueKey('delete-event-${s[1].id}')));
      await tester.pumpAndSettle();
      expect(find.text('Este evento se repete'), findsOneWidget);
      expect(find.text('Só este evento'), findsOneWidget);
      expect(find.text('Este e os seguintes'), findsOneWidget);
      expect(find.text('Todos os eventos da série'), findsOneWidget);
      await tester.tap(find.byKey(const Key('series-scope-following')));
      await tester.pumpAndSettle();

      expect((await _all(repo)).map((e) => e.id), [s[0].id]);
      expect(find.text('3 eventos excluídos'), findsOneWidget);

      await tester.tap(find.text('Desfazer'));
      await tester.pumpAndSettle();
      final back = await _all(repo);
      expect(back.map((e) => e.id), s.map((e) => e.id).toList());
      expect(back.map((e) => e.seriesId).toSet(), {s.first.seriesId});
    });

    testWidgets('"este e os seguintes" e "todos" apagam por series_id (deleteSeries), não por lista de ids', (tester) async {
      final repo = _SpyRepo();
      await repo.upsertEvents(_serie());
      final s = _serie();
      await pumpApp(tester, repo, location: '/agenda');
      await _openFromWeek(tester, s[1]);
      await tester.tap(find.byKey(ValueKey('delete-event-${s[1].id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('series-scope-following')));
      await tester.pumpAndSettle();
      expect(repo.seriesDeletes, [(s[0].seriesId!, s[1].startsAt)]);
      expect((await _all(repo)).map((e) => e.id), [s[0].id]);

      await tester.tap(find.text('Desfazer'));
      await tester.pumpAndSettle();
      expect(await _all(repo), hasLength(4));

      await tester.tap(find.byKey(ValueKey('event-block-${s[0].id}-${s[0].startsAt.toIso8601String().substring(0, 10)}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('delete-event-${s[0].id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('series-scope-all')));
      await tester.pumpAndSettle();
      expect(repo.seriesDeletes.last, (s[0].seriesId!, null));
      expect(await _all(repo), isEmpty);
    });

    testWidgets('"só este evento" apaga apenas ele', (tester) async {
      final repo = await _repoWithSeries();
      final s = _serie();
      await pumpApp(tester, repo, location: '/agenda');
      await _openFromWeek(tester, s[0]);
      await tester.tap(find.byKey(ValueKey('delete-event-${s[0].id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('series-scope-one')));
      await tester.pumpAndSettle();
      expect((await _all(repo)).map((e) => e.id), [s[1].id, s[2].id, s[3].id]);
      expect(find.text('Evento excluído'), findsOneWidget);
    });

    testWidgets('"todos os eventos da série" apaga tudo, inclusive os fora da tela', (tester) async {
      final repo = await _repoWithSeries();
      final s = _serie();
      await pumpApp(tester, repo, location: '/agenda');
      await _openFromWeek(tester, s[0]);
      await tester.tap(find.byKey(ValueKey('delete-event-${s[0].id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('series-scope-all')));
      await tester.pumpAndSettle();
      expect(await _all(repo), isEmpty);
    });

    testWidgets('Cancelar no diálogo de escopo não apaga nada', (tester) async {
      final repo = await _repoWithSeries();
      final s = _serie();
      await pumpApp(tester, repo, location: '/agenda');
      await _openFromWeek(tester, s[0]);
      await tester.tap(find.byKey(ValueKey('delete-event-${s[0].id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('series-scope-cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('series-scope-all')), findsNothing);
      expect(await _all(repo), hasLength(4));
    });

    testWidgets('evento sem série não mostra o diálogo de escopo', (tester) async {
      final repo = MemoryRepository();
      await repo.upsertEvent(CalendarEvent(
        id: 'solo',
        title: 'Avulso',
        startsAt: DateTime(2026, 9, 30, 10),
        endsAt: DateTime(2026, 9, 30, 11),
      ));
      await pumpApp(tester, repo, location: '/agenda');
      await tester.tap(find.text('Avulso'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('delete-event-solo')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('series-scope-all')), findsNothing);
      expect(find.text('Excluir “Avulso”?'), findsOneWidget);
      await tester.tap(find.text('Excluir'));
      await tester.pumpAndSettle();
      expect(await _all(repo), isEmpty);
    });
  });

  group('editar', () {
    testWidgets('"todos" desloca o horário de início de toda a série', (tester) async {
      final repo = await _repoWithSeries();
      final s = _serie();
      await pumpApp(tester, repo, location: '/agenda');
      await _openFromWeek(tester, s[0]);
      await tester.tap(find.byKey(const Key('event-start-time')));
      await tester.pumpAndSettle();
      // Entrada por teclado (desktop): primeiro campo = hora. No teste o relógio
      // é de 12 h e o período (PM) é mantido: 7 → 19:00.
      await tester.enterText(
          find.descendant(of: find.byType(TimePickerDialog), matching: find.byType(TextField)).first, '7');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('event-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('series-scope-all')));
      await tester.pumpAndSettle();

      final events = await _all(repo);
      expect(events, hasLength(4));
      expect(events.map((e) => e.startsAt.hour).toSet(), {19});
      expect(events.map((e) => e.seriesId).toSet(), {s.first.seriesId});
      // O fim ficou em 19:40: a duração agora é de 40 min em todas.
      expect(events.map((e) => e.endsAt.difference(e.startsAt)).toSet(), {const Duration(minutes: 40)});
    });

    testWidgets('"este e os seguintes" muda só os >= e abre série nova', (tester) async {
      final repo = await _repoWithSeries();
      final s = _serie();
      await pumpApp(tester, repo, location: '/agenda');
      await _openFromWeek(tester, s[1]);
      await tester.enterText(find.byKey(const Key('event-title')), 'Cálculo B');
      await tester.tap(find.byKey(const Key('event-save')));
      await tester.pumpAndSettle();
      expect(find.text('Este evento se repete'), findsOneWidget);
      await tester.tap(find.byKey(const Key('series-scope-following')));
      await tester.pumpAndSettle();

      final events = await _all(repo);
      expect(events.map((e) => e.title), ['Cálculo', 'Cálculo B', 'Cálculo B', 'Cálculo B']);
      expect(events[0].seriesId, s.first.seriesId);
      expect(events.skip(1).map((e) => e.seriesId).toSet().length, 1);
      expect(events[1].seriesId, isNot(events[0].seriesId));
    });

    testWidgets('"só este evento" muda ele e o tira da série', (tester) async {
      final repo = await _repoWithSeries();
      final s = _serie();
      await pumpApp(tester, repo, location: '/agenda');
      await _openFromWeek(tester, s[1]);
      await tester.enterText(find.byKey(const Key('event-title')), 'Prova');
      await tester.tap(find.byKey(const Key('event-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('series-scope-one')));
      await tester.pumpAndSettle();
      final events = await _all(repo);
      final changed = events.firstWhere((e) => e.id == s[1].id);
      expect(changed.title, 'Prova');
      expect(changed.seriesId, isNull);
      expect(events.where((e) => e.id != s[1].id).map((e) => e.title).toSet(), {'Cálculo'});
    });

    testWidgets('evento sem série salva direto, sem diálogo de escopo', (tester) async {
      final repo = MemoryRepository();
      await repo.upsertEvent(CalendarEvent(
        id: 'solo',
        title: 'Avulso',
        startsAt: DateTime(2026, 9, 30, 10),
        endsAt: DateTime(2026, 9, 30, 11),
      ));
      await pumpApp(tester, repo, location: '/agenda');
      await tester.tap(find.text('Avulso'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('event-title')), 'Avulso 2');
      await tester.tap(find.byKey(const Key('event-save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('series-scope-all')), findsNothing);
      expect((await _all(repo)).single.title, 'Avulso 2');
    });
  });

  group('ícone de repetição', () {
    testWidgets('semana (desktop): eventos de série têm o ícone, avulsos não', (tester) async {
      final repo = await _repoWithSeries();
      await repo.upsertEvent(CalendarEvent(
        id: 'solo',
        title: 'Avulso',
        startsAt: DateTime(2026, 9, 30, 10),
        endsAt: DateTime(2026, 9, 30, 11),
      ));
      final s = _serie();
      await pumpApp(tester, repo, location: '/agenda');
      expect(find.descendant(of: _block(s[0]), matching: find.byIcon(Icons.repeat)), findsOneWidget);
      final solo = find.byKey(const ValueKey('event-block-solo-2026-09-30'));
      expect(solo, findsOneWidget);
      expect(find.descendant(of: solo, matching: find.byIcon(Icons.repeat)), findsNothing);
    });

    testWidgets('celular: o cartão do evento de série mostra o ícone', (tester) async {
      final repo = MemoryRepository();
      var n = 0;
      final s = SeriesOps.buildSeries(
        CalendarEvent(
          id: 'm1',
          title: 'Yoga',
          startsAt: DateTime(2026, 9, 28, 7),
          endsAt: DateTime(2026, 9, 28, 8),
        ),
        Recurrence(freq: RepeatFreq.daily, count: 2),
        () => 'r${++n}',
      );
      await repo.upsertEvents(s);
      await repo.upsertEvent(CalendarEvent(
        id: 'solo',
        title: 'Avulso',
        startsAt: DateTime(2026, 9, 28, 12),
        endsAt: DateTime(2026, 9, 28, 13),
      ));
      await pumpApp(tester, repo, location: '/agenda', size: const Size(390, 844));
      expect(find.descendant(of: find.byKey(const ValueKey('agenda-event-m1')), matching: find.byIcon(Icons.repeat)),
          findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('agenda-event-solo')), matching: find.byIcon(Icons.repeat)),
          findsNothing);
    });
  });
}
