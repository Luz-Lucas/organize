import '../../domain/agenda.dart';
import '../../domain/calendar_event.dart';

/// Evento posicionado dentro da coluna de um dia (minutos desde 00:00).
class PlacedEvent {
  const PlacedEvent({
    required this.event,
    required this.top,
    required this.height,
    required this.column,
    required this.columns,
  });

  final CalendarEvent event;
  final int top;
  final int height;
  final int column;
  final int columns;
}

const minEventMinutes = 20;

/// Posiciona os eventos com horário que tocam [day] (os de dia inteiro ficam
/// numa faixa à parte, não na grade de horas). Eventos que atravessam a meia-noite
/// são recortados ao dia; sobrepostos dividem a largura em colunas.
List<PlacedEvent> layoutDay(Iterable<CalendarEvent> events, DateTime day) {
  final dayStart = DateTime(day.year, day.month, day.day);
  final dayEnd = DateTime(day.year, day.month, day.day + 1);
  final items = <({CalendarEvent event, int top, int height})>[];
  for (final e in eventsOnDay(events, day).where((e) => !e.allDay)) {
    final start = e.startsAt.isBefore(dayStart) ? dayStart : e.startsAt;
    final end = e.endsAt.isAfter(dayEnd) ? dayEnd : e.endsAt;
    final top = start.isBefore(dayStart) ? 0 : start.hour * 60 + start.minute;
    final endMin = !end.isBefore(dayEnd) ? 24 * 60 : end.hour * 60 + end.minute;
    var height = endMin - top;
    if (height < minEventMinutes) height = minEventMinutes;
    if (top + height > 24 * 60) height = 24 * 60 - top;
    items.add((event: e, top: top, height: height));
  }
  items.sort((a, b) => a.top != b.top ? a.top.compareTo(b.top) : b.height.compareTo(a.height));

  final placed = <PlacedEvent>[];
  var cluster = <({CalendarEvent event, int top, int height, int column})>[];
  var clusterEnd = 0;

  void flush() {
    if (cluster.isEmpty) return;
    final cols = cluster.map((c) => c.column).reduce((a, b) => a > b ? a : b) + 1;
    for (final c in cluster) {
      placed.add(PlacedEvent(
          event: c.event, top: c.top, height: c.height, column: c.column, columns: cols));
    }
    cluster = [];
  }

  for (final it in items) {
    if (cluster.isNotEmpty && it.top >= clusterEnd) flush();
    // Primeira coluna livre no cluster atual.
    var column = 0;
    while (cluster.any((c) => c.column == column && c.top + c.height > it.top)) {
      column++;
    }
    cluster.add((event: it.event, top: it.top, height: it.height, column: column));
    final end = it.top + it.height;
    if (end > clusterEnd || cluster.length == 1) clusterEnd = end;
  }
  flush();
  return placed;
}

/// Grade 6×7 do mês de [month], começando na segunda-feira.
List<DateTime> monthGrid(DateTime month) {
  final first = startOfWeek(DateTime(month.year, month.month, 1));
  return [for (var i = 0; i < 42; i++) DateTime(first.year, first.month, first.day + i)];
}

/// Arredonda minutos ao múltiplo de 15 mais próximo.
int snapMinutes(num minutes) => ((minutes / 15).round()) * 15;
