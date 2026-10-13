import 'calendar_event.dart';
import 'ids.dart';

/// Máximo de ocorrências geradas por série.
const maxSeriesOccurrences = 366;

enum RepeatFreq {
  none('Não repete'),
  daily('Todo dia'),
  weekdays('Dias úteis (seg–sex)'),
  weekly('Toda semana'),
  biweekly('A cada 2 semanas'),
  monthly('Todo mês');

  const RepeatFreq(this.label);

  final String label;

  static RepeatFreq fromName(Object? name) =>
      RepeatFreq.values.firstWhere((f) => f.name == name, orElse: () => RepeatFreq.none);
}

enum SeriesScope { one, following, all }

const _weekdayNames = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];
const _monthNames = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Regra usada para gerar as ocorrências de uma série. Dias ISO: 1 = seg … 7 = dom.
///
/// O banco guarda as ocorrências já materializadas; a regra é só informativa.
class Recurrence {
  Recurrence({required this.freq, Set<int> days = const {}, DateTime? until, this.count})
      : days = Set.unmodifiable(days),
        until = until == null ? null : DateTime(until.year, until.month, until.day);

  final RepeatFreq freq;
  final Set<int> days;

  /// Último dia possível (inclusivo).
  final DateTime? until;
  final int? count;

  factory Recurrence.fromMap(Map<String, dynamic> m) => Recurrence(
        freq: RepeatFreq.fromName(m['freq']),
        days: {for (final d in (m['days'] as List?) ?? const []) (d as num).toInt()},
        until: m['until'] == null ? null : DateTime.parse(m['until'] as String),
        count: (m['count'] as num?)?.toInt(),
      );

  Map<String, dynamic> toMap() => {
        'freq': freq.name,
        'days': (days.toList()..sort()),
        'until': until == null ? null : _ymd(until!),
        'count': count,
      };

  /// Inícios das ocorrências, na hora local de [firstStart] (que é o horário
  /// de referência, mas só entra se casar com a regra). Para no `until`
  /// (inclusivo), no `count`, em 366 ocorrências ou 1 ano após [firstStart].
  List<DateTime> expandStarts(DateTime firstStart) {
    if (freq == RepeatFreq.none) return [firstStart];
    final f = firstStart;
    final limit = DateTime(f.year + 1, f.month, f.day, f.hour, f.minute);
    final max = count == null ? maxSeriesOccurrences : count!.clamp(1, maxSeriesOccurrences);
    final out = <DateTime>[];

    bool accept(DateTime d) {
      if (d.isAfter(limit)) return false;
      if (until != null && DateTime(d.year, d.month, d.day).isAfter(until!)) return false;
      return true;
    }

    if (freq == RepeatFreq.monthly) {
      for (var i = 0; i < 14 && out.length < max; i++) {
        final d = DateTime(f.year, f.month + i, f.day, f.hour, f.minute);
        final expectedMonth = (f.month - 1 + i) % 12 + 1;
        if (d.month != expectedMonth) continue; // mês sem esse dia
        if (!accept(d)) break;
        out.add(d);
      }
      return out;
    }

    final wanted = days.isEmpty ? {f.weekday} : days;
    final interval = freq == RepeatFreq.biweekly ? 2 : 1;
    final mondayOffset = f.weekday - 1;
    for (var i = 0; i <= 372 && out.length < max; i++) {
      final d = DateTime(f.year, f.month, f.day + i, f.hour, f.minute);
      if (!accept(d)) break;
      final ok = switch (freq) {
        RepeatFreq.daily => true,
        RepeatFreq.weekdays => d.weekday <= DateTime.friday,
        _ => wanted.contains(d.weekday) && ((i + mondayOffset) ~/ 7) % interval == 0,
      };
      if (ok) out.add(d);
    }
    return out;
  }

  /// Ex.: "Toda semana às ter e qui, até 15 dez · 18 ocorrências".
  String summary(DateTime firstStart) {
    final starts = expandStarts(firstStart);
    if (starts.isEmpty) return 'Nenhuma ocorrência no período';
    String names(Set<int> ds) {
      final l = (ds.toList()..sort()).map((d) => _weekdayNames[d - 1]).toList();
      return l.length == 1 ? l.single : '${l.sublist(0, l.length - 1).join(', ')} e ${l.last}';
    }

    final head = switch (freq) {
      RepeatFreq.none => freq.label,
      RepeatFreq.daily || RepeatFreq.weekdays => freq.label,
      RepeatFreq.weekly || RepeatFreq.biweekly =>
        '${freq.label} às ${names(days.isEmpty ? {firstStart.weekday} : days)}',
      RepeatFreq.monthly => 'Todo mês no dia ${firstStart.day}',
    };
    final last = starts.last;
    final n = starts.length;
    return '$head, até ${last.day} ${_monthNames[last.month - 1]} · $n ${n == 1 ? 'ocorrência' : 'ocorrências'}';
  }

