import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/agenda.dart';
import '../../domain/calendar_event.dart';
import '../../domain/event_tag.dart';
import '../../ui/org_theme.dart';
import 'agenda_view_prefs.dart';
import 'calendar_common.dart';
import 'calendar_layout.dart';
import 'tag_style.dart';

const double _gutter = 32;
const int _centerPage = 5000;

/// Abaixo desta largura útil (já sem a barra e o respiro) o bloco não comporta texto legível:
/// fica só a barra de cor e o horário.
const double _narrowContent = 24;

/// Distância vertical mínima entre os dedos para a pinça: evita que dedos lado a lado (pinça
/// horizontal) virem uma escala absurda.
const double _minPinchSpan = 40;

/// Semana do celular: 7 colunas (domingo a sábado) numa grade de horas, com faixa de dia inteiro no topo.
/// Deslizar na horizontal troca de semana; segurar um horário vazio cria um evento; a pinça vertical muda
/// a altura da hora. A sobreposição vem de [layoutDay], a mesma da semana do computador.
class MobileWeekView extends StatefulWidget {
  const MobileWeekView({
    super.key,
    required this.weekStart,
    required this.events,
    required this.now,
    required this.hourHeight,
    required this.onHourHeightChanged,
    required this.onHourHeightCommit,
    required this.onWeekChanged,
    required this.onCreate,
    required this.onOpen,
    this.tags = const {},
  });

  /// Domingo da semana mostrada. Quem muda é o pai; esta tela acompanha (animando ou pulando).
  final DateTime weekStart;
  final List<CalendarEvent> events;
  final DateTime now;
  final double hourHeight;

  /// Acompanha a pinça (sem gravar).
  final ValueChanged<double> onHourHeightChanged;

  /// Os dedos saíram: grava a altura atual.
  final VoidCallback onHourHeightCommit;

  /// O usuário deslizou para outra semana (recebe o domingo dela).
  final ValueChanged<DateTime> onWeekChanged;
  final void Function(DateTime start, DateTime end) onCreate;
  final ValueChanged<CalendarEvent> onOpen;

  /// Etiquetas por id; sem elas os eventos têm o visual por espaço.
  final Map<String, EventTag> tags;

  @override
  State<MobileWeekView> createState() => _MobileWeekViewState();
}

/// A rolagem vertical de uma página e o retângulo dela na tela (a pinça usa os dois).
class _PageHandle {
  _PageHandle(this.controller, this.viewportKey);

  final ScrollController controller;
  final GlobalKey viewportKey;

  RenderBox? get box {
    final o = viewportKey.currentContext?.findRenderObject();
    return o is RenderBox && o.attached && o.hasSize ? o : null;
  }
}

class _MobileWeekViewState extends State<MobileWeekView> {
  late final DateTime _base = widget.weekStart;
  late final PageController _pages = PageController(initialPage: _centerPage);
  int _page = _centerPage;

  /// Rolagem vertical compartilhada: toda página nova nasce nela, então trocar de semana não "pula".
  late double _offset = _initialOffset();
  final _handles = <_PageHandle>[];

  final _pointers = <int, Offset>{};
  bool _pinching = false;
  double _pinchStartHeight = 0;
  double _pinchStartSpan = 0;
  double _pinchMinutes = 0;
  double _pinchViewportTop = 0;
  double? _pendingOffset;

  double _initialOffset() {
    final focus = weekFocusMinute(widget.events, widget.weekStart, widget.now);
    return math.max(0, (focus - 60) / 60 * widget.hourHeight);
  }

  DateTime _weekOf(int page) => addDays(_base, (page - _centerPage) * 7);

  int _pageOf(DateTime week) {
    final days = DateTime.utc(week.year, week.month, week.day)
        .difference(DateTime.utc(_base.year, _base.month, _base.day))
        .inDays;
    return _centerPage + (days / 7).round();
  }

