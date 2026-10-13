/// "YYYY-MM-DD" da data local (a hora é ignorada).
String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Exceção de um dia só para um despertar ("só amanhã"): pular ou tocar em
/// outro horário (mesmo num dia da semana que o despertar normalmente não toca).
class WakeOverride {
  const WakeOverride._({
    required this.planId,
    required this.date,
    required this.skip,
    this.hour,
    this.minute,
  });

  /// Não toca em [date].
  factory WakeOverride.skip(String planId, DateTime date) =>
      WakeOverride._(planId: planId, date: DateTime(date.year, date.month, date.day), skip: true);

  /// Toca às [hour]:[minute] em [date], no lugar do horário normal.
  factory WakeOverride.at(String planId, DateTime date, int hour, int minute) => WakeOverride._(
        planId: planId,
        date: DateTime(date.year, date.month, date.day),
        skip: false,
        hour: hour,
        minute: minute,
      );

  final String planId;

  /// Só a data, à meia-noite local.
  final DateTime date;
  final bool skip;
  final int? hour;
  final int? minute;

  String get dateKey => _formatDateKey(date);

  factory WakeOverride.fromMap(Map<String, dynamic> m) {
    final day = (m['run_date'] as String).split('-').map(int.parse).toList();
    final date = DateTime(day[0], day[1], day[2]);
    final planId = m['plan_id'] as String;
    final time = m['time'] as String?;
    if (m['skip'] == true || time == null) return WakeOverride.skip(planId, date);
    final parts = time.split(':');
    return WakeOverride.at(planId, date, int.parse(parts[0]), int.parse(parts[1]));
  }

  /// Sem `user_id`: o banco preenche com o usuário logado.
  Map<String, dynamic> toMap() => {
        'plan_id': planId,
        'run_date': dateKey,
        'skip': skip,
        'time': skip ? null : '${hour!.toString().padLeft(2, '0')}:${minute!.toString().padLeft(2, '0')}',
      };

  @override
  String toString() => 'WakeOverride(${toMap()})';

  @override
  bool operator ==(Object other) =>
      other is WakeOverride &&
      other.planId == planId &&
      other.date == date &&
      other.skip == skip &&
      other.hour == hour &&
      other.minute == minute;

  @override
  int get hashCode => Object.hash(planId, date, skip, hour, minute);
}

String _formatDateKey(DateTime d) => dateKey(d);
