import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/agenda.dart';
import '../../domain/calendar_event.dart';
import '../../domain/event_tag.dart';
import '../../ui/org_theme.dart';
import '../../ui/org_widgets.dart';
import 'calendar_common.dart';
import 'calendar_layout.dart';
import 'tag_style.dart';

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
    this.tags = const {},
  });

  final DateTime selected;
  final List<CalendarEvent> events;
  final DateTime now;
  final Map<String, String> spaceNames;
  final ValueChanged<DateTime> onSelect;
  final ValueChanged<CalendarEvent> onOpen;

  /// Etiquetas por id; sem elas os eventos têm o visual por espaço.
  final Map<String, EventTag> tags;

  /// Ponto do dia no mês: a cor da etiqueta do primeiro evento etiquetado; senão o destaque do tema.
  Color _dotColor(OrgThemeSpec org, List<CalendarEvent> dayEvents) {
    for (final e in dayEvents) {
      final look = eventLook(org, e, tags);
      if (look.tagged) return look.accent;
    }
    return org.accentText;
  }

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
            for (final i in weekdayInitials)
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
                    dotColor: _dotColor(org, eventsOnDay(events, grid[r * 7 + c])),
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
            child: _EventCard(
              event: e,
              day: sel,
              look: eventLook(org, e, tags),
              spaceName: spaceNames[e.spaceId],
              onOpen: onOpen,
            ),
          ),
      ],
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.day,
    required this.look,
    required this.spaceName,
    required this.onOpen,
  });

  final CalendarEvent event;
  final DateTime day;
  final EventLook look;
  final String? spaceName;
  final ValueChanged<CalendarEvent> onOpen;

  @override
  Widget build(BuildContext context) {
    final org = context.org;
    final theme = Theme.of(context);
    final e = event;
    return OrgCard(
      key: ValueKey('agenda-event-${e.id}'),
      onTap: () => onOpen(e),
      color: look.tagged ? look.fill : null,
      child: Row(
        children: [
          Container(
            width: 4,
            height: 36,
            decoration: BoxDecoration(
              color: look.tagged ? null : eventColor(org, e.spaceId),
              borderRadius: BorderRadius.circular(2),
            ),
            clipBehavior: Clip.antiAlias,
            child: look.tagged ? ColoredBox(key: ValueKey('tag-bar-${e.id}-list'), color: look.accent) : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        e.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: look.taggedWeight),
                      ),
                    ),
                    if (e.seriesId != null) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.repeat, size: 14, color: org.inkMuted),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    eventTimeLabel(e, day),
                    ?spaceName,
                    if ((e.location ?? '').isNotEmpty) e.location!,
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(color: org.inkMuted),
                ),
              ],
            ),
          ),
        ],
      ),
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
    required this.dotColor,
    required this.onTap,
  });

  final DateTime day;
  final bool inMonth;
  final bool isToday;
  final bool isSelected;
  final bool hasEvents;
  final Color dotColor;
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
                color: hasEvents ? dotColor : Colors.transparent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
