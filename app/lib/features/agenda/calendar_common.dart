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
