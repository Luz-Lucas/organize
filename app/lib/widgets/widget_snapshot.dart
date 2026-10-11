import 'dart:convert';
import 'dart:ui' show Color;

import '../domain/calendar_event.dart';
import '../domain/task_item.dart';
import '../ui/themes.dart';

const _danger = '#F2726B';
final _provaRe = RegExp(r'^(prova|np\d)', caseSensitive: false);
final _aulaRe = RegExp(r'^[A-Z]\d{2}$');

String _hex(Color c) {
  final rgb = c.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

Map<String, String> _themeMap(String themeId) {
  final t = orgThemeById(themeId);
  return {
    'surface': _hex(t.surface),
    'surfaceRaised': _hex(t.surfaceRaised),
    'line': _hex(t.line),
    'ink': _hex(t.ink),
    'inkMuted': _hex(t.inkMuted),
    'accentDeep': _hex(t.accentDeep),
    'onAccent': _hex(t.onAccent),
    'accentText': _hex(t.accentText),
    'accentSoft': _hex(t.accentSoft),
    'danger': _danger,
  };
}

String _kind(String title) {
  final t = title.trim();
  if (_provaRe.hasMatch(t)) return 'prova';
  if (_aulaRe.hasMatch(t)) return 'aula';
  return 'outro';
}

/// Início do dia de ontem (calendário local) e limite superior da janela
/// (fim do dia de hoje + 14 dias).
DateTime widgetWindowStart(DateTime now) => DateTime(now.year, now.month, now.day - 1);
DateTime widgetWindowEnd(DateTime now) => DateTime(now.year, now.month, now.day + 15);

/// Monta o resumo que os widgets Android leem (contrato em
/// docs/superpowers/specs/2026-10-11-widgets-android-design.md).
/// `state` aceita apenas `ok` ou `signed_out`; `error` é gravado pelo
/// segundo plano sem tocar nas demais chaves.
Map<String, String> buildWidgetSnapshot({
  required DateTime now,
  required Iterable<CalendarEvent> events,
  required Iterable<TaskItem> tasks,
  required String themeId,
  String state = 'ok',
}) {
  assert(state == 'ok' || state == 'signed_out', 'state inválido: $state');
  final signedOut = state == 'signed_out';

  final start = widgetWindowStart(now);
  final end = widgetWindowEnd(now);
  final evs = signedOut
      ? <CalendarEvent>[]
      : (events
          .where((e) => !e.endsAt.isBefore(start) && e.startsAt.isBefore(end))
          .toList()
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt)));

  final open = signedOut
      ? <TaskItem>[]
      : (tasks.where((t) => !t.isDone).toList()
        ..sort((a, b) {
          final byStatus = (a.status == TaskStatus.doing ? 0 : 1)
              .compareTo(b.status == TaskStatus.doing ? 0 : 1);
          if (byStatus != 0) return byStatus;
          if (a.dueAt == null && b.dueAt == null) return 0;
          if (a.dueAt == null) return 1;
          if (b.dueAt == null) return -1;
          return a.dueAt!.compareTo(b.dueAt!);
        }));

  final eventsJson = evs
      .map((e) => {
            'id': e.id,
            'title': e.title,
            'start': e.startsAt.millisecondsSinceEpoch,
            'end': e.endsAt.millisecondsSinceEpoch,
            'allDay': e.allDay,
            'location': (e.location == null || e.location!.trim().isEmpty) ? null : e.location,
            'kind': _kind(e.title),
          })
      .toList();
  final tasksJson = open
      .take(30)
      .map((t) => {
            'id': t.id,
            'title': t.title,
            'status': t.status == TaskStatus.doing ? 'doing' : 'todo',
            'due': t.dueAt?.millisecondsSinceEpoch,
          })
      .toList();

  return {
    'w_state': state,
    'w_generated_at': now.millisecondsSinceEpoch.toString(),
    'w_theme': jsonEncode(_themeMap(themeId)),
    'w_events': jsonEncode(eventsJson),
    'w_tasks': jsonEncode(tasksJson),
  };
}
