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

/// "Toca em 7 h 20 min", "Toca em 20 min", "Toca em 2 d 3 h" (minutos
/// arredondados para cima). `null` sem dias escolhidos.
String? wakeInLabel(List<int> days, int hour, int minute, DateTime now) {
  final at = nextWakeAt(days, hour, minute, now);
  if (at == null) return null;
  final diff = at.difference(now);
  final total = diff.inSeconds % 60 == 0 ? diff.inMinutes : diff.inMinutes + 1;
  final d = total ~/ (24 * 60);
  final h = (total % (24 * 60)) ~/ 60;
  final m = total % 60;
  final parts = d > 0
      ? ['$d d', if (h > 0) '$h h']
      : [if (h > 0) '$h h', if (m > 0) '$m min'];
  return 'Toca em ${parts.isEmpty ? 'menos de 1 min' : parts.join(' ')}';
}
