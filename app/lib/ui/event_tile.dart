import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../domain/calendar_event.dart';

class EventTile extends StatelessWidget {
  const EventTile({super.key, required this.event, this.spaceName});

  final CalendarEvent event;
  final String? spaceName;

  @override
  Widget build(BuildContext context) {
    final hm = DateFormat.Hm('pt_BR');
    final time = event.allDay
        ? 'Dia todo'
        : '${hm.format(event.startsAt)}–${hm.format(event.endsAt)}';
    final location = event.location;
    final details = [
      time,
      ?spaceName,
      if (location != null && location.isNotEmpty) location,
    ].join(' · ');
    return ListTile(
      leading: const Icon(Icons.event_outlined),
      title: Text(event.title),
      subtitle: Text(details),
    );
  }
}
