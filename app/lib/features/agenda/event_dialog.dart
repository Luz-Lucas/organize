import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/agenda.dart';
import '../../domain/calendar_event.dart';
import '../../domain/event_tag.dart';
import '../../domain/ids.dart';
import '../../domain/recurrence.dart';
import '../../domain/reminders.dart';
import '../../domain/space.dart';
import '../../ui/org_theme.dart';
import '../common/reminder_chips.dart';
import '../notes/notebooks/notebooks_logic.dart' show parseFolderColor;
import 'repeat_section.dart';
import 'series_scope_dialog.dart';

/// Diálogo de criar/editar evento. Fecha devolvendo o [CalendarEvent] salvo.
///
/// Se [onSave]/[onDelete] forem passados, o diálogo só fecha quando devolvem
/// `null` (sucesso); uma mensagem de erro devolvida fica no diálogo, sem apagar
/// o que foi digitado.
///
/// Séries: com [onCreateSeries], evento novo ganha o seletor "Repetir" e, se
/// houver repetição, salva por ele em vez de [onSave]. Com [onSaveScoped] /
/// [onDeleteScoped], editar/excluir um evento que tem `seriesId` pergunta antes
/// a quais ocorrências a ação vale. A etiqueta escolhida segue esse mesmo escopo.
///
/// O campo "Etiqueta" (chips coloridos mais "Sem etiqueta") aparece com [tags] não vazio ou com
/// [onCreateTag]; esse callback abre o editor de etiqueta e devolve a criada (ou `null` se cancelou), que
/// entra na lista e já fica selecionada no evento (chip "+ Nova").
class EventDialog extends StatefulWidget {
  const EventDialog({
    super.key,
    required this.initialStart,
    required this.initialEnd,
    required this.spaces,
    this.tags = const [],
    this.onCreateTag,
    this.existing,
    this.onSave,
    this.onDelete,
    this.onCreateSeries,
    this.onSaveScoped,
    this.onDeleteScoped,
  });

  final DateTime initialStart;
  final DateTime initialEnd;
  final List<Space> spaces;
  final List<EventTag> tags;
  final Future<EventTag?> Function()? onCreateTag;
  final CalendarEvent? existing;
  final Future<String?> Function(CalendarEvent event)? onSave;
  final Future<String?> Function()? onDelete;
  final Future<String?> Function(CalendarEvent template, Recurrence recurrence)? onCreateSeries;
  final Future<String?> Function(CalendarEvent event, SeriesScope scope)? onSaveScoped;
  final Future<String?> Function(SeriesScope scope)? onDeleteScoped;

  @override
  State<EventDialog> createState() => _EventDialogState();
}

class _EventDialogState extends State<EventDialog> {
  late final TextEditingController _title = TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _location =
      TextEditingController(text: widget.existing?.location ?? '');
  late DateTime _startDay = startOfDay(widget.initialStart);
  late DateTime _endDay = _initialEndDay();

  /// Evento noturno já salvo (ex.: 23:30 → 00:15 do dia seguinte): o dia de
  /// término volta a ser o do início, e a "virada" é recalculada por
  /// [resolveEventEnd]. Assim, mudar só o horário de início não deixa o evento
  /// com 24 h de duração sem querer.
  DateTime _initialEndDay() {
    final s = widget.initialStart, e = widget.initialEnd;
    final sd = startOfDay(s);
    final next = DateTime(sd.year, sd.month, sd.day + 1);
    final overnight = startOfDay(e) == next && e.hour * 60 + e.minute <= s.hour * 60 + s.minute;
    return overnight ? sd : startOfDay(e);
  }
  late TimeOfDay _start = TimeOfDay.fromDateTime(widget.initialStart);
  late TimeOfDay _end = TimeOfDay.fromDateTime(widget.initialEnd);
  late String? _spaceId = widget.existing?.spaceId;

  /// Etiquetas do seletor: as recebidas mais as criadas com "+ Nova" enquanto o editor está aberto.
  late List<EventTag> _tags = widget.tags;

