import 'ids.dart';
import 'recurrence.dart';
import 'task_item.dart';

/// Mantém as tarefas sem série e as concluídas; de cada série fica só a não
/// concluída de menor `dueAt` (a "próxima pendente"). A ordem da entrada é preservada.
List<TaskItem> nextPendingPerSeries(Iterable<TaskItem> tasks) {
  final list = tasks.toList();
  final next = <String, TaskItem>{};
  for (final t in list) {
    final id = t.seriesId;
    if (id == null || t.isDone) continue;
    final cur = next[id];
    if (cur == null || _byDue(t, cur) < 0) next[id] = t;
  }
  return [
    for (final t in list)
      if (t.seriesId == null || t.isDone || identical(next[t.seriesId], t)) t,
  ];
}

/// Prazo crescente; sem prazo vai para o fim; empate desempata pelo id.
int _byDue(TaskItem a, TaskItem b) {
  final ad = a.dueAt, bd = b.dueAt;
  if (ad == null && bd == null) return a.id.compareTo(b.id);
  if (ad == null) return 1;
  if (bd == null) return -1;
  final c = ad.compareTo(bd);
  return c != 0 ? c : a.id.compareTo(b.id);
}

/// Operações puras sobre as ocorrências materializadas de uma série de tarefas
/// (mesmas regras de [SeriesOps], com `dueAt` no lugar de `startsAt`).
class TaskSeriesOps {
  const TaskSeriesOps._();

  static DateTime _atDue(DateTime s, DateTime tpl) =>
      DateTime(s.year, s.month, s.day, tpl.hour, tpl.minute, tpl.second);

  /// Cria as ocorrências de [template] (que precisa de `dueAt`) segundo [r]; todas com o
  /// mesmo `seriesId`. A ocorrência que cai no mesmo instante do [template] reaproveita o `id`
  /// e o status dele; as demais nascem "a fazer".
  static List<TaskItem> buildSeries(TaskItem template, Recurrence r, String Function() newId) {
    final first = template.dueAt!;
    final seriesId = newId();
    final rule = r.freq == RepeatFreq.none ? null : r;
    var usedTemplateId = false;
    return [
      for (final s in r.expandStarts(first))
        () {
          final reuse = !usedTemplateId && s == first;
          if (reuse) usedTemplateId = true;
          final base = reuse ? template : template.copyWith(status: TaskStatus.todo, clearCompleted: true);
          return base.copyWith(
            id: reuse ? template.id : newId(),
            dueAt: _atDue(s, first),
            seriesId: rule == null ? null : seriesId,
            recurrence: rule,
            clearSeries: rule == null,
          );
        }(),
    ];
  }

  static List<TaskItem> _sorted(Iterable<TaskItem> l) => l.toList()..sort(_byDue);

  /// Registros a gravar ao editar [target] para [edited] com o [scope].
  ///
  /// - `one`: só o alvo, que sai da série.
  /// - `all`: todas recebem título/descrição/prioridade/espaço e o mesmo deslocamento de
  ///   prazo (dias e minutos). Ocorrências concluídas mantêm o `status`; só o alvo
  ///   assume o status de [edited].
  /// - `following`: igual a `all`, mas só as ocorrências a partir do alvo, que passam a
  ///   formar uma série nova (a menos que o alvo seja a primeira).
  static List<TaskItem> applyEdit(
    List<TaskItem> series,
    TaskItem target,
    TaskItem edited,
    SeriesScope scope, {
    String Function()? newSeriesId,
  }) {
    if (scope == SeriesScope.one) {
      return [edited.copyWith(clearSeries: true)];
    }
    final ordered = _sorted(series);
    final targetDue = target.dueAt;
    bool fromTarget(TaskItem t) => targetDue == null || t.dueAt == null || !t.dueAt!.isBefore(targetDue);
    final affected = scope == SeriesScope.all ? ordered : ordered.where(fromTarget).toList();
    final isFirst = affected.isEmpty || identical(affected.first, ordered.first);
    final seriesId = scope == SeriesScope.following && !isFirst ? (newSeriesId ?? newId)() : target.seriesId;

    final editedDue = edited.dueAt;
    var dayDelta = 0, minuteDelta = 0;
    if (targetDue != null && editedDue != null) {
      dayDelta = DateTime.utc(editedDue.year, editedDue.month, editedDue.day)
          .difference(DateTime.utc(targetDue.year, targetDue.month, targetDue.day))
          .inDays;
      minuteDelta = (editedDue.hour * 60 + editedDue.minute) - (targetDue.hour * 60 + targetDue.minute);
    }

    return [
      for (final t in affected)
        () {
          final due = t.dueAt;
          final isTarget = t.id == target.id;
          final shifted = due == null
              ? null
              : DateTime(due.year, due.month, due.day + dayDelta, due.hour, due.minute + minuteDelta);
          return t.copyWith(
            title: edited.title,
            description: edited.description,
            priority: edited.priority,
            dueAt: shifted,
            spaceId: edited.spaceId,
            clearSpace: edited.spaceId == null,
            reminders: edited.reminders,
            seriesId: seriesId,
            status: isTarget ? edited.status : null,
            completedAt: isTarget ? edited.completedAt : null,
            clearCompleted: isTarget && edited.completedAt == null,
          );
        }(),
    ];
  }

  /// Ids a apagar ao excluir [target] com o [scope].
  static List<String> deleteIds(List<TaskItem> series, TaskItem target, SeriesScope scope) {
    switch (scope) {
      case SeriesScope.one:
        return [target.id];
      case SeriesScope.all:
        return [for (final t in _sorted(series)) t.id];
      case SeriesScope.following:
        final due = target.dueAt;
        return [
          for (final t in _sorted(series))
            if (due == null || t.dueAt == null || !t.dueAt!.isBefore(due)) t.id,
        ];
    }
  }
}
