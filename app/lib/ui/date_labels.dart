import 'package:intl/intl.dart';

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Dias inteiros entre o início de hoje e o dia de [due] (negativo = passado).
int _diffDays(DateTime due, DateTime now) =>
    DateTime.utc(due.year, due.month, due.day).difference(DateTime.utc(now.year, now.month, now.day)).inDays;

/// O prazo é anterior ao início de hoje?
bool isOverdue(DateTime due, DateTime now) => _day(due).isBefore(_day(now));

String _noDots(String s) => s.replaceAll('.', '');

/// Rótulo de prazo usado em todo o app, curto e sem pontos de abreviação:
/// "hoje", "amanhã", dia da semana ("sex") nos próximos 6 dias, senão
/// "16 out" (com o ano só quando difere do atual).
///
/// Prazo anterior a hoje vira "atrasada · N d" (N dias de atraso). Para uma
/// tarefa já concluída passe [done] = true: aí o passado é só informativo
/// ("ontem", "12 set"), sem a palavra "atrasada".
String dueLabel(DateTime due, DateTime now, {bool done = false}) {
  final diff = _diffDays(due, now);
  if (diff < 0 && !done) return 'atrasada · ${-diff} d';
  if (diff == 0) return 'hoje';
  if (diff == 1) return 'amanhã';
  if (diff == -1) return 'ontem';
  if (diff >= 2 && diff <= 6) return _noDots(DateFormat('EEE', 'pt_BR').format(due));
  final pattern = due.year == now.year ? 'd MMM' : 'd MMM y';
  return _noDots(DateFormat(pattern, 'pt_BR').format(due));
}
