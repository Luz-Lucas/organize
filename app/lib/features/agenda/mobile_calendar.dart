import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/agenda.dart';
import '../../domain/calendar_event.dart';
import '../../ui/org_theme.dart';
import '../../ui/org_widgets.dart';
import 'calendar_common.dart';
import 'calendar_layout.dart';

const _initials = ['D', 'S', 'T', 'Q', 'Q', 'S', 'S'];

/// Celular: mês compacto (pontos nos dias com evento) + lista do dia escolhido.
class MobileCalendar extends StatelessWidget {
  const MobileCalendar({
    super.key,
    required this.selected,
    required this.events,
    required this.now,
    required this.spaceNames,
    required this.onSelect,
    required this.onOpen,
  });

  final DateTime selected;
  final List<CalendarEvent> events;
  final DateTime now;
  final Map<String, String> spaceNames;
  final ValueChanged<DateTime> onSelect;
  final ValueChanged<CalendarEvent> onOpen;

  @override
  Widget build(BuildContext context) {
    final org = context.org;
    final theme = Theme.of(context);
    final grid = monthGrid(selected);
    final today = startOfDay(now);
    final sel = startOfDay(selected);
    final dayEvents = eventsOnDay(events, sel);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
      children: [
        Row(
          children: [
            for (final i in _initials)
              Expanded(
                child: Center(
                  child: Text(i, style: theme.textTheme.labelSmall?.copyWith(color: org.inkMuted)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (var r = 0; r < 6; r++)
          Row(
            children: [
              for (var c = 0; c < 7; c++)
                Expanded(
                  child: _MiniDay(
                    day: grid[r * 7 + c],
                    inMonth: grid[r * 7 + c].month == selected.month,
                    isToday: grid[r * 7 + c] == today,
                    isSelected: grid[r * 7 + c] == sel,
                    hasEvents: eventsOnDay(events, grid[r * 7 + c]).isNotEmpty,
                    onTap: () => onSelect(grid[r * 7 + c]),
                  ),
                ),
            ],
          ),
        SectionHeader(DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(sel)),
        if (dayEvents.isEmpty) const EmptyHint('Nenhum evento neste dia.'),
        for (final e in dayEvents)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OrgCard(
              key: ValueKey('agenda-event-${e.id}'),
              onTap: () => onOpen(e),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 36,
                    decoration: BoxDecoration(
                      color: eventColor(org, e.spaceId),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            eventTimeLabel(e, sel),
                            if (spaceNames[e.spaceId] != null) spaceNames[e.spaceId]!,
                            if ((e.location ?? '').isNotEmpty) e.location!,
                          ].join(' · '),
                          style: theme.textTheme.bodySmall?.copyWith(color: org.inkMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _MiniDay extends StatelessWidget {
  const _MiniDay({
    required this.day,
    required this.inMonth,
    required this.isToday,
    required this.isSelected,
    required this.hasEvents,
    required this.onTap,
  });

  final DateTime day;
  final bool inMonth;
  final bool isToday;
  final bool isSelected;
  final bool hasEvents;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final org = context.org;
    final theme = Theme.of(context);
    return InkWell(
      key: ValueKey('mini-day-${dayKey(day)}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(org.radiusSm),
      child: Container(
        height: 44,
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: isSelected ? org.accentSoft : null,
          borderRadius: BorderRadius.circular(org.radiusSm),
          border: isSelected ? Border.all(color: org.accentText) : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${day.day}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isToday ? org.accentText : (inMonth ? org.ink : org.inkMuted.withValues(alpha: 0.5)),
                fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
            const SizedBox(height: 3),
            Container(
              key: hasEvents ? ValueKey('dot-${dayKey(day)}') : null,
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hasEvents ? org.accentText : Colors.transparent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
