import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/domain/calendar_event.dart';
import 'package:organizacional/domain/task_item.dart';
import 'package:organizacional/widgets/widget_snapshot.dart';

final now = DateTime(2026, 10, 11, 12);

CalendarEvent ev(String id, String title, DateTime s, DateTime e,
        {bool allDay = false, String? location}) =>
    CalendarEvent(id: id, title: title, startsAt: s, endsAt: e, allDay: allDay, location: location);

TaskItem task(String id, TaskStatus st, {DateTime? due, String? title}) =>
    TaskItem(id: id, title: title ?? id, status: st, dueAt: due);

List<dynamic> events(Map<String, String> s) => jsonDecode(s['w_events']!) as List;
List<dynamic> tasks(Map<String, String> s) => jsonDecode(s['w_tasks']!) as List;

Map<String, String> build({
  List<CalendarEvent> e = const [],
  List<TaskItem> t = const [],
  String theme = 'violeta',
  String state = 'ok',
}) =>
    buildWidgetSnapshot(now: now, events: e, tasks: t, themeId: theme, state: state);

void main() {
  test('tarefas de série não vão para o widget', () {
    final s = build(t: [
      const TaskItem(id: 'avulsa', title: 'Avulsa'),
      TaskItem(id: 'o1', title: 'Lab', dueAt: DateTime(2026, 10, 11, 23, 59), seriesId: 'lab'),
      TaskItem(id: 'o2', title: 'Lab', dueAt: DateTime(2026, 10, 18, 23, 59), seriesId: 'lab'),
    ]);
    expect(tasks(s).map((t) => t['id']), ['avulsa']);
  });

  test('chaves e tema', () {
    final s = build();
    expect(s.keys, containsAll(['w_state', 'w_generated_at', 'w_theme', 'w_events', 'w_tasks']));
    expect(s['w_state'], 'ok');
    expect(s['w_generated_at'], now.millisecondsSinceEpoch.toString());
    final theme = jsonDecode(s['w_theme']!) as Map<String, dynamic>;
    expect(theme.length, 10);
    expect(theme.values.every((v) => RegExp(r'^#[0-9A-F]{6}$').hasMatch(v as String)), isTrue);
    expect(theme['surface'], '#160F1E');
    expect(theme['danger'], '#F2726B');
  });

  test('tema desconhecido volta para violeta', () {
    final theme = jsonDecode(build(theme: 'xyz')['w_theme']!) as Map<String, dynamic>;
    expect(theme['surface'], '#160F1E');
    final safira = jsonDecode(build(theme: 'safira')['w_theme']!) as Map<String, dynamic>;
    expect(safira['surface'], '#081826');
  });

  test('janela de eventos, ordem, kind e campos', () {
    final h = const Duration(hours: 1);
    final s = build(e: [
      ev('late', 'Reunião NP', DateTime(2026, 10, 25, 9), DateTime(2026, 10, 25, 10)),
      ev('tooLate', 'X', DateTime(2026, 10, 26, 9), DateTime(2026, 10, 26, 10)),
      ev('old', 'Velho', DateTime(2026, 10, 9, 9), DateTime(2026, 10, 9, 10)),
      ev('yday', 'M02', DateTime(2026, 10, 10, 0), DateTime(2026, 10, 10, 0).add(h), location: ''),
      ev('p1', 'Prova 2 — M02 D', DateTime(2026, 10, 12, 8), DateTime(2026, 10, 12, 10), location: 'Sala 3'),
      ev('p2', 'NP3 — C03 E', DateTime(2026, 10, 13, 8), DateTime(2026, 10, 13, 10)),
      ev('o', 'Estudo - C03', DateTime(2026, 10, 14), DateTime(2026, 10, 15), allDay: true),
      ev('night', 'Plantão', DateTime(2026, 10, 11, 22), DateTime(2026, 10, 12, 2)),
    ]);
    final list = events(s);
    expect(list.map((e) => e['id']), ['yday', 'night', 'p1', 'p2', 'o', 'late']);
    Map m(String id) => list.firstWhere((e) => e['id'] == id) as Map;
    expect(m('yday')['kind'], 'aula');
    expect(m('yday')['location'], isNull);
    expect(m('p1')['kind'], 'prova');
    expect(m('p1')['location'], 'Sala 3');
    expect(m('p2')['kind'], 'prova');
    expect(m('o')['kind'], 'outro');
    expect(m('o')['allDay'], true);
    expect(m('late')['kind'], 'outro');
    expect(m('night')['start'], DateTime(2026, 10, 11, 22).millisecondsSinceEpoch);
    expect(m('night')['end'], DateTime(2026, 10, 12, 2).millisecondsSinceEpoch);
  });

  test('tarefas: só abertas, doing primeiro, due crescente, limite 30', () {
    final s = build(t: [
      task('done', TaskStatus.done),
      task('todoNo', TaskStatus.todo),
      task('todoLate', TaskStatus.todo, due: DateTime(2026, 10, 20)),
      task('todoSoon', TaskStatus.todo, due: DateTime(2026, 10, 12)),
      task('doingNo', TaskStatus.doing),
      task('doingSoon', TaskStatus.doing, due: DateTime(2026, 10, 13)),
    ]);
    final l = tasks(s);
    expect(l.map((t) => t['id']), ['doingSoon', 'doingNo', 'todoSoon', 'todoLate', 'todoNo']);
    expect(l.first['status'], 'doing');
    expect(l.first['due'], DateTime(2026, 10, 13).millisecondsSinceEpoch);
    expect(l.last['due'], isNull);

    final many = build(t: [for (var i = 0; i < 40; i++) task('t$i', TaskStatus.todo)]);
    expect(tasks(many).length, 30);
  });

  test('título com aspas, quebra de linha, emoji e barra sobrevive', () {
    const title = 'Ola "x"\nlinha 🎓 \\ fim';
    final s = build(
      e: [ev('1', title, DateTime(2026, 10, 11, 14), DateTime(2026, 10, 11, 15))],
      t: [task('2', TaskStatus.todo, title: title)],
    );
    expect(events(s).single['title'], title);
    expect(tasks(s).single['title'], title);
  });

  test('signed_out zera listas', () {
    final s = build(
      state: 'signed_out',
      e: [ev('1', 'M02', DateTime(2026, 10, 11, 14), DateTime(2026, 10, 11, 15))],
      t: [task('2', TaskStatus.todo)],
    );
    expect(s['w_state'], 'signed_out');
    expect(s['w_events'], '[]');
    expect(s['w_tasks'], '[]');
  });

  test('w_bg_alpha: sem transparência pedida, a chave não é gravada (não sobrescreve a preferência)', () {
    expect(build().containsKey('w_bg_alpha'), isFalse);
  });

  test('w_bg_alpha: porcentagem de transparência vira opacidade 0-255 junto do tema', () {
    Map<String, String> withPct(int pct) => buildWidgetSnapshot(
        now: now, events: const [], tasks: const [], themeId: 'violeta', bgTransparencyPct: pct);
    expect(withPct(0)['w_bg_alpha'], '255');
    expect(withPct(25)['w_bg_alpha'], '191');
    expect(withPct(50)['w_bg_alpha'], '128');
    expect(withPct(75)['w_bg_alpha'], '64');
    expect(withPct(90)['w_bg_alpha'], '26');
    expect(withPct(0).containsKey('w_theme'), isTrue);
  });
}
