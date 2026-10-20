import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../domain/recurrence.dart';
import '../../ui/org_theme.dart';

/// Estado da seção "Repetir" (frequência, dias, fim por data ou por quantidade),
/// compartilhado pelos diálogos de evento e de tarefa. O diálogo guarda um
/// [RepeatController], passa-o a [RepeatSection] e lê [recurrence] / [problem] ao salvar.
class RepeatController extends ChangeNotifier {
  RepeatFreq _freq = RepeatFreq.none;
  Set<int> _days = {};
  bool _daysTouched = false;
  bool _untilMode = true;
  DateTime? _until;
  final TextEditingController count = TextEditingController(text: '10');

  RepeatController() {
    count.addListener(notifyListeners);
  }

  RepeatFreq get freq => _freq;
  bool get active => _freq != RepeatFreq.none;
  bool get untilMode => _untilMode;
  bool get weeklyLike => _freq == RepeatFreq.weekly || _freq == RepeatFreq.biweekly;

  set freq(RepeatFreq f) {
    _freq = f;
    notifyListeners();
  }

  set untilMode(bool v) {
    _untilMode = v;
    notifyListeners();
  }

  set until(DateTime d) {
    _until = d;
    notifyListeners();
  }

  /// Dias marcados; sem escolha explícita vale o dia da semana de [startDay].
  Set<int> effectiveDays(DateTime startDay) => _daysTouched ? _days : {startDay.weekday};

  /// Alterna [day] (ISO, 1 = seg); sempre sobra pelo menos um dia marcado.
  void toggleDay(DateTime startDay, int day, bool on) {
    final next = {...effectiveDays(startDay)};
    on ? next.add(day) : next.remove(day);
    if (next.isEmpty) return;
    _days = next;
    _daysTouched = true;
    notifyListeners();
  }

  /// Data final padrão: três meses depois do início.
  DateTime effectiveUntil(DateTime startDay) =>
      _until ?? DateTime(startDay.year, startDay.month + 3, startDay.day);

  int? get countValue {
    final n = int.tryParse(count.text.trim());
    return n != null && n >= 1 && n <= maxSeriesOccurrences ? n : null;
  }

  /// Regra escolhida para uma repetição que começa em [startDay], ou `null` se não repete
  /// ou se estiver incompleta/inválida (veja [problem]).
  Recurrence? recurrence(DateTime startDay) {
    if (_freq == RepeatFreq.none) return null;
    if (_untilMode && effectiveUntil(startDay).isBefore(startDay)) return null;
    if (!_untilMode && countValue == null) return null;
    return Recurrence(
      freq: _freq,
      days: weeklyLike ? effectiveDays(startDay) : const {},
      until: _untilMode ? effectiveUntil(startDay) : null,
      count: _untilMode ? null : countValue,
    );
  }

  /// Mensagem de erro de quem salvou com a repetição ligada; `null` se está tudo certo.
  /// [emptyMessage] vale quando a regra não gera nenhuma ocorrência a partir de [start].
  String? problem(DateTime startDay, DateTime start, {required String emptyMessage}) {
    if (!active) return null;
    final rule = recurrence(startDay);
    if (rule == null) {
      return _untilMode
          ? 'A data final não pode ser antes do início.'
          : 'Informe de 1 a $maxSeriesOccurrences repetições.';
    }
    if (rule.expandStarts(start).isEmpty) return emptyMessage;
    return null;
  }

  @override
  void dispose() {
    count.dispose();
    super.dispose();
  }
}

/// Campos de repetição: seletor "Repetir", dias da semana, "Até"/"Vezes" e o resumo.
/// [keyPrefix] dá as chaves (`<prefix>-repeat`, `<prefix>-repeat-day-N`, …).
class RepeatSection extends StatelessWidget {
  const RepeatSection({
    super.key,
    required this.controller,
    required this.startDay,
    required this.startsAt,
    required this.keyPrefix,
    this.enabled = true,
  });

  final RepeatController controller;

  /// Dia do início da série (só a data).
  final DateTime startDay;

  /// Início completo (a hora entra no resumo).
  final DateTime startsAt;
  final String keyPrefix;
  final bool enabled;

  static const _dayLabels = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];

  Future<void> _pickUntil(BuildContext context) async {
    final until = controller.effectiveUntil(startDay);
    final picked = await showDatePicker(
      context: context,
      initialDate: until.isBefore(startDay) ? startDay : until,
      firstDate: startDay,
      lastDate: DateTime(startDay.year + 1, startDay.month, startDay.day),
    );
    if (picked != null) controller.until = picked;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final theme = Theme.of(context);
          final org = context.org;
          final rule = controller.recurrence(startDay);
          final untilMode = controller.untilMode;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<RepeatFreq>(
                key: Key('$keyPrefix-repeat'),
                isExpanded: true, // textos longos ("Quinzenal…") cortam com reticências em vez de estourar a 360 dp
                initialValue: controller.freq,
                decoration: const InputDecoration(labelText: 'Repetir'),
                items: [
                  for (final f in RepeatFreq.values) DropdownMenuItem(value: f, child: Text(f.label)),
                ],
                onChanged: enabled ? (f) => controller.freq = f ?? RepeatFreq.none : null,
              ),
              if (controller.active) ...[
                if (controller.weeklyLike)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (var d = 1; d <= 7; d++)
                          FilterChip(
                            key: Key('$keyPrefix-repeat-day-$d'),
                            label: Text(_dayLabels[d - 1]),
                            selected: controller.effectiveDays(startDay).contains(d),
                            onSelected: (on) => controller.toggleDay(startDay, d, on),
                          ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ChoiceChip(
                        key: Key('$keyPrefix-repeat-mode-until'),
                        label: const Text('Até'),
                        selected: untilMode,
                        onSelected: (_) => controller.untilMode = true,
                      ),
                      ChoiceChip(
                        key: Key('$keyPrefix-repeat-mode-count'),
                        label: const Text('Vezes'),
                        selected: !untilMode,
                        onSelected: (_) => controller.untilMode = false,
                      ),
                      if (untilMode)
                        TextButton(
                          key: Key('$keyPrefix-repeat-until'),
                          onPressed: () => _pickUntil(context),
                          child: Text(DateFormat("EEE, d 'de' MMM", 'pt_BR').format(controller.effectiveUntil(startDay))),
                        )
                      else
                        SizedBox(
                          width: 96,
                          child: TextField(
                            key: Key('$keyPrefix-repeat-count'),
                            controller: controller.count,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: const InputDecoration(labelText: 'Vezes', isDense: true),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Text(
                    rule == null
                        ? (untilMode
                            ? 'Escolha uma data final a partir do início.'
                            : 'Digite quantas vezes repetir (1 a $maxSeriesOccurrences).')
                        : rule.summary(startsAt),
                    key: Key('$keyPrefix-repeat-summary'),
                    style: theme.textTheme.bodySmall?.copyWith(color: org.accentText),
                  ),
                ),
              ],
            ],
          );
        },
      );
}
