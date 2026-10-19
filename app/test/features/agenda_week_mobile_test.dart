import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/calendar_event.dart';
import 'package:organizacional/domain/event_tag.dart';
import 'package:organizacional/features/agenda/agenda_view_prefs.dart';

import '../helpers.dart';

const _aula = EventTag(id: 't-aula', name: 'Aula', color: '#3E63DD', role: EventTagRole.main, position: 0);
const _acad =
    EventTag(id: 't-acad', name: 'Academia', color: '#30A46C', role: EventTagRole.secondary, position: 1);

final _from = DateTime(2026, 9, 1);

/// Hoje nos testes é segunda 28/09/2026 10:00; a semana vai de domingo 27/09 a sábado 03/10.
CalendarEvent _ev(
  String id,
  String title, {
  int month = 9,
  int day = 29,
  int hour = 10,
  int minute = 0,
  int minutes = 60,
  String? tagId,
  bool allDay = false,
}) {
  final s = DateTime(2026, month, day, hour, minute);
  return CalendarEvent(
    id: id,
    title: title,
    startsAt: allDay ? DateTime(2026, month, day) : s,
    endsAt: allDay ? DateTime(2026, month, day + 1) : s.add(Duration(minutes: minutes)),
    allDay: allDay,
    tagId: tagId,
  );
}

Future<MemoryRepository> _repo([List<CalendarEvent> events = const []]) async {
  final repo = MemoryRepository();
  await repo.upsertTag(_aula);
  await repo.upsertTag(_acad);
  await repo.upsertEvents(events);
  return repo;
}

Future<MemoryAgendaViewPrefs> _pumpWeek(
  WidgetTester tester,
  MemoryRepository repo, {
  MemoryAgendaViewPrefs? prefs,
  Size size = const Size(400, 800),
  DateTime? now,
}) async {
  final p = prefs ?? MemoryAgendaViewPrefs(view: 'week');
  await pumpApp(
    tester,
    repo,
    location: '/agenda',
    size: size,
    now: now,
    overrides: [agendaViewPrefsProvider.overrideWithValue(p)],
  );
  return p;
}

Finder _k(String key) => find.byKey(ValueKey(key));
Finder _col(String day) => _k('mweek-col-$day');
Finder _block(String id, String day) => _k('mweek-event-$id-$day');

Future<void> _swipe(WidgetTester tester, {required bool next}) async {
  await tester.fling(find.byKey(const Key('mobile-week')), Offset(next ? -300 : 300, 0), 1200);
  await tester.pumpAndSettle();
}

