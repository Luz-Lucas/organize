import '../../domain/alexa.dart';
import '../../domain/wake_override.dart';

/// Próxima vez em que um despertar com [days] (1 = segunda … 7 = domingo) e
/// horário [hour]:[minute] toca, estritamente depois de [now]. `null` sem dias.
DateTime? nextWakeAt(List<int> days, int hour, int minute, DateTime now) {
  if (days.isEmpty) return null;
  for (var add = 0; add <= 7; add++) {
    final candidate = DateTime(now.year, now.month, now.day + add, hour, minute);
    if (candidate.isAfter(now) && days.contains(candidate.weekday)) return candidate;
  }
  return null;
}

/// Próxima vez em que [plan] toca depois de [now], considerando as exceções de
/// data ([overrides], de qualquer plano; só as do próprio plano valem): pular um
/// dia, trocar o horário de um dia e tocar num dia fora de `plan.days`.
/// Ignora `plan.enabled` (quem chama decide). `null` se nunca mais toca.
DateTime? nextWake(WakePlan plan, Iterable<WakeOverride> overrides, DateTime now) {
  final own = {for (final o in overrides) if (o.planId == plan.id) o.dateKey: o};
  final today = DateTime(now.year, now.month, now.day);
  final dates = <DateTime>{
    for (var add = 0; add <= 7; add++) DateTime(today.year, today.month, today.day + add),
    for (final o in own.values)
      if (!o.date.isBefore(today)) o.date,
  }.toList()
    ..sort();
  for (final date in dates) {
    final o = own[dateKey(date)];
    final DateTime? candidate;
    if (o != null && o.skip) {
      candidate = null;
    } else if (o != null) {
      candidate = DateTime(date.year, date.month, date.day, o.hour!, o.minute!);
    } else if (plan.days.contains(date.weekday)) {
      candidate = DateTime(date.year, date.month, date.day, plan.hour, plan.minute);
    } else {
      candidate = null;
    }
    if (candidate != null && candidate.isAfter(now)) return candidate;
  }
  return null;
}

/// "em 7 h 20 min", "em 20 min", "em 2 d 3 h" (minutos arredondados para cima).
String wakeCountdown(DateTime at, DateTime now) {
  final diff = at.difference(now);
  final total = diff.inSeconds % 60 == 0 ? diff.inMinutes : diff.inMinutes + 1;
  final d = total ~/ (24 * 60);
  final h = (total % (24 * 60)) ~/ 60;
  final m = total % 60;
  final parts = d > 0
      ? ['$d d', if (h > 0) '$h h']
      : [if (h > 0) '$h h', if (m > 0) '$m min'];
  return 'em ${parts.isEmpty ? 'menos de 1 min' : parts.join(' ')}';
}

/// "Toca em 7 h 20 min", "Toca em 20 min", "Toca em 2 d 3 h" (minutos
/// arredondados para cima). `null` sem dias escolhidos.
String? wakeInLabel(List<int> days, int hour, int minute, DateTime now) {
  final at = nextWakeAt(days, hour, minute, now);
  return at == null ? null : 'Toca ${wakeCountdown(at, now)}';
}

/// Como [wakeInLabel], mas para um plano com exceções de data.
String? wakeInLabelFor(WakePlan plan, Iterable<WakeOverride> overrides, DateTime now) {
  final at = nextWake(plan, overrides, now);
  return at == null ? null : 'Toca ${wakeCountdown(at, now)}';
}
