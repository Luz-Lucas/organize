import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/domain/recurrence.dart';
import 'package:organizacional/features/agenda/repeat_section.dart';

void main() {
  final day = DateTime(2026, 9, 29); // terça
  final at = DateTime(2026, 9, 29, 23, 59);
  const empty = 'nada';

  test('sem repetição não há regra nem erro', () {
    final c = RepeatController();
    addTearDown(c.dispose);
    expect(c.recurrence(day), isNull);
    expect(c.problem(day, at, emptyMessage: empty), isNull);
  });

  test('semanal sem dias marcados usa o dia do início; padrão "até" é início + 3 meses', () {
    final c = RepeatController()..freq = RepeatFreq.weekly;
    addTearDown(c.dispose);
    final r = c.recurrence(day)!;
    expect(r.days, {2});
    expect(r.until, DateTime(2026, 12, 29));
    expect(r.count, isNull);
  });

  test('sempre sobra um dia marcado', () {
    final c = RepeatController()..freq = RepeatFreq.weekly;
    addTearDown(c.dispose);
    c.toggleDay(day, 2, false);
    expect(c.effectiveDays(day), {2});
    c.toggleDay(day, 4, true);
    expect(c.effectiveDays(day), {2, 4});
  });

  test('"até" antes do início é erro; quantidade inválida é erro', () {
    final c = RepeatController()..freq = RepeatFreq.daily;
    addTearDown(c.dispose);
    c.until = DateTime(2026, 9, 1);
    expect(c.recurrence(day), isNull);
    expect(c.problem(day, at, emptyMessage: empty), 'A data final não pode ser antes do início.');
    c.untilMode = false;
    c.count.text = '0';
    expect(c.problem(day, at, emptyMessage: empty), 'Informe de 1 a $maxSeriesOccurrences repetições.');
    c.count.text = '5';
    expect(c.problem(day, at, emptyMessage: empty), isNull);
    expect(c.recurrence(day)!.count, 5);
  });

  test('regra válida que não gera nenhuma ocorrência devolve a mensagem informada', () {
    final c = RepeatController()..freq = RepeatFreq.weekly;
    addTearDown(c.dispose);
    c.toggleDay(day, 1, true);
    c.toggleDay(day, 2, false); // só segunda
    c.until = DateTime(2026, 9, 30);
    expect(c.problem(day, at, emptyMessage: empty), empty);
  });
}