void main() {
  group('seletor Mês | Semana', () {
    testWidgets('começa em Mês, alterna e lembra a escolha por aparelho', (tester) async {
      final prefs = MemoryAgendaViewPrefs();
      await _pumpWeek(tester, await _repo([_ev('e1', 'Cálculo')]), prefs: prefs);
      expect(find.byKey(const Key('agenda-view-month')), findsOneWidget);
      expect(find.byKey(const Key('agenda-view-week')), findsOneWidget);
      expect(find.byKey(const Key('mobile-week')), findsNothing);
      expect(find.byKey(const ValueKey('mini-day-2026-09-29')), findsOneWidget);
      expect(
          tester.widget<SegmentedButton<MobileAgendaView>>(find.byType(SegmentedButton<MobileAgendaView>)).selected,
          {MobileAgendaView.month});

      await tester.tap(find.byKey(const Key('agenda-view-week')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('mobile-week')), findsOneWidget);
      expect(find.byKey(const ValueKey('mini-day-2026-09-29')), findsNothing);
      expect(prefs.view, 'week');
      expect(find.text('27 set – 3 out 2026'), findsOneWidget);

      // Outra execução do app, mesmo aparelho: abre direto na semana.
      await tester.pumpWidget(const SizedBox());
      await _pumpWeek(tester, await _repo(), prefs: prefs);
      expect(find.byKey(const Key('mobile-week')), findsOneWidget);

      await tester.tap(find.byKey(const Key('agenda-view-month')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('mobile-week')), findsNothing);
      expect(find.byKey(const ValueKey('mini-day-2026-09-29')), findsOneWidget);
      expect(prefs.view, 'month');
    });

    testWidgets('no computador não há seletor e a semana de sempre continua', (tester) async {
      await pumpApp(tester, await _repo([_ev('e1', 'Cálculo')]), location: '/agenda');
      expect(find.byKey(const Key('agenda-view-week')), findsNothing);
      expect(find.byKey(const Key('mobile-week')), findsNothing);
      expect(find.byKey(const ValueKey('event-block-e1-2026-09-29')), findsOneWidget);
    });

    testWidgets('semana lembrada no celular vale só abaixo de 720 dp', (tester) async {
      await _pumpWeek(tester, await _repo([_ev('e1', 'Cálculo')]), size: const Size(1000, 800));
      expect(find.byKey(const Key('mobile-week')), findsNothing);
      expect(find.byKey(const ValueKey('event-block-e1-2026-09-29')), findsOneWidget);
    });
  });

  group('grade da semana', () {
    testWidgets('7 colunas de domingo a sábado, cabeçalho com inicial e número, hoje destacado', (tester) async {
      await _pumpWeek(tester, await _repo());
      final days = ['2026-09-27', '2026-09-28', '2026-09-29', '2026-09-30', '2026-10-01', '2026-10-02', '2026-10-03'];
      for (final d in days) {
        expect(_col(d), findsOneWidget, reason: d);
        expect(_k('mweek-head-$d'), findsOneWidget, reason: d);
      }
      // Domingo é a primeira coluna, sábado a última.
      expect(tester.getTopLeft(_col(days.first)).dx, lessThan(tester.getTopLeft(_col(days.last)).dx));
      expect(tester.getSize(_col('2026-09-27')).width, closeTo(tester.getSize(_col('2026-10-03')).width, 0.01));
      expect(find.descendant(of: _k('mweek-head-2026-09-27'), matching: find.text('27')), findsOneWidget);
      expect(find.descendant(of: _k('mweek-head-2026-09-27'), matching: find.text('D')), findsOneWidget);
      expect(find.descendant(of: _k('mweek-head-2026-09-29'), matching: find.text('T')), findsOneWidget);
      // Só o dia de hoje (segunda 28) tem o destaque.
      expect(_k('mweek-today'), findsOneWidget);
      expect(find.descendant(of: _k('mweek-head-2026-09-28'), matching: _k('mweek-today')), findsOneWidget);
      // Coluna de horas à esquerda.
      expect(find.text('9h'), findsOneWidget);
      expect(tester.getTopLeft(find.text('9h')).dx, lessThan(tester.getTopLeft(_col('2026-09-27')).dx));
    });

    testWidgets('evento cai no dia e na hora certos, com a cor da etiqueta', (tester) async {
      final repo = await _repo([_ev('e1', 'Cálculo', minutes: 100, tagId: 't-aula')]);
      await _pumpWeek(tester, repo);
      final col = tester.getRect(_col('2026-09-29'));
      final r = tester.getRect(_block('e1', '2026-09-29'));
      expect(r.top - col.top, closeTo(10 * 48, 0.01));
      expect(r.height, closeTo(100 / 60 * 48 - 1, 0.01));
      expect(r.left, greaterThanOrEqualTo(col.left));
      expect(r.right, lessThanOrEqualTo(col.right));
      expect(tester.widget<ColoredBox>(_k('tag-bar-e1-2026-09-29')).color, const Color(0xFF3E63DD));
      expect(_block('e1', '2026-09-28'), findsNothing);
      expect(_block('e1', '2026-09-30'), findsNothing);
    });

    testWidgets('eventos sobrepostos ficam lado a lado, os outros ocupam a coluna toda', (tester) async {
      final repo = await _repo([
        _ev('a', 'A', tagId: 't-aula'),
        _ev('b', 'B', minute: 30, tagId: 't-acad'),
        _ev('c', 'C', hour: 14),
      ]);
      await _pumpWeek(tester, repo);
      final col = tester.getRect(_col('2026-09-29'));
      final a = tester.getRect(_block('a', '2026-09-29'));
      final b = tester.getRect(_block('b', '2026-09-29'));
      final c = tester.getRect(_block('c', '2026-09-29'));
      expect(a.top, lessThan(b.top));
      expect(a.right, lessThanOrEqualTo(b.left + 0.01));
      expect(a.width, closeTo(b.width, 0.01));
      expect(a.width, closeTo(col.width / 2 - 3, 0.01));
      expect(c.width, closeTo(col.width - 3, 0.01));
    });

    testWidgets('bloco largo mostra o título; bloco estreito, só a barra de cor e o horário', (tester) async {
      final repo = await _repo([
        _ev('a', 'Cálculo', tagId: 't-aula'),
        _ev('b', 'Treino', minute: 30, tagId: 't-acad'),
        _ev('c', 'Reunião', hour: 14, tagId: 't-aula'),
      ]);
      await _pumpWeek(tester, repo);
      expect(find.descendant(of: _block('c', '2026-09-29'), matching: find.text('Reunião')), findsOneWidget);
      expect(find.descendant(of: _block('a', '2026-09-29'), matching: find.text('Cálculo')), findsNothing);
      expect(find.descendant(of: _block('a', '2026-09-29'), matching: find.text('10:00')), findsOneWidget);
      expect(find.descendant(of: _block('b', '2026-09-29'), matching: find.text('10:30')), findsOneWidget);
      expect(_k('tag-bar-a-2026-09-29'), findsOneWidget);
      expect(_k('tag-bar-b-2026-09-29'), findsOneWidget);
    });

    testWidgets('título longo é abreviado com reticências', (tester) async {
      final repo = await _repo([_ev('a', 'Seminário de sistemas distribuídos e computação em nuvem', tagId: 't-aula')]);
      await _pumpWeek(tester, repo);
      final t = tester.widget<Text>(find.descendant(
          of: _block('a', '2026-09-29'), matching: find.textContaining('Seminário')));
      expect(t.overflow, TextOverflow.ellipsis);
      expect(tester.takeException(), isNull);
    });

    testWidgets('evento de dia inteiro vai para a faixa do topo, não para a grade', (tester) async {
      final repo = await _repo([_ev('f', 'Feriado', day: 30, allDay: true)]);
      await _pumpWeek(tester, repo);
      expect(_k('mweek-allday-f'), findsOneWidget);
      expect(find.text('Feriado'), findsOneWidget);
      expect(_block('f', '2026-09-30'), findsNothing);
      await tester.tap(_k('mweek-allday-f'));
      await tester.pumpAndSettle();
      expect(find.text('Editar evento'), findsOneWidget);
    });

    testWidgets('evento que vira a meia-noite aparece nos dois dias', (tester) async {
      final repo = await _repo([
        CalendarEvent(
            id: 'p', title: 'Plantão', startsAt: DateTime(2026, 9, 28, 23, 30), endsAt: DateTime(2026, 9, 29, 0, 15)),
      ]);
      await _pumpWeek(tester, repo);
      expect(_block('p', '2026-09-28'), findsOneWidget);
      expect(_block('p', '2026-09-29'), findsOneWidget);
    });

    testWidgets('linha da hora atual só no dia de hoje e só na semana de hoje', (tester) async {
      await _pumpWeek(tester, await _repo());
      expect(_k('mweek-now-line'), findsOneWidget);
      expect(find.descendant(of: _col('2026-09-28'), matching: _k('mweek-now-line')), findsOneWidget);
      final line = tester.getRect(_k('mweek-now-line'));
      final col = tester.getRect(_col('2026-09-28'));
      expect(line.top - col.top, closeTo(10 * 48, 2));
      await _swipe(tester, next: true);
      expect(_k('mweek-now-line'), findsNothing);
      expect(_k('mweek-today'), findsNothing);
    });

    testWidgets('abre rolada na hora atual', (tester) async {
      await _pumpWeek(tester, await _repo());
      final grid = tester.getRect(_k('mweek-grid-2026-09-27'));
      final line = tester.getRect(_k('mweek-now-line'));
      expect(line.top, greaterThan(grid.top));
      expect(line.bottom, lessThan(grid.bottom));
    });

    testWidgets('abre rolada no primeiro evento da semana quando ele é antes da hora atual', (tester) async {
      final repo = await _repo([_ev('m', 'Madrugada', hour: 6)]);
      await _pumpWeek(tester, repo);
      final grid = tester.getRect(_k('mweek-grid-2026-09-27'));
      final r = tester.getRect(_block('m', '2026-09-29'));
      expect(r.top, greaterThanOrEqualTo(grid.top));
      expect(r.top, lessThan(grid.top + 120));
    });
  });

  group('gestos', () {
    testWidgets('deslizar troca de semana e "Hoje" volta', (tester) async {
      final repo = await _repo([_ev('e1', 'Cálculo', hour: 14), _ev('e2', 'Prova', month: 10, day: 6, hour: 14)]);
      await _pumpWeek(tester, repo);
      expect(find.text('27 set – 3 out 2026'), findsOneWidget);
      expect(find.text('Cálculo'), findsOneWidget);

      await _swipe(tester, next: true);
      expect(find.text('4 – 10 out 2026'), findsOneWidget);
      expect(find.text('Cálculo'), findsNothing);
      expect(find.text('Prova'), findsOneWidget);
      expect(find.byKey(const ValueKey('mweek-head-2026-10-04')), findsOneWidget);

      await _swipe(tester, next: true);
      expect(find.text('11 – 17 out 2026'), findsOneWidget);
      await _swipe(tester, next: false);
      expect(find.text('4 – 10 out 2026'), findsOneWidget);
      await _swipe(tester, next: false);
      await _swipe(tester, next: false);
      expect(find.text('20 – 26 set 2026'), findsOneWidget);

      await tester.tap(find.byKey(const Key('today')));
      await tester.pumpAndSettle();
      expect(find.text('27 set – 3 out 2026'), findsOneWidget);
      expect(find.text('Cálculo'), findsOneWidget);
      expect(_k('mweek-today'), findsOneWidget);
    });

    testWidgets('as setas de semana também navegam', (tester) async {
      await _pumpWeek(tester, await _repo([_ev('e2', 'Prova', month: 10, day: 6, hour: 14)]));
      await tester.tap(find.byKey(const Key('next-week')));
      await tester.pumpAndSettle();
      expect(find.text('4 – 10 out 2026'), findsOneWidget);
      expect(find.text('Prova'), findsOneWidget);
      await tester.tap(find.byKey(const Key('prev-week')));
      await tester.pumpAndSettle();
      expect(find.text('27 set – 3 out 2026'), findsOneWidget);
    });

    testWidgets('a rolagem vertical é a mesma ao trocar de semana', (tester) async {
      await _pumpWeek(tester, await _repo());
      await tester.drag(_k('mweek-grid-2026-09-27'), const Offset(0, -150));
      await tester.pumpAndSettle();
      final before = tester.getRect(_col('2026-09-27')).top;
      await _swipe(tester, next: true);
      expect(tester.getRect(_col('2026-10-04')).top, closeTo(before, 0.5));
    });

    testWidgets('tocar no evento abre o editor', (tester) async {
      await _pumpWeek(tester, await _repo([_ev('e1', 'Cálculo', hour: 14, tagId: 't-aula')]));
      await tester.tap(_block('e1', '2026-09-29'));
      await tester.pumpAndSettle();
      expect(find.text('Editar evento'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Cálculo'), findsOneWidget);
    });

    testWidgets('segurar um horário vazio cria evento de 1 h, com início na meia hora mais próxima',
        (tester) async {
      final repo = await _repo();
      await _pumpWeek(tester, repo);
      final top = tester.getTopLeft(_col('2026-09-29'));
      // 14:20 → 14:30.
      await tester.longPressAt(top + const Offset(10, (14 * 60 + 20) * 48 / 60));
      await tester.pumpAndSettle();
      expect(find.text('Novo evento'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('event-start-time')), matching: find.text('14:30')),
          findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('event-end-time')), matching: find.text('15:30')),
          findsOneWidget);
      // Repetição e etiqueta vêm do mesmo fluxo de criação.
      expect(find.byKey(const Key('event-repeat')), findsOneWidget);
      expect(find.byKey(const Key('event-tag-t-aula')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('event-title')), 'Estudo');
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      final saved = (await repo.watchEvents(from: _from).first).single;
      expect(saved.startsAt, DateTime(2026, 9, 29, 14, 30));
      expect(saved.endsAt, DateTime(2026, 9, 29, 15, 30));
      expect(_block(saved.id, '2026-09-29'), findsOneWidget);
    });

    testWidgets('segurar em cima de um evento não cria outro', (tester) async {
      final repo = await _repo([_ev('e1', 'Cálculo', hour: 14, tagId: 't-aula')]);
      await _pumpWeek(tester, repo);
      await tester.longPress(_block('e1', '2026-09-29'));
      await tester.pumpAndSettle();
      expect(find.text('Novo evento'), findsNothing);
    });

    testWidgets('segurar perto da meia-noite não passa do fim do dia', (tester) async {
      final repo = await _repo();
      await _pumpWeek(tester, repo);
      await tester.drag(_k('mweek-grid-2026-09-27'), const Offset(0, -2000));
      await tester.pumpAndSettle();
      final top = tester.getTopLeft(_col('2026-09-29'));
      await tester.longPressAt(top + const Offset(10, 23.9 * 48));
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byKey(const Key('event-start-time')), matching: find.text('23:30')),
          findsOneWidget);
    });

    testWidgets('pinça vertical muda a altura da hora, entre 32 e 120, e a lembra', (tester) async {
      final repo = await _repo([_ev('e1', 'Cálculo', hour: 14, tagId: 't-aula')]);
      final prefs = await _pumpWeek(tester, repo);
      double height() => tester.getSize(_block('e1', '2026-09-29')).height;
      expect(height(), closeTo(47, 0.01));

      Future<void> pinch(double fromDy, double toDy) async {
        const x = 200.0;
        final g1 = await tester.startGesture(const Offset(x, 400 - 0), pointer: 11);
        final g2 = await tester.startGesture(Offset(x, 400 + fromDy), pointer: 12);
        await tester.pump();
        await g2.moveTo(Offset(x, 400 + toDy));
        await tester.pump();
        await g1.up();
        await g2.up();
        await tester.pumpAndSettle();
      }

      await pinch(100, 200); // ×2
      expect(height(), closeTo(95, 0.01));
      expect(prefs.hourHeight, 96);
      expect(tester.takeException(), isNull);

      await pinch(100, 1000); // passa do limite
      expect(height(), closeTo(119, 0.01));
      expect(prefs.hourHeight, 120);

      await pinch(300, 20); // encolhe além do limite
      expect(height(), closeTo(31, 0.01));
      expect(prefs.hourHeight, 32);
    });

    testWidgets('a pinça não troca de semana nem rola', (tester) async {
      final repo = await _repo([_ev('e1', 'Cálculo', hour: 14, tagId: 't-aula')]);
      await _pumpWeek(tester, repo);
      final g1 = await tester.startGesture(const Offset(100, 400), pointer: 21);
      final g2 = await tester.startGesture(const Offset(300, 400), pointer: 22);
      await tester.pump();
      await g1.moveTo(const Offset(20, 400));
      await g2.moveTo(const Offset(380, 400));
      await tester.pump();
      await g1.up();
      await g2.up();
      await tester.pumpAndSettle();
      expect(find.text('27 set – 3 out 2026'), findsOneWidget);
    });

    testWidgets('altura da hora guardada vale ao reabrir', (tester) async {
      final repo = await _repo([_ev('e1', 'Cálculo', hour: 14, tagId: 't-aula')]);
      await _pumpWeek(tester, repo, prefs: MemoryAgendaViewPrefs(view: 'week', hourHeight: 80));
      expect(tester.getSize(_block('e1', '2026-09-29')).height, closeTo(79, 0.01));
    });
  });

  group('filtros e acessibilidade', () {
    testWidgets('o filtro de etiqueta esconde e mostra os eventos na semana', (tester) async {
      final repo = await _repo([
        _ev('a', 'Cálculo', hour: 14, tagId: 't-aula'),
        _ev('b', 'Treino', hour: 17, tagId: 't-acad'),
        _ev('c', 'Dentista', hour: 12),
      ]);
      await _pumpWeek(tester, repo);
      expect(find.text('Cálculo'), findsOneWidget);
      await tester.tap(find.byKey(const Key('tag-filter-t-aula')));
      await tester.pumpAndSettle();
      expect(_block('a', '2026-09-29'), findsNothing);
      expect(_block('b', '2026-09-29'), findsOneWidget);
      expect(_block('c', '2026-09-29'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('tag-filter-none')));
      await tester.tap(find.byKey(const Key('tag-filter-none')));
      await tester.pumpAndSettle();
      expect(_block('c', '2026-09-29'), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('tag-filter-t-aula')));
      await tester.tap(find.byKey(const Key('tag-filter-t-aula')));
      await tester.pumpAndSettle();
      expect(_block('a', '2026-09-29'), findsOneWidget);
    });

    testWidgets('blocos têm rótulo semântico com título, dia e horário', (tester) async {
      final handle = tester.ensureSemantics();
      final repo = await _repo([
        _ev('a', 'Aula M02', minutes: 100, tagId: 't-aula'),
        CalendarEvent(
            id: 'p', title: 'Plantão', startsAt: DateTime(2026, 9, 28, 23, 30), endsAt: DateTime(2026, 9, 29, 0, 15)),
        _ev('f', 'Feriado', day: 30, allDay: true),
      ]);
      await _pumpWeek(tester, repo);
      expect(tester.getSemantics(_block('a', '2026-09-29')).label, 'Aula M02, terça 10:00 a 11:40');
      expect(tester.getSemantics(_k('mweek-allday-f')).label, 'Feriado, quarta, dia inteiro');
      expect(find.bySemanticsLabel('Plantão, segunda 23:30 a terça 00:15'), findsNWidgets(2));
      handle.dispose();
    });
  });

  group('telas pequenas e fonte grande', () {
    testWidgets('360 dp com fonte 1,3x: semana cheia, sobreposição, dia inteiro e pinça sem estourar',
        (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final repo = await _repo([
        _ev('a', 'Seminário de pesquisa em sistemas distribuídos', tagId: 't-aula'),
        _ev('b', 'Treino de força e condicionamento', minute: 15, tagId: 't-acad'),
        _ev('c', 'Reunião de orientação com o grupo', minute: 30),
        _ev('d', 'Almoço com a turma toda do curso', minute: 45, minutes: 20),
        _ev('f1', 'Feriado municipal de aniversário da cidade', day: 30, allDay: true),
        _ev('f2', 'Prazo final da entrega do relatório', day: 30, allDay: true),
        _ev('f3', 'Aniversário', day: 30, allDay: true),
        _ev('g', 'Plantão noturno', month: 10, day: 1, hour: 23, minutes: 120),
      ]);
      await _pumpWeek(tester, repo, size: const Size(360, 740));
      expect(tester.takeException(), isNull);
      expect(_k('mobile-week'), findsOneWidget);

      await tester.drag(_k('mweek-grid-2026-09-27'), const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final g1 = await tester.startGesture(const Offset(180, 300), pointer: 31);
      final g2 = await tester.startGesture(const Offset(180, 340), pointer: 32);
      await tester.pump();
      await g2.moveTo(const Offset(180, 700));
      await tester.pump();
      await g1.up();
      await g2.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await _swipe(tester, next: true);
      expect(tester.takeException(), isNull);
    });
  });
}