  /// Etiqueta escolhida; uma que não existe mais (apagada em outro aparelho) conta como nenhuma.
  late String? _tagId = _tags.any((t) => t.id == widget.existing?.tagId) ? widget.existing?.tagId : null;
  late List<int> _reminders = widget.existing?.reminders ?? defaultEventReminders;
  bool _busy = false;
  String? _error;

  // Repetição (só em evento novo).
  final _repeat = RepeatController();

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _repeat.dispose();
    super.dispose();
  }

  bool get _canRepeat => widget.existing == null && widget.onCreateSeries != null;
  DateTime get _startsAt =>
      DateTime(_startDay.year, _startDay.month, _startDay.day, _start.hour, _start.minute);

  /// Fim efetivo. No mesmo dia do início, um horário que não é depois do início
  /// (ex.: 22:00 → 02:00) vai para o dia seguinte; fim igual ao início continua
  /// inválido (validado por [validateEventTimes]).
  DateTime get _endsAt {
    final start = _startsAt;
    final resolved = resolveEventEnd(start, _endDay, _end.hour, _end.minute);
    final raw = DateTime(_endDay.year, _endDay.month, _endDay.day, _end.hour, _end.minute);
    return raw == start ? raw : resolved;
  }

  bool get _endsNextDay {
    final end = _endsAt;
    return end.isAfter(_startsAt) && startOfDay(end) != _startDay;
  }

  Future<void> _pickDay({required bool start}) async {
    final current = start ? _startDay : startOfDay(_endsAt);
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(current.year - 1),
      lastDate: DateTime(current.year + 5),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        final shift = (picked.difference(_startDay).inHours / 24).round();
        _startDay = picked;
        _endDay = DateTime(_endDay.year, _endDay.month, _endDay.day + shift);
      } else {
        _endDay = picked;
      }
    });
  }

  Future<void> _pickTime({required bool start}) async {
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final picked = await showTimePicker(
      context: context,
      initialTime: start ? _start : _end,
      initialEntryMode: wide ? TimePickerEntryMode.input : TimePickerEntryMode.dial,
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _start = picked;
      } else {
        _end = picked;
      }
    });
  }

  Future<void> _submit() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Dê um título ao evento.');
      return;
    }
    final start = _startsAt;
    final end = _endsAt;
    final problem = validateEventTimes(start, end);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final location = _location.text.trim();
    final old = widget.existing;
    final event = CalendarEvent(
      id: old?.id ?? newId(),
      title: title,
      startsAt: start,
      endsAt: end,
      allDay: old?.allDay ?? false,
      location: location.isEmpty ? null : location,
      spaceId: _spaceId,
      source: old?.source ?? 'manual',
      externalId: old?.externalId,
      seriesId: old?.seriesId,
      recurrence: old?.recurrence,
      tagId: _tagId,
      reminders: _reminders,
    );

    Future<String?> Function()? save;
    if (_canRepeat && _repeat.active) {
      final failure = _repeat.problem(_startDay, start,
          emptyMessage: 'A repetição não gera nenhum evento nesse período.');
      if (failure != null) {
        setState(() => _error = failure);
        return;
      }
      final rule = _repeat.recurrence(_startDay)!;
      save = () => widget.onCreateSeries!(event, rule);
    } else if (old?.seriesId != null && widget.onSaveScoped != null) {
      final scope = await showSeriesScopeDialog(context, deleting: false);
      if (scope == null || !mounted) return;
      save = () => widget.onSaveScoped!(event, scope);
    } else if (widget.onSave != null) {
      save = () => widget.onSave!(event);
    }
    if (save != null) {
      setState(() {
        _busy = true;
        _error = null;
      });
      final failure = await save();
      if (!mounted) return;
      if (failure != null) {
        setState(() {
          _busy = false;
          _error = failure;
        });
        return;
      }
    }
    if (mounted) Navigator.of(context).pop(event);
  }

  Future<void> _delete() async {
    final event = widget.existing!;
    Future<String?> Function()? delete = widget.onDelete;
    if (event.seriesId != null && widget.onDeleteScoped != null) {
      // Para eventos de série a escolha do escopo já é a confirmação.
      final scope = await showSeriesScopeDialog(context, deleting: true);
      if (scope == null || !mounted) return;
      delete = () => widget.onDeleteScoped!(scope);
    } else {
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
      if (confirmed != true || !mounted) return;
    }
    if (delete != null) {
      setState(() {
        _busy = true;
        _error = null;
      });
      final failure = await delete();
      if (!mounted) return;
      if (failure != null) {
        setState(() {
          _busy = false;
          _error = failure;
        });
        return;
      }
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _createTag() async {
    final created = await widget.onCreateTag!();
    if (created == null || !mounted) return;
    setState(() {
      if (!_tags.any((t) => t.id == created.id)) _tags = [..._tags, created];
      _tagId = created.id;
    });
  }

  List<Widget> _tagSection(BuildContext context) {
    final theme = Theme.of(context);
    final org = context.org;
    return [
      const SizedBox(height: 12),
      Text('Etiqueta', style: theme.textTheme.labelMedium?.copyWith(color: org.inkMuted)),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ChoiceChip(
            key: const Key('event-tag-none'),
            label: const Text('Sem etiqueta'),
            selected: _tagId == null,
            onSelected: _busy ? null : (_) => setState(() => _tagId = null),
          ),
          for (final t in _tags)
            ChoiceChip(
              key: Key('event-tag-${t.id}'),
              avatar: CircleAvatar(radius: 6, backgroundColor: parseFolderColor(t.color) ?? org.accentDeep),
              label: Text(t.name),
              selected: _tagId == t.id,
              onSelected: _busy ? null : (_) => setState(() => _tagId = t.id),
            ),
          if (widget.onCreateTag != null)
            ActionChip(
              key: const Key('event-tag-new'),
              label: const Text('+ Nova'),
              onPressed: _busy ? null : _createTag,
            ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final hm = DateFormat.Hm('pt_BR');
    final day = DateFormat("EEE, d 'de' MMM", 'pt_BR');
    final org = context.org;
    final editing = widget.existing != null;
    return AlertDialog(
      title: Text(editing ? 'Editar evento' : 'Novo evento'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const Key('event-title'),
                controller: _title,
                autofocus: !editing,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Título'),
              ),
              const SizedBox(height: 12),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const SizedBox(width: 56, child: Text('Início')),
                  TextButton(
                    key: const Key('event-start-day'),
                    onPressed: () => _pickDay(start: true),
                    child: Text(day.format(_startDay)),
                  ),
                  TextButton(
                    key: const Key('event-start-time'),
                    onPressed: () => _pickTime(start: true),
                    child: Text(hm.format(_startsAt)),
                  ),
                ],
              ),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const SizedBox(width: 56, child: Text('Fim')),
                  TextButton(
                    key: const Key('event-end-day'),
                    onPressed: () => _pickDay(start: false),
                    child: Text(day.format(startOfDay(_endsAt))),
                  ),
                  TextButton(
                    key: const Key('event-end-time'),
                    onPressed: () => _pickTime(start: false),
                    child: Text(hm.format(_endsAt)),
                  ),
                ],
              ),
              if (_endsNextDay)
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 4),
                  child: Text('Termina no dia seguinte',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: org.accentText)),
                ),
              if (_canRepeat)
                RepeatSection(
                  controller: _repeat,
                  startDay: _startDay,
                  startsAt: _startsAt,
                  keyPrefix: 'event',
                  enabled: !_busy,
                ),
              TextField(
                key: const Key('event-location'),
                controller: _location,
                decoration: const InputDecoration(labelText: 'Local (opcional)'),
              ),
              if (!(widget.existing?.allDay ?? false)) ...[
                const SizedBox(height: 12),
                ReminderChips(
                  selected: _reminders,
                  onChanged: (v) => setState(() => _reminders = v),
                  enabled: !_busy,
                ),
              ],
              if (_tags.isNotEmpty || widget.onCreateTag != null) ..._tagSection(context),
              if (widget.spaces.isNotEmpty) ...[
                const SizedBox(height: 12),
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
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (editing)
          TextButton(
            key: ValueKey('delete-event-${widget.existing!.id}'),
            onPressed: _busy ? null : _delete,
            child: Text('Excluir evento', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(key: const Key('event-save'), onPressed: _busy ? null : _submit, child: const Text('Salvar')),
      ],
    );
  }
}