  @override
  void didUpdateWidget(MobileWeekView old) {
    super.didUpdateWidget(old);
    if (old.weekStart != widget.weekStart) {
      final target = _pageOf(widget.weekStart);
      if (target != _page && _pages.hasClients) {
        if ((target - _page).abs() == 1) {
          _pages.animateToPage(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        } else {
          _pages.jumpToPage(target);
        }
        _page = target;
      }
    }
    if (old.hourHeight != widget.hourHeight) {
      // Mantém na tela o mesmo horário (o do ponto entre os dedos, ou o do topo).
      final target = _pendingOffset ?? _offset / old.hourHeight * widget.hourHeight;
      _pendingOffset = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _jumpAll(target);
      });
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _jumpAll(double target) {
    var applied = math.max(0.0, target);
    for (final h in _handles) {
      if (!h.controller.hasClients) continue;
      final max = h.controller.position.maxScrollExtent;
      applied = target.clamp(0.0, max).toDouble();
      h.controller.jumpTo(applied);
    }
    _offset = applied;
  }

  // --- pinça ---------------------------------------------------------------------------------

  double _span() {
    final ys = _pointers.values.map((p) => p.dy).toList();
    return math.max((ys[0] - ys[1]).abs(), _minPinchSpan);
  }

  double _focalY() {
    final ys = _pointers.values.map((p) => p.dy).toList();
    return (ys[0] + ys[1]) / 2;
  }

  double _viewportTop() {
    RenderBox? best;
    var bestDx = double.infinity;
    for (final h in _handles) {
      final b = h.box;
      if (b == null) continue;
      final dx = b.localToGlobal(Offset.zero).dx.abs();
      if (dx < bestDx) {
        bestDx = dx;
        best = b;
      }
    }
    return best?.localToGlobal(Offset.zero).dy ?? 0;
  }

  void _pointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.position;
    if (_pointers.length != 2) return;
    _pinchStartHeight = widget.hourHeight;
    _pinchStartSpan = _span();
    _pinchViewportTop = _viewportTop();
    _pinchMinutes = (_offset + _focalY() - _pinchViewportTop) / _pinchStartHeight * 60;
    setState(() => _pinching = true);
  }

  void _pointerMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.position;
    if (!_pinching || _pointers.length < 2) return;
    final height = clampHourHeight(_pinchStartHeight * _span() / _pinchStartSpan);
    if (height == widget.hourHeight) return;
    _pendingOffset = _pinchMinutes / 60 * height - (_focalY() - _pinchViewportTop);
    widget.onHourHeightChanged(height);
  }

  void _pointerUp(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pinching && _pointers.length < 2) {
      setState(() => _pinching = false);
      widget.onHourHeightCommit();
    }
  }

  // --- criação -------------------------------------------------------------------------------

  /// Segurar num horário vazio: começa na meia hora mais próxima e dura 1 h.
  void _createAt(DateTime day, double minutes) {
    if (_pointers.length >= 2) return;
    final start = ((minutes / 30).round() * 30).clamp(0, 23 * 60 + 30);
    widget.onCreate(
      DateTime(day.year, day.month, day.day, 0, start),
      DateTime(day.year, day.month, day.day, 0, start + 60),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      key: const Key('mobile-week'),
      behavior: HitTestBehavior.translucent,
      onPointerDown: _pointerDown,
      onPointerMove: _pointerMove,
      onPointerUp: _pointerUp,
      onPointerCancel: _pointerUp,
      child: PageView.builder(
        controller: _pages,
        physics: _pinching ? const NeverScrollableScrollPhysics() : null,
        onPageChanged: (i) {
          _page = i;
          widget.onWeekChanged(_weekOf(i));
        },
        itemBuilder: (context, i) {
          final week = _weekOf(i);
          return _WeekPage(
            key: ValueKey('mweek-page-${dayKey(week)}'),
            weekStart: week,
            events: widget.events,
            now: widget.now,
            tags: widget.tags,
            hourHeight: widget.hourHeight,
            initialOffset: _offset,
            locked: _pinching,
            onScroll: (o) => _offset = o,
            onRegister: _handles.add,
            onUnregister: _handles.remove,
            onCreate: _createAt,
            onOpen: widget.onOpen,
          );
        },
      ),
    );
  }
}

class _WeekPage extends StatefulWidget {
  const _WeekPage({
    super.key,
    required this.weekStart,
    required this.events,
    required this.now,
    required this.tags,
    required this.hourHeight,
    required this.initialOffset,
    required this.locked,
    required this.onScroll,
    required this.onRegister,
    required this.onUnregister,
    required this.onCreate,
    required this.onOpen,
  });

