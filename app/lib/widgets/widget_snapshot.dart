import 'dart:convert';
import 'dart:ui' show Color;

import '../domain/calendar_event.dart';
import '../domain/event_tag.dart';
import '../domain/shopping.dart';
import '../domain/task_item.dart';
import '../features/notes/notebooks/notebooks_logic.dart' show folderColorHex, parseFolderColor;
import '../ui/themes.dart';
import 'widget_appearance.dart';

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

/// Janela do widget Calendário: do 1º dia do mês anterior ao 1º dia do mês depois do seguinte
/// (fim exclusivo). As setas do widget não passam disso.
DateTime calendarWindowStart(DateTime now) => DateTime(now.year, now.month - 1, 1);
DateTime calendarWindowEnd(DateTime now) => DateTime(now.year, now.month + 2, 1);

/// Monta o resumo que os widgets Android leem (contrato em
/// docs/superpowers/specs/2026-10-11-widgets-android-design.md).
/// `state` aceita apenas `ok` ou `signed_out`; `error` é gravado pelo
/// segundo plano sem tocar nas demais chaves. `bgTransparencyPct` (preferência do
/// aparelho) vira `w_bg_alpha`; sem ele a chave não é gravada, preservando a escolha.
/// Tarefas de série (`seriesId`) não entram no widget.
/// Com [tags], cada evento etiquetado leva `tagColor` (`#RRGGBB`) para o widget desenhar o ponto colorido.
/// [calendarEvents] (widget Calendário) vira `w_cal_events` + `w_cal_range`; [shoppingLists] e [shoppingItems]
/// (widget Mercado) viram `w_shop`. Quando `null` (ainda não carregados ou consulta falhou) as chaves
/// não são gravadas, preservando o último resumo; em `signed_out` são gravadas vazias.
Map<String, String> buildWidgetSnapshot({
  required DateTime now,
  required Iterable<CalendarEvent> events,
  required Iterable<TaskItem> tasks,
  required String themeId,
  String state = 'ok',
  int? bgTransparencyPct,
  Iterable<EventTag> tags = const [],
  Iterable<CalendarEvent>? calendarEvents,
  Iterable<ShoppingList>? shoppingLists,
  Iterable<ShoppingItem>? shoppingItems,
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
      : (tasks.where((t) => !t.isDone && t.seriesId == null).toList()
        ..sort((a, b) {
          final byStatus = (a.status == TaskStatus.doing ? 0 : 1)
              .compareTo(b.status == TaskStatus.doing ? 0 : 1);
          if (byStatus != 0) return byStatus;
          if (a.dueAt == null && b.dueAt == null) return 0;
          if (a.dueAt == null) return 1;
          if (b.dueAt == null) return -1;
          return a.dueAt!.compareTo(b.dueAt!);
        }));

  final tagColors = <String, String>{
    for (final t in tags)
      if (parseFolderColor(t.color) case final c?) t.id: folderColorHex(c),
  };
  final eventsJson = evs
      .map((e) => {
            'id': e.id,
            'title': e.title,
            'start': e.startsAt.millisecondsSinceEpoch,
            'end': e.endsAt.millisecondsSinceEpoch,
            'allDay': e.allDay,
            'location': (e.location == null || e.location!.trim().isEmpty) ? null : e.location,
            'kind': _kind(e.title),
            'tagColor': e.tagId == null ? null : tagColors[e.tagId],
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

  final calStart = calendarWindowStart(now);
  final calEnd = calendarWindowEnd(now);
  final calJson = signedOut || calendarEvents == null
      ? <Map<String, Object?>>[]
      : (calendarEvents.where((e) => !e.endsAt.isBefore(calStart) && e.startsAt.isBefore(calEnd)).toList()
            ..sort((a, b) => a.startsAt.compareTo(b.startsAt)))
          .map((e) => {
                'id': e.id,
                'title': e.title,
                'start': e.startsAt.millisecondsSinceEpoch,
                'end': e.endsAt.millisecondsSinceEpoch,
                'allDay': e.allDay,
                'tagColor': e.tagId == null ? null : tagColors[e.tagId],
              })
          .toList();

  return {
    'w_state': state,
    'w_generated_at': now.millisecondsSinceEpoch.toString(),
    'w_theme': jsonEncode(_themeMap(themeId)),
    if (bgTransparencyPct != null) widgetBgAlphaKey: widgetBgAlphaFor(bgTransparencyPct).toString(),
    'w_events': jsonEncode(eventsJson),
    'w_tasks': jsonEncode(tasksJson),
    if (signedOut || calendarEvents != null) ...{
      'w_cal_events': jsonEncode(calJson),
      'w_cal_range': jsonEncode({
        'from': calStart.millisecondsSinceEpoch,
        'to': calEnd.millisecondsSinceEpoch,
      }),
    },
    if (signedOut || (shoppingLists != null && shoppingItems != null))
      'w_shop': jsonEncode(_shopJson(
          signedOut ? const [] : shoppingLists!, signedOut ? const [] : shoppingItems!)),
  };
}

/// Primeira lista (por `position`) com os itens não marcados agrupados por seção.
/// Sem nenhuma lista: `listId` nulo e nenhuma seção (o widget mostra "Lista vazia").
Map<String, Object?> _shopJson(Iterable<ShoppingList> lists, Iterable<ShoppingItem> items) {
  final indexed = lists.toList().asMap().entries.toList()
    ..sort((a, b) {
      final p = a.value.position.compareTo(b.value.position);
      return p != 0 ? p : a.key.compareTo(b.key);
    });
  if (indexed.isEmpty) {
    return {'listId': null, 'listName': 'Mercado', 'sections': <Object>[]};
  }
  final first = indexed.first.value;
  final pending = items.where((i) => i.listId == first.id && !i.checked).toList();
  return {
    'listId': first.id,
    'listName': first.name,
    'sections': [
      for (final (section, group) in groupBySection(pending, first.sectionOrder))
        {
          'name': section.name,
          'label': section.label,
          'items': [
            for (final i in group) {'id': i.id, 'name': i.name, 'quantity': i.quantity},
          ],
        },
    ],
  };
}
