import 'package:flutter_test/flutter_test.dart';
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
}
