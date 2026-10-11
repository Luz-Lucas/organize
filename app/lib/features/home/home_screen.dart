import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/alexa_repository.dart';
import '../../data/repository.dart';
import '../../domain/alexa.dart';
import '../../domain/user_settings.dart';
import '../../ui/common.dart';
import '../../ui/motif_painter.dart';
import '../../ui/org_theme.dart';
import '../../ui/org_widgets.dart';

typedef SendCommand = Future<void> Function(String kind, Map<String, Object?> payload);

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _speech = TextEditingController();
  String? _echoId;

  @override
  void dispose() {
    _speech.dispose();
    super.dispose();
  }

  Future<void> _send(String kind, Map<String, Object?> payload) async {
    try {
      final outcome = await runCommand(ref.read(alexaRepositoryProvider), kind, payload);
      if (!mounted) return;
      showError(context, outcome);
    } on RepositoryException {
      if (mounted) showError(context, 'Não foi possível enviar o comando.');
    }
  }

  Future<void> _toggle(WakePlan plan, bool enabled) async {
    try {
      await ref.read(alexaRepositoryProvider).upsertWakePlan(plan.copyWith(enabled: enabled));
    } on RepositoryException {
      if (mounted) showError(context, 'Não foi possível alterar o despertar.');
    }
  }

  Future<void> _setHidden(String id, bool hide) async {
    try {
      await ref.read(settingsRepositoryProvider).setDeviceHidden(id, hide);
    } on RepositoryException {
      if (mounted) {
        showError(
          context,
          hide ? 'Não foi possível ocultar o dispositivo.' : 'Não foi possível mostrar o dispositivo.',
        );
      }
    }
  }

  Future<void> _remove(AlexaDevice d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover da Alexa?'),
        content: Text('Isso apaga “${d.name}” da sua conta Amazon. Não dá para desfazer pelo app.'),
        actions: [
          TextButton(
            key: const Key('remove-cancel'),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('remove-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok == true) await _send('delete_device', {'entityId': d.id});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final org = context.org;
    final hiddenIds = (ref.watch(settingsProvider).value ?? const UserSettings()).hiddenAlexaDevices.toSet();
    final now = ref.watch(clockProvider)();
    final status = ref.watch(bridgeStatusProvider).value;
    final allDevices = ref.watch(alexaDevicesProvider).value ?? const <AlexaDevice>[];
    final devices = allDevices.where((d) => !hiddenIds.contains(d.id)).toList();
    final hidden = allDevices.where((d) => hiddenIds.contains(d.id)).toList();
    final routines = ref.watch(alexaRoutinesProvider).value ?? const <AlexaRoutine>[];
    final plans = ref.watch(wakePlansProvider).value ?? const <WakePlan>[];
    final echos = devices.where((d) => d.kind == 'echo').toList();
    final smart = devices.where((d) => d.kind == 'smart').toList();
    final echoId = _echoId ?? echos.where((e) => e.online).firstOrNull?.id ?? echos.firstOrNull?.id;
    final names = {for (final e in echos) e.id: e.name};
    final banner = bridgeBanner(status, now);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: MotifBackground(
                height: 90,
                child: PageHeader(
                  title: 'Casa',
                  subtitle: 'Despertares, rotinas e dispositivos',
                  actions: [
                    IconButton(
                      key: const Key('sync-alexa'),
                      tooltip: 'Sincronizar com a Alexa',
                      icon: const Icon(Icons.sync),
                      onPressed: () => _send('sync', const {}),
                    ),
                  ],
                ),
              ),
            ),
            if (banner != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  key: const Key('bridge-banner'),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(org.radiusMd),
                  ),
                  child: Text(banner, style: TextStyle(color: theme.colorScheme.onErrorContainer)),
                ),
              ),
            if (echos.isNotEmpty) ...[
              const SectionHeader('Tocar em'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in echos)
                    ChoiceChip(
                      key: ValueKey('echo-${e.id}'),
                      label: Text(e.online ? e.name : '${e.name} (offline)'),
                      selected: e.id == echoId,
                      onSelected: (_) => setState(() => _echoId = e.id),
                    ),
                ],
              ),
            ],
            Row(
              children: [
                const Expanded(child: SectionHeader('Despertar')),
                TextButton.icon(
                  key: const Key('new-wake'),
                  onPressed: () => context.go('/casa/despertar/novo'),
                  icon: const Icon(Icons.add),
                  label: const Text('Novo'),
                ),
              ],
            ),
            if (plans.isEmpty) const EmptyHint('Nenhum despertar. Crie um para tocar Spotify e ouvir seu dia.'),
            if (plans.isNotEmpty)
              OrgCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    for (final p in plans)
                      ListTile(
                        leading: Icon(Icons.alarm, color: org.accent),
                        title: Text(p.label),
                        subtitle: Text(wakeSummary(p, names)),
                        trailing: Switch(
                          key: ValueKey('wake-enabled-${p.id}'),
                          value: p.enabled,
                          onChanged: (v) => _toggle(p, v),
                        ),
                        onTap: () => context.go('/casa/despertar/${p.id}'),
                      ),
                  ],
                ),
              ),
            const SectionHeader('Rotinas da Alexa'),
            if (routines.isEmpty) const EmptyHint('Nenhuma rotina sincronizada.'),
            if (routines.isNotEmpty)
              OrgCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    for (final r in routines)
                      ListTile(
                        leading: Icon(Icons.play_circle_outline, color: org.accent),
                        title: Text(r.name),
                        trailing: IconButton(
                          key: ValueKey('run-routine-${r.id}'),
                          tooltip: 'Executar',
                          icon: const Icon(Icons.play_arrow),
                          onPressed: echoId == null
                              ? null
                              : () => _send('routine', {'routineId': r.id, 'echoDeviceId': echoId}),
                        ),
                      ),
                  ],
                ),
              ),
            const SectionHeader('Dispositivos'),
            if (smart.isEmpty) const EmptyHint('Nenhum dispositivo inteligente encontrado.'),
            if (smart.isNotEmpty)
              OrgCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    for (final d in smart)
                      _DeviceTile(
                        key: ValueKey('device-${d.id}'),
                        device: d,
                        onCommand: _send,
                        onHide: () => _setHidden(d.id, true),
                        onRemove: () => _remove(d),
                      ),
                  ],
                ),
              ),
            if (hidden.isNotEmpty)
              Column(
                key: const Key('hidden-devices'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionHeader('Ocultos (${hidden.length})'),
                  OrgCard(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
                        for (final d in hidden)
                          ListTile(
                            leading: Icon(
                              d.kind == 'echo' ? Icons.speaker_outlined : Icons.visibility_off_outlined,
                              color: org.inkMuted,
                            ),
                            title: Text(d.name),
                            trailing: TextButton(
                              key: ValueKey('show-${d.id}'),
                              onPressed: () => _setHidden(d.id, false),
                              child: const Text('Mostrar'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            const SectionHeader('Falar no Echo'),
            OrgCard(
              child: TextField(
                key: const Key('speak-text'),
                controller: _speech,
                decoration: InputDecoration(
                  hintText: 'Ex.: o jantar está pronto',
                  suffixIcon: IconButton(
                    key: const Key('speak-send'),
                    tooltip: 'Falar',
                    icon: const Icon(Icons.campaign_outlined),
                    onPressed: echoId == null
                        ? null
                        : () {
                            final text = _speech.text.trim();
                            if (text.isEmpty) return;
                            _speech.clear();
                            _send('speak', {'echoDeviceId': echoId, 'text': text});
                          },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceTile extends StatefulWidget {
  const _DeviceTile({
    super.key,
    required this.device,
    required this.onCommand,
    required this.onHide,
    required this.onRemove,
  });

  final AlexaDevice device;
  final SendCommand onCommand;
  final VoidCallback onHide;
  final VoidCallback onRemove;

  @override
  State<_DeviceTile> createState() => _DeviceTileState();
}

class _DeviceTileState extends State<_DeviceTile> {
  double _brightness = 50;

  @override
  Widget build(BuildContext context) {
    final d = widget.device;
    return Column(
      children: [
        ListTile(
          leading: Icon(Icons.lightbulb_outline, color: context.org.accent),
          title: Text(d.name),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (d.supports('turnOff'))
                IconButton(
                  key: ValueKey('off-${d.id}'),
                  tooltip: 'Desligar',
                  icon: const Icon(Icons.power_settings_new),
                  onPressed: () => widget.onCommand('device', {'entityId': d.id, 'action': 'turnOff'}),
                ),
              if (d.supports('turnOn'))
                IconButton(
                  key: ValueKey('on-${d.id}'),
                  tooltip: 'Ligar',
                  icon: const Icon(Icons.power),
                  onPressed: () => widget.onCommand('device', {'entityId': d.id, 'action': 'turnOn'}),
                ),
              PopupMenuButton<String>(
                key: ValueKey('device-menu-${d.id}'),
                tooltip: 'Mais opções',
                onSelected: (v) => v == 'hide' ? widget.onHide() : widget.onRemove(),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'hide', child: Text('Ocultar do app')),
                  if (d.kind == 'smart') const PopupMenuItem(value: 'remove', child: Text('Remover da Alexa')),
                ],
              ),
            ],
          ),
        ),
        if (d.supports('setBrightness'))
          Slider(
            key: ValueKey('brightness-${d.id}'),
            value: _brightness,
            max: 100,
            divisions: 10,
            label: '${_brightness.round()}%',
            onChanged: (v) => setState(() => _brightness = v),
            onChangeEnd: (v) =>
                widget.onCommand('device', {'entityId': d.id, 'action': 'setBrightness', 'brightness': v.round()}),
          ),
      ],
    );
  }
}
