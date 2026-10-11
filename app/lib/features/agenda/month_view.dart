import 'package:flutter/material.dart';

import '../../domain/agenda.dart';
import '../../domain/calendar_event.dart';
import '../../ui/org_theme.dart';
import 'calendar_common.dart';
import 'calendar_layout.dart';

const _weekdays = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];

/// Grade 6×7 do mês com até 3 pílulas por dia e "+N".
class MonthView extends StatelessWidget {
  const MonthView({
    super.key,
    required this.month,
    required this.events,
    required this.now,
    required this.onOpenDay,
  });

  final DateTime month;
  final List<CalendarEvent> events;
  final DateTime now;
  final ValueChanged<DateTime> onOpenDay;

  @override
  Widget build(BuildContext context) {
    final org = context.org;
    final theme = Theme.of(context);
    final grid = monthGrid(month);
    final today = startOfDay(now);
    return Column(
      children: [
        Row(
          children: [
            for (final w in _weekdays)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Center(
                    child: Text(w, style: theme.textTheme.labelMedium?.copyWith(color: org.inkMuted)),
                  ),
                ),
              ),
          ],
        ),
        Expanded(
          child: Column(
            children: [
              for (var r = 0; r < 6; r++)
                Expanded(
                  child: Row(
                    children: [
                      for (var c = 0; c < 7; c++)
                        Expanded(
                          child: _DayCell(
                            day: grid[r * 7 + c],
                            inMonth: grid[r * 7 + c].month == month.month,
                            isToday: grid[r * 7 + c] == today,
                            events: eventsOnDay(events, grid[r * 7 + c]),
                            onTap: () => onOpenDay(grid[r * 7 + c]),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.inMonth,
    required this.isToday,
    required this.events,
    required this.onTap,
  });

  final DateTime day;
  final bool inMonth;
  final bool isToday;
  final List<CalendarEvent> events;
  final VoidCallback onTap;

  static const double _head = 22;
  static const double _pill = 18;

  @override
  Widget build(BuildContext context) {
    final org = context.org;
    final theme = Theme.of(context);
    return InkWell(
      key: ValueKey('month-day-${dayKey(day)}'),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: org.line), left: BorderSide(color: org.line)),
        ),
        padding: const EdgeInsets.all(2),
        child: LayoutBuilder(builder: (context, c) {
          final avail = c.maxHeight - _head;
          var shown = events.length < 3 ? events.length : 3;
          shown = shown.clamp(0, (avail / _pill).floor());
          if (events.length > shown && avail - shown * _pill < 14 && shown > 0) shown--;
          final rest = events.length - shown;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: _head,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      '${day.day}',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: isToday ? org.accentText : (inMonth ? org.ink : org.inkMuted.withValues(alpha: 0.5)),
                        fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
              for (final e in events.take(shown))
                SizedBox(
                  height: _pill,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 1),
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: eventColor(org, e.spaceId),
                      borderRadius: BorderRadius.circular(org.radiusSm),
                    ),
                    child: Text(
                      e.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(color: org.onAccent),
                    ),
                  ),
                ),
              if (rest > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text('+$rest', style: theme.textTheme.labelSmall?.copyWith(color: org.inkMuted)),
                ),
            ],
          );
        }),
      ),
    );
  }
}
