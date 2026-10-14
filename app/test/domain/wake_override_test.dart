import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/domain/alexa.dart';
import 'package:organizacional/domain/wake_override.dart';
import 'package:organizacional/features/home/wake_next.dart';

void main() {
  group('WakeOverride', () {
    test('fromMap lê pulo e horário (time com segundos)', () {
      final skip = WakeOverride.fromMap({'plan_id': 'p1', 'run_date': '2026-09-29', 'skip': true, 'time': null});
      expect(skip, WakeOverride.skip('p1', DateTime(2026, 9, 29)));
      final at = WakeOverride.fromMap({'plan_id': 'p1', 'run_date': '2026-09-29', 'skip': false, 'time': '06:30:00'});
      expect(at, WakeOverride.at('p1', DateTime(2026, 9, 29), 6, 30));
      expect(at.skip, isFalse);
      expect(at.hour, 6);
      expect(at.minute, 30);
    });

    test('toMap grava só plano, data local e horário (user_id vem do banco)', () {
      expect(WakeOverride.skip('p1', DateTime(2026, 9, 29, 15, 40)).toMap(),
          {'plan_id': 'p1', 'run_date': '2026-09-29', 'skip': true, 'time': null});
      expect(WakeOverride.at('p1', DateTime(2026, 10, 3), 6, 5).toMap(),
          {'plan_id': 'p1', 'run_date': '2026-10-03', 'skip': false, 'time': '06:05'});
    });

    test('a data guardada ignora a hora do relógio', () {
      expect(WakeOverride.skip('p1', DateTime(2026, 9, 29, 23, 59)).date, DateTime(2026, 9, 29));
      expect(dateKey(DateTime(2026, 1, 5, 8)), '2026-01-05');
    });
  });

  group('nextWake com exceções', () {
    final monday10 = DateTime(2026, 9, 28, 10);
    const plan = WakePlan(
      id: 'p1', label: 'Aula', days: [1, 2, 3, 4, 5], hour: 7, minute: 0, echoDeviceId: 'E',
    );

    test('sem exceções é a regra semanal', () {
      expect(nextWake(plan, const [], monday10), DateTime(2026, 9, 29, 7));
    });

    test('pular amanhã vai para o dia seguinte', () {
      final o = [WakeOverride.skip('p1', DateTime(2026, 9, 29))];
      expect(nextWake(plan, o, monday10), DateTime(2026, 9, 30, 7));
    });

    test('horário só amanhã substitui o do plano', () {
      final o = [WakeOverride.at('p1', DateTime(2026, 9, 29), 5, 45)];
      expect(nextWake(plan, o, monday10), DateTime(2026, 9, 29, 5, 45));
    });

    test('horário num dia fora dos dias do plano é um toque extra', () {
      final o = [WakeOverride.at('p1', DateTime(2026, 10, 3), 9, 0)]; // sábado
      expect(nextWake(plan, o, monday10), DateTime(2026, 9, 29, 7)); // o de terça vem antes
      final skipWeek = [for (var d = 29; d <= 30; d++) WakeOverride.skip('p1', DateTime(2026, 9, d)),
        WakeOverride.skip('p1', DateTime(2026, 10, 1)), WakeOverride.skip('p1', DateTime(2026, 10, 2)), ...o];
      expect(nextWake(plan, skipWeek, monday10), DateTime(2026, 10, 3, 9));
    });

    test('exceção distante (além de uma semana) também conta', () {
      const sundayOnly = WakePlan(id: 'p1', label: 'x', days: [1], hour: 7, minute: 0, echoDeviceId: 'E');
      final o = [
        WakeOverride.skip('p1', DateTime(2026, 10, 5)),
        WakeOverride.skip('p1', DateTime(2026, 10, 12)),
        WakeOverride.at('p1', DateTime(2026, 10, 15), 8, 0),
      ];
      expect(nextWake(sundayOnly, o, monday10), DateTime(2026, 10, 15, 8));
    });

    test('exceção de hoje com horário que já passou é ignorada; que ainda vem, vale', () {
      expect(nextWake(plan, [WakeOverride.at('p1', DateTime(2026, 9, 28), 9, 0)], monday10), DateTime(2026, 9, 29, 7));
      expect(nextWake(plan, [WakeOverride.at('p1', DateTime(2026, 9, 28), 11, 0)], monday10), DateTime(2026, 9, 28, 11));
    });

    test('exceção de outro plano não interfere; sem nenhum toque possível devolve null', () {
      expect(nextWake(plan, [WakeOverride.skip('outro', DateTime(2026, 9, 29))], monday10), DateTime(2026, 9, 29, 7));
      expect(nextWake(plan.copyWith(days: const []), const [], monday10), isNull);
    });

    test('rótulo "Toca em …" considera a exceção', () {
      final o = [WakeOverride.at('p1', DateTime(2026, 9, 29), 5, 45)];
      expect(wakeInLabelFor(plan, o, monday10), 'Toca em 19 h 45 min');
      expect(wakeInLabelFor(plan.copyWith(days: const []), const [], monday10), isNull);
    });
  });
}
