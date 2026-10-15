import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/agenda.dart';
import '../../domain/calendar_event.dart';
import '../../domain/event_tag.dart';
import '../../ui/org_theme.dart';
import 'calendar_common.dart';
import 'calendar_layout.dart';
import 'tag_style.dart';

const double hourHeight = 48;
const double _gutter = 52;

/// Semana em grade de horas (48px/hora), estilo Google Agenda.
class WeekView extends StatefulWidget {
  const WeekView({
    super.key,
    required this.weekStart,
    required this.events,
    required this.now,
    required this.onCreate,
    required this.onOpen,
    this.tags = const {},
  });

  final DateTime weekStart;
  final List<CalendarEvent> events;
  final DateTime now;
  final void Function(DateTime start, DateTime end) onCreate;
  final ValueChanged<CalendarEvent> onOpen;

  /// Etiquetas por id; sem elas os eventos têm o visual por espaço.
  final Map<String, EventTag> tags;

  @override
  State<WeekView> createState() => _WeekViewState();
}

class _WeekViewState extends State<WeekView> {
  final _scroll = ScrollController(initialScrollOffset: 7 * hourHeight);

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final org = context.org;
    final theme = Theme.of(context);
    final today = startOfDay(widget.now);
    final days = [for (var i = 0; i < 7; i++) addDays(widget.weekStart, i)];
    final wd = DateFormat('EEE', 'pt_BR');
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: _gutter),
          child: Row(
            children: [
              for (final d in days)
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      border: Border(left: BorderSide(color: org.line), bottom: BorderSide(color: org.line)),
                    ),
                    child: Column(
                      children: [
                        Text(
                          wd.format(d),
                          style: theme.textTheme.labelMedium
                              ?.copyWith(color: d == today ? org.accentText : org.inkMuted),
                        ),
                        Text(
                          '${d.day}',
                          key: ValueKey('week-head-${dayKey(d)}'),
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: d == today ? org.accentText : org.ink,
                            fontWeight: d == today ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                        for (final e in eventsOnDay(widget.events, d).where((e) => e.allDay))
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                            child: GestureDetector(
                              key: ValueKey('allday-${e.id}'),
                              onTap: () => widget.onOpen(e),
                              child: SizedBox(
                                width: double.infinity,
                                child: Builder(builder: (context) {
                                  final look = eventLook(org, e, widget.tags);
                                  return EventSurface(
                                    look: look,
                                    radius: org.radiusSm,
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                    barKey: ValueKey('tag-bar-${e.id}-allday'),
                                    child: Text(
                                      e.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(color: look.text, fontWeight: look.taggedWeight),
                                    ),
                                  );
                                }),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            controller: _scroll,
            child: SizedBox(
              height: 24 * hourHeight,
              child: Row(
                children: [
                  SizedBox(
                    width: _gutter,
                    child: Stack(
                      children: [
                        for (var h = 1; h < 24; h++)
                          Positioned(
                            top: h * hourHeight - 7,
                            right: 8,
                            child: Text(
                              '${h.toString().padLeft(2, '0')}:00',
                              style: theme.textTheme.labelSmall?.copyWith(color: org.inkMuted),
                            ),
                          ),
                      ],
                    ),
                  ),
                  for (final d in days)
                    Expanded(
                      child: _DayColumn(
                        day: d,
                        isToday: d == today,
                        now: widget.now,
                        events: widget.events,
                        tags: widget.tags,
                        onCreate: widget.onCreate,
                        onOpen: widget.onOpen,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DayColumn extends StatefulWidget {
  const _DayColumn({
    required this.day,
    required this.isToday,
    required this.now,
    required this.events,
    required this.tags,
    required this.onCreate,
    required this.onOpen,
  });

  final DateTime day;
  final bool isToday;
  final DateTime now;
  final List<CalendarEvent> events;
  final Map<String, EventTag> tags;
  final void Function(DateTime start, DateTime end) onCreate;
  final ValueChanged<CalendarEvent> onOpen;

  @override
  State<_DayColumn> createState() => _DayColumnState();
}

class _DayColumnState extends State<_DayColumn> {
  double? _dragFrom;
  double? _dragTo;

  DateTime _at(int minutes) =>
      DateTime(widget.day.year, widget.day.month, widget.day.day, 0, minutes);

  double _minutesAt(double dy) => (dy / hourHeight * 60).clamp(0, 24 * 60).toDouble();

  void _finishDrag() {
    final from = _dragFrom, to = _dragTo;
    setState(() {
      _dragFrom = null;
      _dragTo = null;
    });
    if (from == null || to == null) return;
    var a = snapMinutes(from < to ? from : to);
    var b = snapMinutes(from < to ? to : from);
    if (b - a < 15) b = a + 60;
    if (b > 24 * 60) {
      b = 24 * 60;
      if (b - a < 15) a = b - 60;
    }
    widget.onCreate(_at(a), _at(b));
  }

  @override
  Widget build(BuildContext context) {
    final org = context.org;
    final placed = layoutDay(widget.events, widget.day);
    final dragRect = (_dragFrom != null && _dragTo != null)
        ? (() {
            final a = _dragFrom! < _dragTo! ? _dragFrom! : _dragTo!;
            final b = _dragFrom! < _dragTo! ? _dragTo! : _dragFrom!;
            return (snapMinutes(a), snapMinutes(b) <= snapMinutes(a) ? snapMinutes(a) + 15 : snapMinutes(b));
          })()
        : null;
    return GestureDetector(
      dragStartBehavior: DragStartBehavior.down,
      onVerticalDragStart: (d) => setState(() {
        _dragFrom = _minutesAt(d.localPosition.dy);
        _dragTo = _dragFrom;
      }),
      onVerticalDragUpdate: (d) => setState(() => _dragTo = _minutesAt(d.localPosition.dy)),
      onVerticalDragEnd: (_) => _finishDrag(),
      onVerticalDragCancel: () => setState(() {
        _dragFrom = null;
        _dragTo = null;
      }),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: widget.isToday ? org.accentSoft.withValues(alpha: 0.35) : null,
          border: Border(left: BorderSide(color: org.line)),
        ),
        child: LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth;
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Column(
                children: [
                  for (var h = 0; h < 24; h++)
                    GestureDetector(
                      key: ValueKey('slot-${dayKey(widget.day)}-$h'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => widget.onCreate(_at(h * 60), _at((h + 1) * 60)),
                      child: Container(
                        height: hourHeight,
                        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: org.line))),
                      ),
                    ),
                ],
              ),
              if (dragRect != null)
                Positioned(
                  top: dragRect.$1 * hourHeight / 60,
                  height: (dragRect.$2 - dragRect.$1) * hourHeight / 60,
                  left: 2,
                  right: 2,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: org.accentSoft,
                        border: Border.all(color: org.accentText),
                        borderRadius: BorderRadius.circular(org.radiusSm),
                      ),
                    ),
                  ),
                ),
              for (final p in placed)
                Positioned(
                  top: p.top * hourHeight / 60,
                  height: p.height * hourHeight / 60 - 1,
                  left: w * p.column / p.columns + 1,
                  width: w / p.columns - 3,
                  child: _EventBlock(
                    key: ValueKey('event-block-${p.event.id}-${dayKey(widget.day)}'),
                    placed: p,
                    day: widget.day,
                    tags: widget.tags,
                    onTap: () => widget.onOpen(p.event),
                  ),
                ),
              if (widget.isToday)
                Positioned(
                  top: (widget.now.hour * 60 + widget.now.minute) * hourHeight / 60,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(child: Container(height: 2, color: org.accentText)),
                ),
            ],
          );
        }),
      ),
    );
  }
}

class _EventBlock extends StatelessWidget {
  const _EventBlock({super.key, required this.placed, required this.day, required this.tags, required this.onTap});

  final PlacedEvent placed;
  final DateTime day;
  final Map<String, EventTag> tags;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final org = context.org;
    final e = placed.event;
    final look = eventLook(org, e, tags);
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(color: look.text);
    return GestureDetector(
      onTap: onTap,
      child: EventSurface(
        look: look,
        radius: org.radiusSm,
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        barKey: ValueKey('tag-bar-${e.id}-${dayKey(day)}'),
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: style?.copyWith(fontWeight: look.titleWeight)),
                  ),
                  if (e.seriesId != null) Icon(Icons.repeat, size: 14, color: look.text),
                ],
              ),
              if (placed.height >= 40)
                Text(eventTimeLabel(e, day), maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
            ],
          ),
        ),
      ),
    );
  }
}
