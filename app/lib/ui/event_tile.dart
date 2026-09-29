import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../app/providers.dart';
import '../data/repository.dart';
import '../domain/calendar_event.dart';
import 'common.dart';

class EventTile extends ConsumerWidget {
  const EventTile({super.key, required this.event, this.spaceName});

  final CalendarEvent event;
  final String? spaceName;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Excluir “${event.title}”?'),
        content: const Text('Essa ação não pode ser desfeita.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Excluir')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(repositoryProvider).deleteEvent(event.id);
    } on RepositoryException {
      if (context.mounted) showError(context, 'Não foi possível excluir o evento.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      trailing: IconButton(
        key: ValueKey('delete-event-${event.id}'),
        tooltip: 'Excluir',
        icon: const Icon(Icons.delete_outline),
        onPressed: () => _delete(context, ref),
      ),
    );
  }
}
