import 'package:flutter/material.dart';

import '../../domain/alexa.dart';
import '../../ui/org_theme.dart';
import '../../ui/org_widgets.dart';

const wakeDelayOptionsMin = [0, 1, 5, 10, 15, 30];

String _delayLabel(int min) => min == 0 ? 'Na hora' : '$min min';

/// Seção "Dispositivos no despertar": ações sobre luzes e tomadas inteligentes.
class WakeDeviceActionsSection extends StatelessWidget {
  const WakeDeviceActionsSection({
    super.key,
    required this.actions,
    required this.devices,
    required this.hiddenIds,
    required this.onChanged,
  });

  final List<WakeDeviceAction> actions;

  /// Todos os dispositivos conhecidos (qualquer tipo).
  final List<AlexaDevice> devices;
  final Set<String> hiddenIds;
  final ValueChanged<List<WakeDeviceAction>> onChanged;

  /// Dispositivos inteligentes visíveis que ainda não têm ação neste despertar.
  List<AlexaDevice> get _available => devices
      .where((d) => d.kind == 'smart' && !hiddenIds.contains(d.id) && !actions.any((a) => a.entityId == d.id))
      .toList();

  void _replace(WakeDeviceAction old, WakeDeviceAction updated) =>
      onChanged([for (final a in actions) a.entityId == old.entityId ? updated : a]);

  Future<void> _add(BuildContext context) async {
    final picked = await showModalBottomSheet<AlexaDevice>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final options = _available;
        if (options.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: EmptyHint('Nenhum dispositivo disponível. Sincronize na tela Casa ou mostre dispositivos ocultos.'),
          );
        }
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final d in options)
                ListTile(
                  key: ValueKey('device-pick-${d.id}'),
                  leading: const Icon(Icons.lightbulb_outline),
                  title: Text(d.name),
                  onTap: () => Navigator.of(ctx).pop(d),
                ),
            ],
          ),
        );
      },
    );
    if (picked == null) return;
    onChanged([
      ...actions,
      WakeDeviceAction(entityId: picked.id, name: picked.name, action: WakeActionType.turnOn),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final org = context.org;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Dispositivos no despertar'),
        if (actions.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Ligue luzes ou outros dispositivos junto com o despertar. Fora de casa, nada é ligado.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: org.inkMuted),
            ),
          ),
        for (final a in actions)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OrgCard(
              key: ValueKey('device-action-${a.entityId}'),
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
              child: _ActionEditor(
                action: a,
                device: devices.where((d) => d.id == a.entityId).firstOrNull,
                onChanged: (updated) => _replace(a, updated),
                onRemove: () => onChanged([for (final x in actions) if (x.entityId != a.entityId) x]),
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const Key('device-action-add'),
            onPressed: () => _add(context),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Adicionar dispositivo'),
          ),
        ),
      ],
    );
  }
}

class _ActionEditor extends StatelessWidget {
  const _ActionEditor({required this.action, required this.device, required this.onChanged, required this.onRemove});

  final WakeDeviceAction action;
  final AlexaDevice? device;
  final ValueChanged<WakeDeviceAction> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final id = action.entityId;
    final brightness = action.brightness ?? 100;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(action.name, style: Theme.of(context).textTheme.titleSmall)),
            IconButton(
              key: ValueKey('device-remove-$id'),
              tooltip: 'Remover',
              icon: const Icon(Icons.close),
              onPressed: onRemove,
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in WakeActionType.values)
              ChoiceChip(
                key: ValueKey('device-type-$id-${t.name}'),
                label: Text(t == WakeActionType.setBrightness && action.action == t ? 'Brilho $brightness%' : t.label),
                selected: action.action == t,
                // Se o dispositivo é conhecido e não tem a operação, não oferece.
                onSelected: device != null && !device!.supports(t.name) && device!.operations.isNotEmpty
                    ? null
                    : (_) => onChanged(action.copyWith(
                          action: t,
                          brightness: t == WakeActionType.setBrightness ? brightness : null,
                        )),
              ),
          ],
        ),
        if (action.action == WakeActionType.setBrightness)
          Slider(
            key: ValueKey('device-brightness-$id'),
            value: brightness.toDouble(),
            max: 100,
            divisions: 20,
            label: '$brightness%',
            onChanged: (v) => onChanged(action.copyWith(brightness: v.round())),
          ),
        const SizedBox(height: 4),
        Text('Quando', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.org.inkMuted)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in wakeDelayOptionsMin)
              ChoiceChip(
                key: ValueKey('device-delay-$id-$m'),
                label: Text(_delayLabel(m)),
                selected: action.delayMin == m,
                onSelected: (_) => onChanged(action.copyWith(delayMin: m)),
              ),
          ],
        ),
      ],
    );
  }
}
