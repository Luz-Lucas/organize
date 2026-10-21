/// Antecedências de lembrete, em minutos antes do horário do item
/// (1 dia, 1 hora, 30 min, 15 min), da maior para a menor.
const reminderOptions = [1440, 60, 30, 15];

/// Lembretes padrão: tarefa avisa 1 hora antes; evento, 30 minutos antes.
const defaultTaskReminders = [60];
const defaultEventReminders = [30];

String reminderLabel(int minutes) => switch (minutes) {
      1440 => '1 dia',
      60 => '1 hora',
      _ => '$minutes min',
    };

/// Só valores de [reminderOptions], sem repetidos, da maior antecedência para a menor.
List<int> normalizeReminders(Iterable<int> values) =>
    [for (final o in reminderOptions) if (values.contains(o)) o];

/// Lê a coluna `reminders` (lista de inteiros); ausente ou de outro tipo vira [fallback].
List<int> parseReminders(Object? value, List<int> fallback) {
  if (value is! List) return fallback;
  return [for (final v in value) if (v is num) v.toInt()];
}

bool sameReminders(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
