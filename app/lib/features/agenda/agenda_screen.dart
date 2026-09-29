import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../data/repository.dart';
import '../../domain/agenda.dart';
import '../../domain/calendar_event.dart';
import '../../domain/space.dart';
import '../../ui/common.dart';
import '../../ui/event_tile.dart';
import 'event_dialog.dart';

class AgendaScreen extends ConsumerStatefulWidget {
  const AgendaScreen({super.key});

  @override
  ConsumerState<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends ConsumerState<AgendaScreen> {
  late DateTime _weekStart = startOfWeek(ref.read(clockProvider)());

  DateTime _dayOfWeek(int i) => DateTime(_weekStart.year, _weekStart.month, _weekStart.day + i);

  void _shift(int days) => setState(() => _weekStart = _dayOfWeek(days));

  Future<void> _newEvent(List<Space> spaces) async {
    final now = ref.read(clockProvider)();
    final inWeek = !now.isBefore(_weekStart) && now.isBefore(_dayOfWeek(7));
    final event = await showDialog<CalendarEvent>(
      context: context,
      builder: (_) => EventDialog(initialDay: inWeek ? now : _weekStart, spaces: spaces),
    );
    if (event == null) return;
    try {
      await ref.read(repositoryProvider).upsertEvent(event);
    } on RepositoryException {
      if (mounted) showError(context, 'Não foi possível salvar o evento.');
    }
  }

  List<Widget> _day(DateTime day, List<CalendarEvent> events, Map<String, String> names) {
    final dayEvents = eventsOnDay(events, day);
    return [
      SectionHeader(DateFormat('EEEE, dd/MM', 'pt_BR').format(day)),
      if (dayEvents.isEmpty) const EmptyHint('—'),
      for (final e in dayEvents) EventTile(event: e, spaceName: names[e.spaceId]),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final events = ref.watch(eventsFromProvider(_weekStart));
    final spaces = ref.watch(spacesProvider);
    final short = DateFormat('d MMM', 'pt_BR');
    return Scaffold(
      appBar: AppBar(
        title: Text('${short.format(_weekStart)} – ${short.format(_dayOfWeek(6))}'),
        actions: [
          IconButton(
            key: const Key('prev-week'),
            tooltip: 'Semana anterior',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _shift(-7),
          ),
          TextButton(
            onPressed: () => setState(() => _weekStart = startOfWeek(ref.read(clockProvider)())),
            child: const Text('Esta semana'),
          ),
          IconButton(
            key: const Key('next-week'),
            tooltip: 'Próxima semana',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _shift(7),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('new-event'),
        tooltip: 'Novo evento',
        onPressed: () => _newEvent(spaces.value ?? const []),
        child: const Icon(Icons.add),
      ),
      body: asyncView(events, (eventList) {
        final names = {for (final s in spaces.value ?? const <Space>[]) s.id: s.name};
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (var i = 0; i < 7; i++) ..._day(_dayOfWeek(i), eventList, names),
          ],
        );
      }),
    );
  }
}
