import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/agenda.dart';
import '../../domain/calendar_event.dart';
import '../../ui/org_theme.dart';

/// Cor do evento: por espaço (hash entre três tons de `accentDeep`, que é a
/// cor segura para texto `onAccent`), sem espaço = `accentDeep`.
Color eventColor(OrgThemeSpec org, String? spaceId) {
  if (spaceId == null) return org.accentDeep;
  final h = spaceId.codeUnits.fold<int>(0, (a, b) => a + b) % 3;
  return switch (h) {
    0 => org.accentDeep,
    1 => Color.lerp(org.accentDeep, org.surface, 0.3)!,
    _ => Color.lerp(org.accentDeep, org.surface, 0.55)!,
  };
}

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// Horário do evento como aparece na lista do dia [day].
/// Ex.: "10:00–11:40", "22:00 → dom 02:00", "sáb 22:00 → 02:00", "Dia todo".
String eventTimeLabel(CalendarEvent e, DateTime day) {
  if (e.allDay) return 'Dia todo';
  final hm = DateFormat.Hm('pt_BR');
  final wd = DateFormat('EEE', 'pt_BR');
  String dow(DateTime d) => wd.format(d).replaceAll('.', '');
  final endsAtNextMidnight = e.endsAt == DateTime(e.startsAt.year, e.startsAt.month, e.startsAt.day + 1);
  if (_sameDay(e.startsAt, e.endsAt) || endsAtNextMidnight) {
    return '${hm.format(e.startsAt)}–${hm.format(e.endsAt)}';
  }
  if (_sameDay(e.startsAt, day)) {
    return '${hm.format(e.startsAt)} → ${dow(e.endsAt)} ${hm.format(e.endsAt)}';
  }
  return '${dow(e.startsAt)} ${hm.format(e.startsAt)} → ${hm.format(e.endsAt)}';
}

DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

String dayKey(DateTime d) => DateFormat('yyyy-MM-dd').format(startOfDay(d));

const weekdayInitials = ['D', 'S', 'T', 'Q', 'Q', 'S', 'S'];

const _weekdayNames = ['domingo', 'segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado'];

/// Dia da semana por extenso e sem "-feira" ("terça"), como se fala.
String weekdayName(DateTime d) => _weekdayNames[d.weekday % DateTime.daysPerWeek];

/// Rótulo falado do bloco do evento na grade de horas, por exemplo "Aula M02, terça 10:00 a 11:40".
/// Evento que vira a meia-noite cita os dois dias.
String eventSemanticLabel(CalendarEvent e, DateTime day) {
  if (e.allDay) return '${e.title}, ${weekdayName(day)}, dia inteiro';
  final hm = DateFormat.Hm('pt_BR');
  final endsAtNextMidnight = e.endsAt == DateTime(e.startsAt.year, e.startsAt.month, e.startsAt.day + 1);
  if (_sameDay(e.startsAt, e.endsAt) || endsAtNextMidnight) {
    return '${e.title}, ${weekdayName(e.startsAt)} ${hm.format(e.startsAt)} a ${hm.format(e.endsAt)}';
  }
  return '${e.title}, ${weekdayName(e.startsAt)} ${hm.format(e.startsAt)} a ${weekdayName(e.endsAt)} ${hm.format(e.endsAt)}';
}
