import 'package:flutter/material.dart';

import '../../domain/agenda.dart';
import '../../domain/calendar_event.dart';
import '../../domain/event_tag.dart';
import '../../ui/org_theme.dart';
import 'calendar_common.dart';
import 'calendar_layout.dart';
import 'tag_style.dart';

const _weekdays = ['dom', 'seg', 'ter', 'qua', 'qui', 'sex', 'sáb'];

/// Grade 6×7 do mês com até 3 pílulas por dia e "+N".
class MonthView extends StatelessWidget {
  const MonthView({
    super.key,
    required this.month,
    required this.events,
    required this.now,
    required this.onOpenDay,
    this.tags = const {},
  });

  final DateTime month;
  final List<CalendarEvent> events;
  final DateTime now;
  final ValueChanged<DateTime> onOpenDay;

  /// Etiquetas por id; sem elas os eventos têm o visual por espaço.
  final Map<String, EventTag> tags;

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
                            tags: tags,
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
    required this.tags,
    required this.onTap,
  });

  final DateTime day;
  final bool inMonth;
  final bool isToday;
  final List<CalendarEvent> events;
  final Map<String, EventTag> tags;
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
                  child: Builder(builder: (context) {
                    final look = eventLook(org, e, tags);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 1),
                      child: SizedBox.expand(
                        child: EventSurface(
                          look: look,
                          radius: org.radiusSm,
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          barKey: ValueKey('tag-bar-${e.id}-month'),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              e.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: look.text, fontWeight: look.taggedWeight),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
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
