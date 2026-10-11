import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/domain/calendar_event.dart';
import 'package:organizacional/features/agenda/calendar_layout.dart';

void main() {
  test('evento 22:00→02:00 fica 22:00–24:00 no dia 1 e 00:00–02:00 no dia 2', () {
    final e = CalendarEvent(
        id: 'f', title: 'Festa', startsAt: DateTime(2026, 10, 10, 22), endsAt: DateTime(2026, 10, 11, 2));
    final d1 = layoutDay([e], DateTime(2026, 10, 10)).single;
    expect([d1.top, d1.height], [22 * 60, 120]);
    final d2 = layoutDay([e], DateTime(2026, 10, 11)).single;
    expect([d2.top, d2.height], [0, 120]);
  });

  test('eventos sobrepostos dividem a largura em colunas', () {
    final a = CalendarEvent(
        id: 'a', title: 'A', startsAt: DateTime(2026, 10, 12, 8), endsAt: DateTime(2026, 10, 12, 10));
    final b = CalendarEvent(
        id: 'b', title: 'B', startsAt: DateTime(2026, 10, 12, 9), endsAt: DateTime(2026, 10, 12, 11));
    final c = CalendarEvent(
        id: 'c', title: 'C', startsAt: DateTime(2026, 10, 12, 13), endsAt: DateTime(2026, 10, 12, 14));
    final p = layoutDay([a, b, c], DateTime(2026, 10, 12));
    expect(p.map((x) => (x.column, x.columns)), [(0, 2), (1, 2), (0, 1)]);
  });

  test('altura mínima de 20 min para eventos curtos', () {
    final e = CalendarEvent(
        id: 's', title: 'S', startsAt: DateTime(2026, 10, 12, 8), endsAt: DateTime(2026, 10, 12, 8, 5));
    expect(layoutDay([e], DateTime(2026, 10, 12)).single.height, 20);
  });

  test('monthGrid tem 42 dias começando na segunda', () {
    final g = monthGrid(DateTime(2026, 10, 15));
    expect(g, hasLength(42));
    expect(g.first, DateTime(2026, 9, 28));
    expect(g.last, DateTime(2026, 11, 8));
  });

  test('arredonda a 15 minutos', () {
    expect(snapMinutes(7), 0);
    expect(snapMinutes(8), 15);
    expect(snapMinutes(22 * 60 + 37), 22 * 60 + 30);
  });

  test('evento de dia inteiro fica fora da grade de horas', () {
    final allDay = CalendarEvent(
        id: 'd', title: 'Feriado', startsAt: DateTime(2026, 10, 12), endsAt: DateTime(2026, 10, 13), allDay: true);
    final timed = CalendarEvent(
        id: 't', title: 'Aula', startsAt: DateTime(2026, 10, 12, 8), endsAt: DateTime(2026, 10, 12, 9));
    final p = layoutDay([allDay, timed], DateTime(2026, 10, 12));
    expect(p.map((x) => x.event.id), ['t']);
    expect((p.single.column, p.single.columns), (0, 1));
  });
}
