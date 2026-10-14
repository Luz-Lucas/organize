import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:organizacional/ui/date_labels.dart';

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  final now = DateTime(2026, 10, 14, 15); // quarta-feira

  test('hoje, amanhã e ontem (concluída)', () {
    expect(dueLabel(DateTime(2026, 10, 14, 23, 59), now), 'hoje');
    expect(dueLabel(DateTime(2026, 10, 14, 8), now), 'hoje'); // hora já passou, dia não
    expect(dueLabel(DateTime(2026, 10, 15, 23, 59), now), 'amanhã');
    expect(dueLabel(DateTime(2026, 10, 13, 23, 59), now, done: true), 'ontem');
  });

  test('próximos 6 dias usam o dia da semana sem ponto', () {
    expect(dueLabel(DateTime(2026, 10, 16, 23, 59), now), 'sex');
    expect(dueLabel(DateTime(2026, 10, 20, 23, 59), now), 'ter'); // +6
    expect(dueLabel(DateTime(2026, 10, 16), now), isNot(contains('.')));
  });

  test('depois disso mostra "d MMM" e só põe o ano quando difere', () {
    expect(dueLabel(DateTime(2026, 10, 21, 23, 59), now), '21 out'); // +7
    expect(dueLabel(DateTime(2026, 12, 3), now), '3 dez');
    expect(dueLabel(DateTime(2027, 1, 5), now), '5 jan 2027');
    expect(dueLabel(DateTime(2026, 9, 3), now, done: true), '3 set');
  });

  test('antes de hoje vira "atrasada · N d"', () {
    expect(dueLabel(DateTime(2026, 10, 13, 23, 59), now), 'atrasada · 1 d');
    expect(dueLabel(DateTime(2026, 10, 9), now), 'atrasada · 5 d');
    expect(isOverdue(DateTime(2026, 10, 13, 23, 59), now), isTrue);
    expect(isOverdue(DateTime(2026, 10, 14, 1), now), isFalse);
  });
}
