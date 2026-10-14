import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../data/repository.dart';
import '../../domain/agenda.dart';
import '../../domain/calendar_event.dart';
import '../../domain/event_tag.dart';
import '../../domain/ids.dart';
import '../../domain/recurrence.dart';
import '../../domain/space.dart';
import '../../ui/common.dart';
import '../../ui/org_theme.dart';
import '../../ui/org_widgets.dart';
import 'agenda_filter.dart';
import 'calendar_common.dart';
import 'calendar_layout.dart';
import 'event_dialog.dart';
import 'mobile_calendar.dart';
import 'month_view.dart';
import 'tag_filter_bar.dart';
import 'tag_style.dart';
import 'tags_manager.dart';
import 'week_view.dart';

enum _AgendaView { week, month }

/// Garante que a semeadura das etiquetas iniciais seja tentada uma vez por execução do app: quem apagou
/// todas as etiquetas de propósito não as vê voltar a cada visita à agenda.
class _SeedGuard {
  bool tried = false;
}

final _seedGuardProvider = Provider<_SeedGuard>((ref) => _SeedGuard());

class AgendaScreen extends ConsumerStatefulWidget {
  const AgendaScreen({super.key});

  @override
  ConsumerState<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends ConsumerState<AgendaScreen> {
  _AgendaView _view = _AgendaView.week;
  late DateTime _anchor = startOfDay(ref.read(clockProvider)());

  DateTime get _weekStart => startOfWeek(_anchor);

  /// Sem nenhuma etiqueta, pede a semeadura das iniciais (Aula, Academia, Sazonal, Reunião).
  void _maybeSeed(AsyncValue<List<EventTag>> tags) {
    final guard = ref.read(_seedGuardProvider);
    if (guard.tried || !tags.hasValue || tags.requireValue.isNotEmpty) return;
    guard.tried = true;
    final repo = ref.read(repositoryProvider);
    unawaited(() async {
      try {
        await repo.seedEventTags();
      } catch (_) {
        // Sem etiquetas a agenda funciona igual; tenta de novo na próxima execução.
        guard.tried = false;
      }
    }());
  }

  DateTime _monthOf(DateTime d, int delta) {
    final first = DateTime(d.year, d.month + delta, 1);
    final today = startOfDay(ref.read(clockProvider)());
    return first.year == today.year && first.month == today.month ? today : first;
  }

  Future<void> _edit(List<Space> spaces, {CalendarEvent? existing, DateTime? start, DateTime? end}) async {
    final repo = ref.read(repositoryProvider);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final now = ref.read(clockProvider)();
    final inWeek = !now.isBefore(_weekStart) && now.isBefore(addDays(_weekStart, 7));
    final weekMode = MediaQuery.sizeOf(context).width >= 720 && _view == _AgendaView.week;
    final day = weekMode ? (inWeek ? startOfDay(now) : _weekStart) : _anchor;
    final s = existing?.startsAt ?? start ?? DateTime(day.year, day.month, day.day, 8);
    final e = existing?.endsAt ?? end ?? DateTime(day.year, day.month, day.day, 9, 40);
    await showDialog<CalendarEvent>(
      context: context,
      builder: (_) => EventDialog(
        initialStart: s,
        initialEnd: e,
        spaces: spaces,
        tags: ref.read(eventTagsProvider).value ?? const <EventTag>[],
        existing: existing,
        onSave: (event) async {
          try {
            await repo.upsertEvent(event);
            return null;
          } on RepositoryException {
            return 'Não foi possível salvar o evento.';
          }
        },
        onDelete: existing == null
            ? null
            : () async {
                try {
                  await repo.deleteEvent(existing.id);
                  showUndo(messenger, 'Evento excluído', () => repo.upsertEvent(existing));
                  return null;
                } on RepositoryException {
                  return 'Não foi possível excluir o evento.';
                }
              },
        onCreateSeries: (template, rule) async {
          try {
            await repo.upsertEvents(SeriesOps.buildSeries(template, rule, newId));
            return null;
          } on RepositoryException {
            return 'Não foi possível salvar os eventos.';
          }
        },
        onSaveScoped: existing?.seriesId == null
            ? null
            : (event, scope) async {
                try {
                  final series = await _seriesOf(repo, existing!);
                  await repo.upsertEvents(SeriesOps.applyEdit(series, existing, event, scope));
                  return null;
                } on RepositoryException {
                  return 'Não foi possível salvar o evento.';
                }
              },
        onDeleteScoped: existing?.seriesId == null
            ? null
            : (scope) async {
                try {
                  final series = await _seriesOf(repo, existing!);
                  final ids = SeriesOps.deleteIds(series, existing, scope).toSet();
                  final removed = [for (final e in series) if (ids.contains(e.id)) e];
                  // Séries longas: apaga por series_id (e início), não por uma lista enorme de ids.
                  switch (scope) {
                    case SeriesScope.one:
                      await repo.deleteEvent(existing.id);
                    case SeriesScope.following:
                      await repo.deleteSeries(existing.seriesId!, from: existing.startsAt);
                    case SeriesScope.all:
                      await repo.deleteSeries(existing.seriesId!);
                  }
                  showUndo(
                    messenger,
                    removed.length == 1 ? 'Evento excluído' : '${removed.length} eventos excluídos',
                    () => repo.upsertEvents(removed),
                  );
                  return null;
                } on RepositoryException {
                  return 'Não foi possível excluir o evento.';
                }
              },
      ),
    );
  }

  /// Ocorrências da série de [event] (inclusive as que não estão na tela).
  Future<List<CalendarEvent>> _seriesOf(Repository repo, CalendarEvent event) async {
    final series = await repo.listSeries(event.seriesId!);
    return series.any((e) => e.id == event.id) ? series : [...series, event];
  }

  String _title(bool desktop) {
    if (desktop && _view == _AgendaView.week) {
      final a = _weekStart, b = addDays(_weekStart, 6);
      String mon(DateTime d) => DateFormat('MMM', 'pt_BR').format(d).replaceAll('.', '');
      if (a.month == b.month) return '${a.day} – ${b.day} ${mon(b)} ${b.year}';
      return '${a.day} ${mon(a)} – ${b.day} ${mon(b)} ${b.year}';
    }
    final s = DateFormat('MMMM yyyy', 'pt_BR').format(_anchor);
    return s[0].toUpperCase() + s.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.sizeOf(context).width >= 720;
    final week = desktop && _view == _AgendaView.week;
    final now = ref.watch(clockProvider)();
    final spaces = ref.watch(spacesProvider);
    final spaceList = spaces.value ?? const <Space>[];
    final from = week ? _weekStart : monthGrid(_anchor).first;
    final events = ref.watch(eventsFromProvider(from));
    final tagsAsync = ref.watch(eventTagsProvider);
    ref.listen(eventTagsProvider, (_, next) => _maybeSeed(next));
    _maybeSeed(tagsAsync);
    final tagList = tagsAsync.value ?? const <EventTag>[];
    final tags = tagMap(tagList);
    // Antes de as etiquetas chegarem não dá para saber o que é "sem etiqueta": não filtra.
    final hidden = tagsAsync.hasValue ? ref.watch(agendaHiddenTagsProvider) : const <String>{};
    final org = context.org;

    final actions = <Widget>[
      if (desktop) ...[
        ChoiceChip(
          key: const Key('view-week'),
          label: const Text('Semana'),
          selected: _view == _AgendaView.week,
          onSelected: (_) => setState(() => _view = _AgendaView.week),
        ),
        const SizedBox(width: 6),
        ChoiceChip(
          key: const Key('view-month'),
          label: const Text('Mês'),
          selected: _view == _AgendaView.month,
          onSelected: (_) => setState(() => _view = _AgendaView.month),
        ),
        const SizedBox(width: 12),
      ],
      IconButton(
        key: Key(week ? 'prev-week' : 'prev-month'),
        tooltip: week ? 'Semana anterior' : 'Mês anterior',
        icon: const Icon(Icons.chevron_left),
        onPressed: () => setState(() =>
            _anchor = week ? addDays(_anchor, -7) : _monthOf(_anchor, -1)),
      ),
      TextButton(
        key: const Key('today'),
        onPressed: () => setState(() => _anchor = startOfDay(ref.read(clockProvider)())),
        child: const Text('Hoje'),
      ),
      IconButton(
        key: Key(week ? 'next-week' : 'next-month'),
        tooltip: week ? 'Próxima semana' : 'Próximo mês',
        icon: const Icon(Icons.chevron_right),
        onPressed: () => setState(() =>
            _anchor = week ? addDays(_anchor, 7) : _monthOf(_anchor, 1)),
      ),
      PopupMenuButton<String>(
        key: const Key('agenda-menu'),
        tooltip: 'Menu da agenda',
        onSelected: (v) {
          if (v == 'tags') showTagsManager(context);
        },
        itemBuilder: (_) => const [
          PopupMenuItem(key: Key('menu-manage-tags'), value: 'tags', child: Text('Gerenciar etiquetas')),
        ],
      ),
    ];

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        key: const Key('new-event'),
        tooltip: 'Novo evento',
        backgroundColor: org.accentDeep,
        foregroundColor: org.onAccent,
        onPressed: () => _edit(spaceList),
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: Column(
          children: [
            PageHeader(title: _title(desktop), actions: actions),
            if (tagList.isNotEmpty)
              TagFilterBar(
                tags: tagList,
                hidden: hidden,
                onToggle: ref.read(agendaHiddenTagsProvider.notifier).toggle,
              ),
            Expanded(
              child: asyncView(events, (allEvents) {
                final eventList = filterByTag(allEvents, hidden, tags.keys.toSet());
                if (!desktop) {
                  return MobileCalendar(
                    selected: _anchor,
                    events: eventList,
                    now: now,
                    spaceNames: {for (final s in spaceList) s.id: s.name},
                    tags: tags,
                    onSelect: (d) => setState(() => _anchor = d),
                    onOpen: (e) => _edit(spaceList, existing: e),
                  );
                }
                if (_view == _AgendaView.month) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: MonthView(
                      month: _anchor,
                      events: eventList,
                      now: now,
                      tags: tags,
                      onOpenDay: (d) => setState(() {
                        _anchor = d;
                        _view = _AgendaView.week;
                      }),
                    ),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  child: WeekView(
                    key: ValueKey('week-${dayKey(_weekStart)}'),
                    weekStart: _weekStart,
                    events: eventList,
                    now: now,
                    tags: tags,
                    onCreate: (s, e) => _edit(spaceList, start: s, end: e),
                    onOpen: (e) => _edit(spaceList, existing: e),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}
