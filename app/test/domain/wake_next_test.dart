import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/domain/alexa.dart';
import 'package:organizacional/domain/wake_override.dart';
import 'package:organizacional/features/home/wake_next.dart';

void main() {
  final monday10 = DateTime(2026, 9, 28, 10); // segunda-feira
  const weekdays = [1, 2, 3, 4, 5];

  test('sem dias não há próxima vez', () {
    expect(nextWakeAt(const [], 7, 0, monday10), isNull);
    expect(wakeInLabel(const [], 7, 0, monday10), isNull);
  });

  test('horário de hoje que ainda não passou', () {
    expect(wakeInLabel(weekdays, 11, 20, monday10), 'Toca em 1 h 20 min');
    expect(wakeInLabel(weekdays, 10, 20, monday10), 'Toca em 20 min');
    expect(wakeInLabel(weekdays, 12, 0, monday10), 'Toca em 2 h');
  });

  test('já passou hoje: vai para o próximo dia escolhido', () {
    expect(nextWakeAt(weekdays, 7, 0, monday10), DateTime(2026, 9, 29, 7));
    expect(wakeInLabel(weekdays, 7, 0, monday10), 'Toca em 21 h');
    expect(nextWakeAt(const [1], 7, 0, monday10), DateTime(2026, 10, 5, 7));
    expect(wakeInLabel(const [1], 7, 0, monday10), 'Toca em 6 d 21 h');
  });

  test('só fim de semana, a partir de segunda', () {
    expect(nextWakeAt(const [6, 7], 8, 30, monday10), DateTime(2026, 10, 3, 8, 30));
  });

  group('nextOccurrenceDate: o dia que o "Só …" edita', () {
    const plan = WakePlan(id: 'p', label: 'Aula', days: [1, 2, 3, 4, 5], hour: 9, minute: 30, echoDeviceId: 'E');
    test('às 2 h de uma quinta, o toque das 9:30 é o de hoje', () {
      expect(nextOccurrenceDate(plan, const [], DateTime(2026, 10, 15, 2)), DateTime(2026, 10, 15));
    });
    test('depois do horário, passa para o próximo dia do plano', () {
      expect(nextOccurrenceDate(plan, const [], DateTime(2026, 10, 15, 10)), DateTime(2026, 10, 16));
      // sexta 10 h → segunda
      expect(nextOccurrenceDate(plan, const [], DateTime(2026, 10, 16, 10)), DateTime(2026, 10, 19));
    });
    test('um toque pulado continua sendo o próximo (para poder voltar ao normal)', () {
      final skip = WakeOverride.skip('p', DateTime(2026, 10, 15));
      expect(nextOccurrenceDate(plan, [skip], DateTime(2026, 10, 15, 2)), DateTime(2026, 10, 15));
      expect(nextWake(plan, [skip], DateTime(2026, 10, 15, 2)), DateTime(2026, 10, 16, 9, 30));
    });
    test('horário trocado vale para saber se já passou', () {
      final early = WakeOverride.at('p', DateTime(2026, 10, 15), 1, 0);
      expect(nextOccurrenceDate(plan, [early], DateTime(2026, 10, 15, 2)), DateTime(2026, 10, 16));
    });
    test('sem dias e sem exceções: null', () {
      expect(nextOccurrenceDate(plan.copyWith(days: const []), const [], DateTime(2026, 10, 15, 2)), isNull);
    });
  });

  test('dias com domingo primeiro', () {
    expect(daysSundayFirst.first, 7);
    expect(formatDays([1, 7, 3]), 'Dom, Seg, Qua');
  });
}
