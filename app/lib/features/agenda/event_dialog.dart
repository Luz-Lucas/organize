import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/agenda.dart';
import '../../domain/calendar_event.dart';
import '../../domain/ids.dart';
import '../../domain/space.dart';

class EventDialog extends StatefulWidget {
  const EventDialog({super.key, required this.initialDay, required this.spaces});

  final DateTime initialDay;
  final List<Space> spaces;

  @override
  State<EventDialog> createState() => _EventDialogState();
}

class _EventDialogState extends State<EventDialog> {
  final _title = TextEditingController();
  late DateTime _day = startOfDay(widget.initialDay);
  TimeOfDay _start = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 9, minute: 40);
  String? _spaceId;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  DateTime _at(TimeOfDay t) => DateTime(_day.year, _day.month, _day.day, t.hour, t.minute);

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(_day.year - 1),
      lastDate: DateTime(_day.year + 5),
    );
    if (picked != null) setState(() => _day = picked);
  }

  Future<void> _pickTime({required bool start}) async {
    final picked = await showTimePicker(context: context, initialTime: start ? _start : _end);
    if (picked == null) return;
    setState(() {
      if (start) {
        _start = picked;
      } else {
        _end = picked;
      }
    });
  }

  void _submit() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Dê um título ao evento.');
      return;
    }
    final start = _at(_start);
    final end = _at(_end);
    final problem = validateEventTimes(start, end);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    Navigator.of(context).pop(CalendarEvent(
      id: newId(),
      title: title,
      startsAt: start,
      endsAt: end,
      spaceId: _spaceId,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final hm = DateFormat.Hm('pt_BR');
    return AlertDialog(
      title: const Text('Novo evento'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('event-title'),
              controller: _title,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Título'),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _pickDay,
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(_day)),
            ),
            Row(
              children: [
                TextButton(
                  onPressed: () => _pickTime(start: true),
                  child: Text('Início ${hm.format(_at(_start))}'),
                ),
                TextButton(
                  onPressed: () => _pickTime(start: false),
                  child: Text('Fim ${hm.format(_at(_end))}'),
                ),
              ],
            ),
            if (widget.spaces.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in widget.spaces)
                    ChoiceChip(
                      label: Text(s.name),
                      selected: _spaceId == s.id,
                      onSelected: (selected) => setState(() => _spaceId = selected ? s.id : null),
                    ),
                ],
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(onPressed: _submit, child: const Text('Salvar')),
      ],
    );
  }
}
