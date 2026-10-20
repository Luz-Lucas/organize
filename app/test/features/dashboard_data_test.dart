import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/location_repository.dart';
import 'package:organizacional/domain/calendar_event.dart';
import 'package:organizacional/domain/event_tag.dart';
import 'package:organizacional/domain/home_presence.dart';
import 'package:organizacional/domain/task_item.dart';
import 'package:organizacional/domain/user_settings.dart';
import 'package:organizacional/features/today/dashboard_data.dart';
import 'package:organizacional/location/location_service.dart';
import 'package:organizacional/widgets/widget_snapshot.dart';

CalendarEvent _ev(String id, String title, DateTime start,
        {Duration length = const Duration(hours: 1), bool allDay = false, String? location}) =>
    CalendarEvent(
      id: id,
      title: title,
      startsAt: start,
      endsAt: start.add(length),
      allDay: allDay,
      location: location,
    );

final _now = DateTime(2026, 9, 28, 10);

void main() {
  group('isExamTitle', () {
    test('segue exatamente a regra dos widgets (kind prova)', () {
      const titles = ['Prova de Cálculo', 'prova 2', ' NP1 Física', 'np2', 'NPS', 'Aula', 'A01', 'Reprova', ''];
      for (final t in titles) {
        final snap = buildWidgetSnapshot(
          now: _now,
          events: [_ev('x', t, _now)],
          tasks: const [],
          themeId: 'violeta',
        );
        final kind = (jsonDecode(snap['w_events']!) as List).single['kind'];
        expect(isExamTitle(t), kind == 'prova', reason: '"$t"');
      }
    });
  });

  group('buildTodayPlan', () {
    const aula = EventTag(id: 'aula', name: 'Aula', color: '#3366FF', role: EventTagRole.main);
    const sec = EventTag(id: 'sec', name: 'Lembrete', color: '#999999', role: EventTagRole.secondary);
    const gym = EventTag(id: 'gym', name: 'Academia', color: '#00AA00');
    final tags = {for (final t in [aula, sec, gym]) t.id: t};

    CalendarEvent ev(String id, String title, DateTime start,
            {String? tagId, String? seriesId, bool allDay = false, Duration length = const Duration(hours: 1)}) =>
        CalendarEvent(
          id: id,
          title: title,
          startsAt: start,
          endsAt: start.add(length),
          allDay: allDay,
          tagId: tagId,
          seriesId: seriesId,
        );

    TaskItem t(String id, {DateTime? due, TaskStatus status = TaskStatus.todo}) =>
        TaskItem(id: id, title: id, dueAt: due, status: status);

    List<String> ids(TodayPlan p) => p.events.map((e) => e.id).toList();

    test('só eventos de hoje, dia inteiro primeiro e depois por início', () {
      final p = buildTodayPlan(_now, [
        ev('tarde', 'Física', DateTime(2026, 9, 28, 14)),
        ev('cedo', 'Cálculo', DateTime(2026, 9, 28, 8)),
        ev('dia', 'Feriado', DateTime(2026, 9, 28), allDay: true, length: const Duration(days: 1)),
        ev('amanha', 'Amanhã', DateTime(2026, 9, 29, 8)),
      ], tags, const []);
      expect(ids(p), ['dia', 'cedo', 'tarde']);
    });

    test('academia sai por título e por nome da etiqueta', () {
      final p = buildTodayPlan(_now, [
        ev('a', 'Academia', DateTime(2026, 9, 28, 6)),
        ev('b', 'Treino de pernas', DateTime(2026, 9, 28, 7)),
        ev('c', 'Sessão qualquer', DateTime(2026, 9, 28, 18), tagId: 'gym'),
        ev('d', 'Cálculo', DateTime(2026, 9, 28, 8), tagId: 'aula'),
      ], tags, const []);
      expect(ids(p), ['d']);
    });

    test('etiqueta secundária sai', () {
      final p = buildTodayPlan(_now, [
        ev('a', 'Lembrar de algo', DateTime(2026, 9, 28, 9), tagId: 'sec'),
        ev('b', 'Cálculo', DateTime(2026, 9, 28, 8), tagId: 'aula'),
      ], tags, const []);
      expect(ids(p), ['b']);
    });

    test('série que se repete todo dia (5 ou mais em 7 dias) sai; aula semanal fica', () {
      final daily = [
        for (var i = 0; i < 7; i++) ev('d$i', 'Remédio', DateTime(2026, 9, 28 + i, 9), seriesId: 'rem'),
      ];
      final weekly = [
        for (var i = 0; i < 3; i++) ev('w$i', 'Redes', DateTime(2026, 9, 28 + 7 * i, 19), seriesId: 'redes'),
      ];
      final p = buildTodayPlan(_now, [...daily, ...weekly], tags, const []);
      expect(ids(p), ['w0']);
    });

    test('série com 4 ocorrências na semana ainda aparece; a 5ª fora da janela não conta', () {
      final four = [
        for (var i = 0; i < 4; i++) ev('q$i', 'Monitoria', DateTime(2026, 9, 28 + i, 17), seriesId: 'mon'),
        ev('q4', 'Monitoria', DateTime(2026, 10, 5, 17), seriesId: 'mon'), // +7 dias: fora da janela
      ];
      expect(ids(buildTodayPlan(_now, four, tags, const [])), ['q0']);
    });

    test('tarefas: atrasada e de hoje entram; amanhã, sem data e concluída ficam de fora', () {
      final p = buildTodayPlan(_now, const [], tags, [
        t('amanha', due: DateTime(2026, 9, 29, 12)),
        t('hoje', due: DateTime(2026, 9, 28, 23, 59)),
        t('atrasada', due: DateTime(2026, 9, 20)),
        t('sem-data'),
        t('feita', due: DateTime(2026, 9, 28), status: TaskStatus.done),
      ]);
      expect(p.tasks.map((e) => e.id), ['atrasada', 'hoje']);
      expect(p.moreTasks, 0);
    });

    test('no máximo 5 tarefas, por prazo, e conta o resto', () {
      final p = buildTodayPlan(_now, const [], tags, [
        for (var i = 0; i < 4; i++) t('o$i', due: DateTime(2026, 9, 20 + i)),
        for (var i = 0; i < 4; i++) t('h$i', due: DateTime(2026, 9, 28, 23, 59)),
      ]);
      expect(p.tasks.length, 5);
      expect(p.tasks.first.id, 'o0');
      expect(p.moreTasks, 3);
    });

    group('tarefas de série', () {
      TaskItem occ(String id, DateTime due, {TaskStatus status = TaskStatus.todo}) =>
          TaskItem(id: id, title: 'Lab', dueAt: due, status: status, seriesId: 'lab');

      test('só a próxima pendente da série entra, mesmo com várias vencidas', () {
        final p = buildTodayPlan(_now, const [], tags, [
          occ('o1', DateTime(2026, 9, 15, 23, 59)),
          occ('o2', DateTime(2026, 9, 22, 23, 59)),
          occ('o3', DateTime(2026, 9, 28, 23, 59)),
        ]);
        expect(p.tasks.map((e) => e.id), ['o1']);
        expect(p.moreTasks, 0);
      });

      test('concluída a atrasada, aparece a seguinte', () {
        final p = buildTodayPlan(_now, const [], tags, [
          occ('o1', DateTime(2026, 9, 15, 23, 59), status: TaskStatus.done),
          occ('o2', DateTime(2026, 9, 22, 23, 59)),
          occ('o3', DateTime(2026, 9, 28, 23, 59)),
        ]);
        expect(p.tasks.map((e) => e.id), ['o2']);
      });

      test('próxima de uma semana à frente não entra; série inteira concluída não quebra', () {
        final future = buildTodayPlan(_now, const [], tags, [
          occ('o1', DateTime(2026, 9, 28, 23, 59), status: TaskStatus.done),
          occ('o2', DateTime(2026, 10, 5, 23, 59)),
        ]);
        expect(future.tasks, isEmpty);
        final allDone = buildTodayPlan(_now, const [], tags, [
          occ('o1', DateTime(2026, 9, 21, 23, 59), status: TaskStatus.done),
          occ('o2', DateTime(2026, 9, 28, 23, 59), status: TaskStatus.done),
        ]);
        expect(allDone.tasks, isEmpty);
        expect(allDone.moreTasks, 0);
      });
    });
  });

  group('presenceChip', () {
    const home = UserSettings(homeLat: -19.9320, homeLon: -43.9380);
    LocationReport at(double metersNorth, {Duration age = Duration.zero}) => LocationReport(
          fix: GeoFix(lat: -19.9320 + metersNorth / 111194.9, lon: -43.9380),
          reportedAt: _now.subtract(age),
        );

    test('sem casa não mostra nada', () {
      expect(presenceChip(settings: const UserSettings(), last: at(0), now: _now), isNull);
      expect(presenceChip(settings: null, last: at(0), now: _now), isNull);
    });

    test('em casa, fora e indisponível', () {
      expect(presenceChip(settings: home, last: at(10), now: _now)!.label, 'Em casa');
      final away = presenceChip(settings: home, last: at(5000), now: _now)!;
      expect(away.state, PresenceState.away);
      expect(away.label, 'Fora (a 5,0 km)');
      expect(presenceChip(settings: home, last: null, now: _now)!.label, 'Local indisponível');
      expect(presenceChip(settings: home, last: at(10, age: const Duration(hours: 2)), now: _now)!.label,
          'Local indisponível');
    });
  });
}
