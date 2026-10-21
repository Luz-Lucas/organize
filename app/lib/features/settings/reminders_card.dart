import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/repository.dart';
import '../../domain/alexa.dart';
import '../../domain/user_settings.dart';
import '../../ui/common.dart';
import '../../ui/org_theme.dart';
import '../../ui/org_widgets.dart';

/// Ajustes > "Lembretes": chave do celular, chave da Alexa com a escolha do Echo
/// e o não perturbe (chave + início + fim).
class RemindersCard extends ConsumerWidget {
  const RemindersCard({super.key});

  Future<void> _guarded(BuildContext context, Future<void> Function() op) async {
    try {
      await op();
    } on RepositoryException {
      if (context.mounted) showError(context, 'Não foi possível salvar os lembretes.');
    }
  }

  Future<void> _pickTime(BuildContext context, WidgetRef ref, {required bool start, required int minutes}) async {
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
      initialEntryMode: wide ? TimePickerEntryMode.input : TimePickerEntryMode.dial,
    );
    if (picked == null || !context.mounted) return;
    final value = picked.hour * 60 + picked.minute;
    final repo = ref.read(settingsRepositoryProvider);
    await _guarded(context, () => start ? repo.setDnd(start: value) : repo.setDnd(end: value));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider).value ?? const UserSettings();
    final repo = ref.read(settingsRepositoryProvider);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: context.org.inkMuted);
    final echos = (ref.watch(alexaDevicesProvider).value ?? const <AlexaDevice>[])
        .where((d) => d.kind == 'echo')
        .toList();
    final echo = echos.any((d) => d.id == s.reminderEcho) ? s.reminderEcho : null;
    return OrgCard(
      key: const Key('reminders-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            key: const Key('reminders-phone-switch'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Avisar no celular'),
            subtitle: const Text('Notificação no aparelho antes de tarefas e eventos.'),
            value: s.remindersPhone,
            onChanged: (v) => _guarded(context, () => repo.setRemindersPhone(v)),
          ),
          SwitchListTile(
            key: const Key('reminders-alexa-switch'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Avisar na Alexa'),
            subtitle: const Text('A Alexa fala o lembrete no Echo escolhido, se você não estiver fora de casa.'),
            value: s.remindersAlexa,
            onChanged: (v) => _guarded(context, () => repo.setRemindersAlexa(v)),
          ),
          if (s.remindersAlexa)
            if (echos.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('Nenhum Echo encontrado. Confira a ponte da Alexa.',
                    key: const Key('reminders-no-echo'), style: muted),
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Echo dos lembretes'),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      key: const Key('reminders-echo'),
                      isExpanded: true,
                      isDense: true,
                      value: echo,
                      hint: const Text('Escolha um Echo'),
                      items: [for (final d in echos) DropdownMenuItem(value: d.id, child: Text(d.name))],
                      onChanged: (id) => _guarded(context, () => repo.setReminderEcho(id)),
                    ),
                  ),
                ),
              ),
          SwitchListTile(
            key: const Key('reminders-dnd-switch'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Não perturbe'),
            subtitle: const Text('Lembretes dentro do intervalo esperam o fim dele, se ainda der tempo.'),
            value: s.dndEnabled,
            onChanged: (v) => _guarded(context, () => repo.setDnd(enabled: v)),
          ),
          if (s.dndEnabled)
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('Das'),
                TextButton(
                  key: const Key('reminders-dnd-start'),
                  onPressed: () => _pickTime(context, ref, start: true, minutes: s.dndStart),
                  child: Text(formatMinutesOfDay(s.dndStart)),
                ),
                const Text('às'),
                TextButton(
                  key: const Key('reminders-dnd-end'),
                  onPressed: () => _pickTime(context, ref, start: false, minutes: s.dndEnd),
                  child: Text(formatMinutesOfDay(s.dndEnd)),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
