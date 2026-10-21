import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/domain/calendar_event.dart';
import 'package:organizacional/domain/recurrence.dart';
import 'package:organizacional/domain/reminders.dart';
import 'package:organizacional/domain/task_item.dart';
import 'package:organizacional/domain/task_series.dart';
import 'package:organizacional/domain/user_settings.dart';

void main() {
  group('opções', () {
    test('quatro antecedências em minutos, da maior para a menor', () {
      expect(reminderOptions, [1440, 60, 30, 15]);
      expect(defaultTaskReminders, [60]);
      expect(defaultEventReminders, [30]);
    });

    test('rótulos', () {
      expect([for (final m in reminderOptions) reminderLabel(m)], ['1 dia', '1 hora', '30 min', '15 min']);
    });

    test('normalizeReminders tira inválidos e repetidos e ordena', () {
      expect(normalizeReminders([15, 60, 7, 60, 1440]), [1440, 60, 15]);
      expect(normalizeReminders(const []), isEmpty);
    });
  });

  group('TaskItem.reminders', () {
    test('padrão é [60]', () {
      expect(const TaskItem(id: 'a', title: 't').reminders, [60]);
    });

    test('fromMap lê a coluna; ausente ou inválida cai no padrão', () {
      final base = {'id': 'a', 'title': 't', 'status': 'todo'};
      expect(TaskItem.fromMap({...base, 'reminders': [1440, 15]}).reminders, [1440, 15]);
      expect(TaskItem.fromMap({...base, 'reminders': <int>[]}).reminders, isEmpty);
      expect(TaskItem.fromMap(base).reminders, [60]);
      expect(TaskItem.fromMap({...base, 'reminders': null}).reminders, [60]);
      expect(TaskItem.fromMap({...base, 'reminders': 'x'}).reminders, [60]);
    });

    test('toMap grava reminders e a volta preserva', () {
      final t = const TaskItem(id: 'a', title: 't').copyWith(reminders: [30, 15]);
      expect(t.toMap()['reminders'], [30, 15]);
      expect(TaskItem.fromMap(t.toMap()), t);
    });

    test('copyWith mantém reminders e == considera a lista', () {
      final t = const TaskItem(id: 'a', title: 't', reminders: [15]);
      expect(t.copyWith(title: 'u').reminders, [15]);
      expect(t, const TaskItem(id: 'a', title: 't', reminders: [15]));
      expect(t == t.copyWith(reminders: [30]), isFalse);
      expect(t.hashCode, const TaskItem(id: 'a', title: 't', reminders: [15]).hashCode);
    });

    test('série: ocorrências copiam reminders e a edição em todas propaga', () {
      final tpl = TaskItem(id: 'tpl', title: 'Lab', dueAt: DateTime(2026, 10, 20, 23, 59), reminders: const [1440]);
      var n = 0;
      final series =
          TaskSeriesOps.buildSeries(tpl, Recurrence(freq: RepeatFreq.weekly, days: {2}, count: 3), () => 'i${++n}');
      expect(series.map((t) => t.reminders), everyElement([1440]));
      final edited = series.first.copyWith(reminders: [60, 15]);
      final out = TaskSeriesOps.applyEdit(series, series.first, edited, SeriesScope.all);
      expect(out.map((t) => t.reminders), everyElement([60, 15]));
    });
  });

  group('CalendarEvent.reminders', () {
    CalendarEvent ev({List<int>? r}) => CalendarEvent(
          id: 'e',
          title: 'x',
          startsAt: DateTime(2026, 10, 21, 15),
          endsAt: DateTime(2026, 10, 21, 16),
          reminders: r ?? const [30],
        );

    test('padrão é [30]', () {
      expect(CalendarEvent(id: 'e', title: 'x', startsAt: DateTime(2026), endsAt: DateTime(2026)).reminders, [30]);
    });

    test('fromMap/toMap', () {
      final m = ev(r: [60, 15]).toMap();
      expect(m['reminders'], [60, 15]);
      expect(CalendarEvent.fromMap(m), ev(r: [60, 15]));
      m.remove('reminders');
      expect(CalendarEvent.fromMap(m).reminders, [30]);
      expect(CalendarEvent.fromMap({...m, 'reminders': <int>[]}).reminders, isEmpty);
    });

    test('copyWith, withoutSpace e == preservam', () {
      final e = ev(r: [15]);
      expect(e.copyWith(title: 'y').reminders, [15]);
      expect(e.withoutSpace().reminders, [15]);
      expect(e == ev(r: [30]), isFalse);
    });

    test('série: ocorrências copiam reminders e edição em todas propaga', () {
      var n = 0;
      final series = SeriesOps.buildSeries(
          ev(r: [1440]), Recurrence(freq: RepeatFreq.daily, count: 3), () => 'i${++n}');
      expect(series.map((e) => e.reminders), everyElement([1440]));
      final edited = series.first.copyWith(reminders: [60]);
      final out = SeriesOps.applyEdit(series, series.first, edited, SeriesScope.all);
      expect(out.map((e) => e.reminders), everyElement([60]));
    });
  });

  group('UserSettings lembretes', () {
    test('padrões', () {
      const s = UserSettings();
      expect(s.remindersPhone, isTrue);
      expect(s.remindersAlexa, isTrue);
      expect(s.reminderEcho, isNull);
      expect(s.dndEnabled, isTrue);
      expect(s.dndStart, 23 * 60);
      expect(s.dndEnd, 10 * 60);
    });

    test('fromMap lê as colunas (time vira minutos do dia)', () {
      final s = UserSettings.fromMap({
        'reminders_phone': false,
        'reminders_alexa': false,
        'reminder_echo': 'ABC',
        'dnd_enabled': false,
        'dnd_start': '22:30:00',
        'dnd_end': '07:05',
      });
      expect(s.remindersPhone, isFalse);
      expect(s.remindersAlexa, isFalse);
      expect(s.reminderEcho, 'ABC');
      expect(s.dndEnabled, isFalse);
      expect(s.dndStart, 22 * 60 + 30);
      expect(s.dndEnd, 7 * 60 + 5);
    });

    test('ausentes ou inválidos caem nos padrões', () {
      final s = UserSettings.fromMap({'reminders_phone': 'sim', 'dnd_start': 'xx', 'dnd_end': null, 'reminder_echo': ''});
      expect(s.remindersPhone, isTrue);
      expect(s.dndStart, 23 * 60);
      expect(s.dndEnd, 10 * 60);
      expect(s.reminderEcho, isNull);
    });

    test('toMap escreve time como HH:MM e a volta preserva', () {
      final s = const UserSettings().copyWith(reminderEcho: 'ABC', dndStart: 22 * 60 + 30, dndEnd: 7 * 60 + 5, remindersAlexa: false);
      final m = s.toMap();
      expect(m['dnd_start'], '22:30');
      expect(m['dnd_end'], '07:05');
      expect(m['reminder_echo'], 'ABC');
      final r = UserSettings.fromMap(m);
      expect([r.reminderEcho, r.dndStart, r.dndEnd, r.remindersAlexa], ['ABC', 22 * 60 + 30, 7 * 60 + 5, false]);
    });

    test('copyWith limpa o Echo e preserva o resto', () {
      final s = const UserSettings(reminderEcho: 'ABC');
      expect(s.copyWith(theme: 'coral').reminderEcho, 'ABC');
      expect(s.copyWith(clearReminderEcho: true).reminderEcho, isNull);
      expect(s.copyWith(dndEnabled: false).dndEnabled, isFalse);
      expect(s.copyWith(remindersPhone: false).remindersPhone, isFalse);
    });

    test('formatMinutesOfDay', () {
      expect(formatMinutesOfDay(23 * 60), '23:00');
      expect(formatMinutesOfDay(7 * 60 + 5), '07:05');
    });
  });
}
