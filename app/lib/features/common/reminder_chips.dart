import 'package:flutter/material.dart';

import '../../domain/reminders.dart';
import '../../ui/org_theme.dart';

/// "Lembrar": "Não lembrar" + quatro chips (1 dia, 1 hora, 30 min, 15 min antes), vários ao mesmo
/// tempo. [onChanged] recebe a lista nova, ordenada da maior antecedência para a
/// menor; pode ficar vazia (sem lembrete). Reutilizado nos editores de tarefa e de
/// evento. Chaves dos chips: `reminder-chip-none` e `reminder-chip-<minutos>`.
class ReminderChips extends StatelessWidget {
  const ReminderChips({
    super.key,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
    this.hint,
  });

  final List<int> selected;
  final ValueChanged<List<int>> onChanged;
  final bool enabled;

  /// Dica em texto pequeno abaixo dos chips.
  final String? hint;

  void _toggle(int minutes, bool on) {
    final next = on ? [...selected, minutes] : selected.where((m) => m != minutes);
    onChanged(normalizeReminders(next));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = context.org.inkMuted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Lembrar', style: theme.textTheme.labelMedium?.copyWith(color: muted)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            // Atalho explícito para "sem lembrete" (a lista vazia), já que nem todo evento é rígido.
            FilterChip(
              key: const Key('reminder-chip-none'),
              label: const Text('Não lembrar'),
              selected: selected.isEmpty,
              onSelected: enabled ? (_) => onChanged(const []) : null,
            ),
            for (final m in reminderOptions)
              FilterChip(
                key: Key('reminder-chip-$m'),
                label: Text(reminderLabel(m)),
                selected: selected.contains(m),
                onSelected: enabled ? (on) => _toggle(m, on) : null,
              ),
          ],
        ),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(hint!, key: const Key('reminder-hint'), style: theme.textTheme.bodySmall?.copyWith(color: muted)),
          ),
      ],
    );
  }
}