  @override
  bool operator ==(Object other) =>
      other is Recurrence &&
      other.freq == freq &&
      other.count == count &&
      other.until == until &&
      other.days.length == days.length &&
      other.days.containsAll(days);

  @override
  int get hashCode => Object.hash(freq, count, until, Object.hashAll((days.toList()..sort())));
}

/// Operações puras sobre as ocorrências materializadas de uma série.
class SeriesOps {
  const SeriesOps._();

  static DateTime _atStart(DateTime s, DateTime tpl) =>
      DateTime(s.year, s.month, s.day, tpl.hour, tpl.minute, tpl.second);

  /// Cria as ocorrências de [template] segundo [r]; todas com o mesmo `seriesId`.
  /// A duração (em minutos) é a do [template]; a ocorrência que cai no mesmo
  /// instante do [template] reaproveita o `id` dele.
  static List<CalendarEvent> buildSeries(CalendarEvent template, Recurrence r, String Function() newId) {
    final seriesId = newId();
    final minutes = template.endsAt.difference(template.startsAt).inMinutes;
    final rule = r.freq == RepeatFreq.none ? null : r;
    var usedTemplateId = false;
    return [
      for (final s in r.expandStarts(template.startsAt))
        () {
          final reuse = !usedTemplateId && s == template.startsAt;
          if (reuse) usedTemplateId = true;
          final start = _atStart(s, template.startsAt);
          return template.copyWith(
            id: reuse ? template.id : newId(),
            startsAt: start,
            endsAt: DateTime(start.year, start.month, start.day, start.hour, start.minute + minutes),
            seriesId: rule == null ? null : seriesId,
            recurrence: rule,
            clearSeries: rule == null,
          );
        }(),
    ];
  }

  static List<CalendarEvent> _sorted(Iterable<CalendarEvent> l) =>
      l.toList()..sort((a, b) => a.startsAt.compareTo(b.startsAt));

  /// Registros a gravar ao editar [target] para [edited] com o [scope].
  ///
  /// - `one`: só o alvo, que sai da série.
  /// - `all`: todas recebem título/local/espaço/dia-inteiro, o mesmo
  ///   deslocamento de início (dias e minutos) e a nova duração.
  /// - `following`: igual a `all`, mas só as ocorrências a partir do alvo, que
  ///   passam a formar uma série nova (a menos que o alvo seja a primeira).
  static List<CalendarEvent> applyEdit(
    List<CalendarEvent> series,
    CalendarEvent target,
    CalendarEvent edited,
    SeriesScope scope, {
    String Function()? newSeriesId,
  }) {
    if (scope == SeriesScope.one) {
      return [edited.copyWith(clearSeries: true)];
    }
    final ordered = _sorted(series);
    final affected = scope == SeriesScope.all
        ? ordered
        : ordered.where((e) => !e.startsAt.isBefore(target.startsAt)).toList();
    final isFirst = ordered.isEmpty || !ordered.first.startsAt.isBefore(target.startsAt);
    final seriesId = scope == SeriesScope.following && !isFirst ? (newSeriesId ?? newId)() : target.seriesId;

    final dayDelta = DateTime.utc(edited.startsAt.year, edited.startsAt.month, edited.startsAt.day)
        .difference(DateTime.utc(target.startsAt.year, target.startsAt.month, target.startsAt.day))
        .inDays;
    final minuteDelta = (edited.startsAt.hour * 60 + edited.startsAt.minute) -
        (target.startsAt.hour * 60 + target.startsAt.minute);
    final minutes = edited.endsAt.difference(edited.startsAt).inMinutes;

    return [
      for (final e in affected)
        () {
          final start = DateTime(
              e.startsAt.year, e.startsAt.month, e.startsAt.day + dayDelta, e.startsAt.hour, e.startsAt.minute + minuteDelta);
          return e.copyWith(
            title: edited.title,
            location: edited.location,
            spaceId: edited.spaceId,
            allDay: edited.allDay,
            startsAt: start,
            endsAt: DateTime(start.year, start.month, start.day, start.hour, start.minute + minutes),
            seriesId: seriesId,
            clearLocation: edited.location == null,
            clearSpace: edited.spaceId == null,
          );
        }(),
    ];
  }

  /// Ids a apagar ao excluir [target] com o [scope].
  static List<String> deleteIds(List<CalendarEvent> series, CalendarEvent target, SeriesScope scope) {
    switch (scope) {
      case SeriesScope.one:
        return [target.id];
      case SeriesScope.all:
        return [for (final e in _sorted(series)) e.id];
      case SeriesScope.following:
        return [
          for (final e in _sorted(series))
            if (!e.startsAt.isBefore(target.startsAt)) e.id,
        ];
    }
  }
}
