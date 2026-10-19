import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/domain/calendar_event.dart';
import 'package:organizacional/features/agenda/agenda_view_prefs.dart';
import 'package:organizacional/features/agenda/calendar_common.dart';
import 'package:organizacional/features/agenda/calendar_layout.dart';
import 'package:shared_preferences/shared_preferences.dart';

CalendarEvent _ev(String id, String title, DateTime s, DateTime e, {bool allDay = false}) =>
    CalendarEvent(id: id, title: title, startsAt: s, endsAt: e, allDay: allDay);

void main() {
  group('preferências da visão no celular (SharedPreferences)', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('guarda e devolve a visão e a altura da hora por aparelho', () async {
      const prefs = SharedPreferencesAgendaViewPrefs();
      expect(await prefs.loadView(), isNull);
      expect(await prefs.loadHourHeight(), isNull);
      await prefs.saveView('week');
      await prefs.saveHourHeight(72.5);
      expect(await prefs.loadView(), 'week');
      expect(await prefs.loadHourHeight(), 72.5);
      final raw = await SharedPreferences.getInstance();
      expect(raw.getString('agenda_mobile_view'), 'week');
      expect(raw.getDouble('agenda_hour_height'), 72.5);
    });

    test('valor de outro tipo vira "sem preferência", sem erro', () async {
      SharedPreferences.setMockInitialValues({'agenda_mobile_view': 3, 'agenda_hour_height': 'alto'});
      const prefs = SharedPreferencesAgendaViewPrefs();
      expect(await prefs.loadView(), isNull);
      expect(await prefs.loadHourHeight(), isNull);
    });
  });

  group('altura da hora', () {
    test('fica entre 32 e 120', () {
      expect(clampHourHeight(10), 32);
      expect(clampHourHeight(48), 48);
      expect(clampHourHeight(500), 120);
    });

    test('o provider restaura o valor guardado (com limite) e só grava ao confirmar', () async {
      final prefs = MemoryAgendaViewPrefs(hourHeight: 200);
      final c = ProviderContainer(overrides: [agendaViewPrefsProvider.overrideWithValue(prefs)]);
      addTearDown(c.dispose);
      expect(c.read(agendaHourHeightProvider), 48);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(agendaHourHeightProvider), 120);

      c.read(agendaHourHeightProvider.notifier).preview(20);
      expect(c.read(agendaHourHeightProvider), 32);
      expect(prefs.hourHeight, 200, reason: 'prévia não grava');
      c.read(agendaHourHeightProvider.notifier).commit();
      await Future<void>.delayed(Duration.zero);
      expect(prefs.hourHeight, 32);
    });

    test('preferência antiga não sobrescreve uma escolha já feita', () async {
      final prefs = MemoryAgendaViewPrefs(hourHeight: 100);
      final c = ProviderContainer(overrides: [agendaViewPrefsProvider.overrideWithValue(prefs)]);
      addTearDown(c.dispose);
      c.read(agendaHourHeightProvider);
      c.read(agendaHourHeightProvider.notifier).preview(60);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(agendaHourHeightProvider), 60);
    });
  });

  group('visão escolhida', () {
    test('começa em Mês, restaura "week" e grava ao escolher', () async {
      final prefs = MemoryAgendaViewPrefs(view: 'week');
      final c = ProviderContainer(overrides: [agendaViewPrefsProvider.overrideWithValue(prefs)]);
      addTearDown(c.dispose);
      expect(c.read(agendaMobileViewProvider), MobileAgendaView.month);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(agendaMobileViewProvider), MobileAgendaView.week);
      c.read(agendaMobileViewProvider.notifier).select(MobileAgendaView.month);
      await Future<void>.delayed(Duration.zero);
      expect(prefs.view, 'month');
    });

    test('valor desconhecido guardado mantém Mês', () async {
      final prefs = MemoryAgendaViewPrefs(view: 'ano');
      final c = ProviderContainer(overrides: [agendaViewPrefsProvider.overrideWithValue(prefs)]);
      addTearDown(c.dispose);
      c.read(agendaMobileViewProvider);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(agendaMobileViewProvider), MobileAgendaView.month);
    });
  });

  group('rótulo semântico do evento', () {
    final tue = DateTime(2026, 9, 29);

    test('mesmo dia: título, dia da semana e horário', () {
      final e = _ev('a', 'Aula M02', DateTime(2026, 9, 29, 10), DateTime(2026, 9, 29, 11, 40));
      expect(eventSemanticLabel(e, tue), 'Aula M02, terça 10:00 a 11:40');
    });

    test('vira a meia-noite: cita os dois dias', () {
      final e = _ev('p', 'Plantão', DateTime(2026, 9, 28, 23, 30), DateTime(2026, 9, 29, 0, 15));
      expect(eventSemanticLabel(e, tue), 'Plantão, segunda 23:30 a terça 00:15');
      expect(eventSemanticLabel(e, DateTime(2026, 9, 28)), 'Plantão, segunda 23:30 a terça 00:15');
    });

    test('termina à meia-noite em ponto: continua sendo do mesmo dia', () {
      final e = _ev('n', 'Jantar', DateTime(2026, 9, 29, 22), DateTime(2026, 9, 30));
      expect(eventSemanticLabel(e, tue), 'Jantar, terça 22:00 a 00:00');
    });

    test('dia inteiro', () {
      final e = _ev('d', 'Feriado', DateTime(2026, 9, 29), DateTime(2026, 9, 30), allDay: true);
      expect(eventSemanticLabel(e, tue), 'Feriado, terça, dia inteiro');
    });

    test('nomes dos dias, domingo a sábado', () {
      expect([for (var i = 0; i < 7; i++) weekdayName(DateTime(2026, 9, 27 + i))],
          ['domingo', 'segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado']);
      expect(weekdayInitials, ['D', 'S', 'T', 'Q', 'Q', 'S', 'S']);
    });
  });

  group('hora em que a semana abre rolada', () {
    final sun = DateTime(2026, 9, 27);

    test('sem eventos: a hora atual', () {
      expect(weekFocusMinute(const [], sun, DateTime(2026, 9, 28, 10, 20)), 10 * 60 + 20);
    });

    test('primeiro evento da semana antes da hora atual: ele', () {
      final e = _ev('a', 'Cedo', DateTime(2026, 9, 29, 6, 30), DateTime(2026, 9, 29, 7));
      expect(weekFocusMinute([e], sun, DateTime(2026, 9, 28, 10)), 6 * 60 + 30);
    });

    test('primeiro evento depois da hora atual: a hora atual', () {
      final e = _ev('a', 'Tarde', DateTime(2026, 9, 29, 15), DateTime(2026, 9, 29, 16));
      expect(weekFocusMinute([e], sun, DateTime(2026, 9, 28, 10)), 10 * 60);
    });

    test('dia inteiro e eventos de fora da semana não contam', () {
      final allDay = _ev('d', 'Feriado', DateTime(2026, 9, 29), DateTime(2026, 9, 30), allDay: true);
      final outside = _ev('o', 'Outra semana', DateTime(2026, 10, 6, 5), DateTime(2026, 10, 6, 6));
      expect(weekFocusMinute([allDay, outside], sun, DateTime(2026, 9, 28, 10)), 10 * 60);
    });
  });
}
