import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/location_repository.dart';
import 'package:organizacional/domain/calendar_event.dart';
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

  group('buildNowNext', () {
    test('em andamento, próximos e sobra', () {
      final nn = buildNowNext(_now, [
        _ev('a', 'Em curso', DateTime(2026, 9, 28, 9, 30)),
        _ev('b', 'Já foi', DateTime(2026, 9, 28, 7), length: const Duration(minutes: 30)),
        _ev('c', 'Depois 1', DateTime(2026, 9, 28, 11)),
        _ev('d', 'Depois 2', DateTime(2026, 9, 28, 14)),
        _ev('e', 'Depois 3', DateTime(2026, 9, 28, 18)),
        _ev('f', 'Dia todo', DateTime(2026, 9, 28), allDay: true, length: const Duration(days: 1)),
      ]);
      expect(nn.current.map((e) => e.id), ['a']);
      expect(nn.upcoming.map((e) => e.id), ['c', 'd', 'e']);
      expect(nn.allDay.map((e) => e.id), ['f']);
      expect(nn.todayCount, 6);
      expect(nn.freeDay, isFalse);
    });

    test('agenda livre mostra o próximo dia com evento', () {
      final nn = buildNowNext(_now, [
        _ev('x', 'Depois de amanhã', DateTime(2026, 9, 30, 8)),
        _ev('y', 'Amanhã', DateTime(2026, 9, 29, 8)),
      ]);
      expect(nn.freeDay, isTrue);
      expect(nn.nothingLeft, isTrue);
      expect(nn.nextDayEvent!.id, 'y');
    });

    test('só eventos que já terminaram: nada mais por hoje, mas não é dia livre', () {
      final nn = buildNowNext(_now, [_ev('a', 'Cedo', DateTime(2026, 9, 28, 7))]);
      expect(nn.nothingLeft, isTrue);
      expect(nn.freeDay, isFalse);
    });
  });

  group('nextExam', () {
    test('escolhe a prova mais próxima na janela de 30 dias', () {
      final info = nextExam(_now, [
        _ev('a', 'Prova de Redes', DateTime(2026, 10, 10, 8)),
        _ev('b', 'NP1 Cálculo', DateTime(2026, 9, 30, 10)),
        _ev('c', 'Aula comum', DateTime(2026, 9, 29, 8)),
      ])!;
      expect(info.event.id, 'b');
      expect(info.days, 2);
      expect(examWhen(info), 'em 2 dias');
    });

    test('amanhã e hoje trazem o horário; dia inteiro não', () {
      final tomorrow = nextExam(_now, [_ev('a', 'Prova X', DateTime(2026, 9, 29, 10))])!;
      expect(examWhen(tomorrow), 'amanhã às 10:00');
      final today = nextExam(_now, [_ev('a', 'Prova X', DateTime(2026, 9, 28, 15))])!;
      expect(examWhen(today), 'hoje às 15:00');
      final allDay = nextExam(_now, [
        _ev('a', 'Prova X', DateTime(2026, 9, 29), allDay: true, length: const Duration(days: 1)),
      ])!;
      expect(examWhen(allDay), 'amanhã');
    });

    test('em andamento, fora da janela e já terminada', () {
      final running = nextExam(_now, [_ev('a', 'Prova X', DateTime(2026, 9, 28, 9), length: const Duration(hours: 2))])!;
      expect(running.inProgress, isTrue);
      expect(examWhen(running), 'em andamento');
      expect(nextExam(_now, [_ev('a', 'Prova X', DateTime(2026, 11, 5, 9))]), isNull);
      expect(nextExam(_now, [_ev('a', 'Prova X', DateTime(2026, 9, 28, 7))]), isNull);
      expect(nextExam(_now, [_ev('a', 'Prova X', DateTime(2026, 10, 28, 9))]), isNotNull); // 30 dias
    });
  });

  group('pickDashboardTasks', () {
    TaskItem t(String id, {DateTime? due, TaskStatus status = TaskStatus.todo}) =>
        TaskItem(id: id, title: id, dueAt: due, status: status);

    test('atrasadas, hoje e em andamento, nessa ordem, sem repetir', () {
      final picks = pickDashboardTasks(_now, [
        t('futura'),
        t('hoje', due: DateTime(2026, 9, 28, 23, 59)),
        t('atrasada', due: DateTime(2026, 9, 20)),
        t('fazendo', status: TaskStatus.doing),
        t('fazendo-hoje', due: DateTime(2026, 9, 28, 23, 59), status: TaskStatus.doing),
        t('feita', due: DateTime(2026, 9, 20), status: TaskStatus.done),
      ]);
      expect(picks.overdue.map((e) => e.id), ['atrasada']);
      expect(picks.today.map((e) => e.id), ['hoje', 'fazendo-hoje']);
      expect(picks.doing.map((e) => e.id), ['fazendo']);
      expect(picks.hidden, 0);
      expect(picks.pending, 5);
    });

    test('limita a 5 e conta as que ficaram de fora', () {
      final picks = pickDashboardTasks(_now, [
        for (var i = 0; i < 4; i++) t('o$i', due: DateTime(2026, 9, 20 + i)),
        for (var i = 0; i < 4; i++) t('h$i', due: DateTime(2026, 9, 28, 23, 59)),
      ]);
      expect(picks.shown, 5);
      expect(picks.overdue.length, 4);
      expect(picks.today.length, 1);
      expect(picks.hidden, 3);
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