  final DateTime weekStart;
  final List<CalendarEvent> events;
  final DateTime now;
  final Map<String, EventTag> tags;
  final double hourHeight;
  final double initialOffset;
  final bool locked;
  final ValueChanged<double> onScroll;
  final ValueChanged<_PageHandle> onRegister;
  final ValueChanged<_PageHandle> onUnregister;
  final void Function(DateTime day, double minutes) onCreate;
  final ValueChanged<CalendarEvent> onOpen;

  @override
  State<_WeekPage> createState() => _WeekPageState();
}

class _WeekPageState extends State<_WeekPage> {
  late final ScrollController _scroll = ScrollController(initialScrollOffset: widget.initialOffset);
  final _viewportKey = GlobalKey();
  late final _PageHandle _handle = _PageHandle(_scroll, _viewportKey);

  @override
  void initState() {
    super.initState();
    widget.onRegister(_handle);
    _scroll.addListener(() {
      if (_scroll.hasClients) widget.onScroll(_scroll.offset);
    });
    // Se a rolagem herdada passa do fim (outra altura de hora ou tela menor), encosta no fim.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      if (_scroll.offset > max) _scroll.jumpTo(max);
    });
  }

  @override
  void dispose() {
    widget.onUnregister(_handle);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final org = context.org;
    final theme = Theme.of(context);
    final today = startOfDay(widget.now);
    final days = [for (var i = 0; i < 7; i++) addDays(widget.weekStart, i)];
    final h = widget.hourHeight;
    final allDay = [for (final d in days) eventsOnDay(widget.events, d).where((e) => e.allDay).toList()];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: _gutter),
          child: Row(
            children: [
              for (final d in days) Expanded(child: _DayHead(day: d, isToday: d == today)),
            ],
          ),
        ),
        if (allDay.any((l) => l.isNotEmpty))
          Padding(
            padding: const EdgeInsets.only(left: _gutter),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 72),
              child: SingleChildScrollView(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < 7; i++)
                      Expanded(
                        child: Column(
                          children: [
                            for (final e in allDay[i])
                              _AllDayChip(event: e, day: days[i], tags: widget.tags, onTap: () => widget.onOpen(e)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        Divider(height: 1, color: org.line),
        Expanded(
          child: KeyedSubtree(
            key: _viewportKey,
            child: SingleChildScrollView(
              key: ValueKey('mweek-grid-${dayKey(widget.weekStart)}'),
              controller: _scroll,
              physics: widget.locked ? const NeverScrollableScrollPhysics() : null,
              padding: const EdgeInsets.only(bottom: 88),
              child: SizedBox(
                height: 24 * h,
                child: Row(
                  children: [
                    SizedBox(
                      width: _gutter,
                      child: Stack(
                        children: [
                          for (var hr = 1; hr < 24; hr++)
                            Positioned(
                              top: hr * h - 8,
                              right: 4,
                              child: Text(
                                '${hr}h',
                                maxLines: 1,
                                style: theme.textTheme.labelSmall?.copyWith(color: org.inkMuted, fontSize: 10),
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
                          hourHeight: h,
                          onCreate: widget.onCreate,
                          onOpen: widget.onOpen,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DayHead extends StatelessWidget {
  const _DayHead({required this.day, required this.isToday});

  final DateTime day;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final org = context.org;
    final theme = Theme.of(context);
    return Semantics(
      label: '${weekdayName(day)} ${day.day}${isToday ? ', hoje' : ''}',
      excludeSemantics: true,
      child: Padding(
        key: ValueKey('mweek-head-${dayKey(day)}'),
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            Text(
              weekdayInitials[day.weekday % DateTime.daysPerWeek],
              style: theme.textTheme.labelSmall?.copyWith(color: isToday ? org.accentText : org.inkMuted),
            ),
            const SizedBox(height: 2),
            Container(
              key: isToday ? const ValueKey('mweek-today') : null,
              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
              padding: const EdgeInsets.all(2),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: isToday ? org.accentDeep : null, shape: BoxShape.circle),
              child: Text(
                '${day.day}',
                maxLines: 1,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: isToday ? org.onAccent : org.ink,
                  fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AllDayChip extends StatelessWidget {
  const _AllDayChip({required this.event, required this.day, required this.tags, required this.onTap});

  final CalendarEvent event;
  final DateTime day;
  final Map<String, EventTag> tags;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final org = context.org;
    final look = eventLook(org, event, tags);
    final style = Theme.of(context)
        .textTheme
        .labelSmall
        ?.copyWith(color: look.text, fontSize: 10, height: 1.15, fontWeight: look.taggedWeight);
    return Padding(
      padding: const EdgeInsets.fromLTRB(1, 0, 1, 2),
      child: Semantics(
        key: ValueKey('mweek-allday-${event.id}'),
        label: eventSemanticLabel(event, day),
        button: true,
        excludeSemantics: true,
        onTap: onTap,
        child: GestureDetector(
          onTap: onTap,
          child: SizedBox(
            width: double.infinity,
            child: EventSurface(
              look: look,
              radius: org.radiusSm,
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
              barKey: ValueKey('tag-bar-${event.id}-allday'),
              child: Text(event.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
            ),
          ),
        ),
      ),
    );
  }
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.day,
    required this.isToday,
    required this.now,
    required this.events,
    required this.tags,
    required this.hourHeight,
    required this.onCreate,
    required this.onOpen,
  });

  final DateTime day;
  final bool isToday;
  final DateTime now;
  final List<CalendarEvent> events;
  final Map<String, EventTag> tags;
  final double hourHeight;
  final void Function(DateTime day, double minutes) onCreate;
  final ValueChanged<CalendarEvent> onOpen;

  @override
  Widget build(BuildContext context) {
    final org = context.org;
    final placed = layoutDay(events, day);
    return GestureDetector(
      key: ValueKey('mweek-col-${dayKey(day)}'),
      behavior: HitTestBehavior.opaque,
      onLongPressStart: (d) => onCreate(day, d.localPosition.dy / hourHeight * 60),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isToday ? org.accentSoft.withValues(alpha: 0.35) : null,
          border: Border(left: BorderSide(color: org.line)),
        ),
        child: LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth;
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Column(
                children: [
                  for (var hr = 0; hr < 24; hr++)
                    Container(
                      height: hourHeight,
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: org.line))),
                    ),
                ],
              ),
              for (final p in placed)
                Positioned(
                  top: p.top * hourHeight / 60,
                  height: p.height * hourHeight / 60 - 1,
                  left: w * p.column / p.columns + 1,
                  width: w / p.columns - 3,
                  child: _EventBlock(
                    key: ValueKey('mweek-event-${p.event.id}-${dayKey(day)}'),
                    placed: p,
                    day: day,
                    tags: tags,
                    hourHeight: hourHeight,
                    onTap: () => onOpen(p.event),
                  ),
                ),
              if (isToday)
                Positioned(
                  top: (now.hour * 60 + now.minute) * hourHeight / 60,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Container(key: const ValueKey('mweek-now-line'), height: 2, color: org.accentText),
                  ),
                ),
            ],
          );
        }),
      ),
    );
  }
}

String _hm(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

class _EventBlock extends StatelessWidget {
  const _EventBlock({
    super.key,
    required this.placed,
    required this.day,
    required this.tags,
    required this.hourHeight,
    required this.onTap,
  });

  final PlacedEvent placed;
  final DateTime day;
  final Map<String, EventTag> tags;
  final double hourHeight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final org = context.org;
    final e = placed.event;
    final look = eventLook(org, e, tags);
    final style = Theme.of(context)
        .textTheme
        .labelSmall
        ?.copyWith(color: look.text, fontSize: 10, height: 1.15);
    final blockHeight = placed.height * hourHeight / 60 - 1;
    final lines = blockHeight >= 56 ? 3 : (blockHeight >= 32 ? 2 : 1);
    return Semantics(
      label: eventSemanticLabel(e, day),
      button: true,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        // Segurar em cima de um evento não cria outro por baixo dele.
        onLongPress: () {},
        child: EventSurface(
          look: look,
          radius: org.radiusSm,
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          barKey: ValueKey('tag-bar-${e.id}-${dayKey(day)}'),
          child: LayoutBuilder(builder: (context, c) {
            if (c.maxWidth < _narrowContent) {
              return ClipRect(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: Text(_hm(placed.top), maxLines: 1, softWrap: false, style: style),
                  ),
                ),
              );
            }
            return SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.title,
                    maxLines: lines,
                    overflow: TextOverflow.ellipsis,
                    style: style?.copyWith(fontWeight: look.titleWeight),
                  ),
                  if (blockHeight >= 56) Text(_hm(placed.top), maxLines: 1, style: style),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }
}
