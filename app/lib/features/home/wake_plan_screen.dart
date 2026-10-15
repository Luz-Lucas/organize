import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/alexa_repository.dart';
import '../../data/repository.dart';
import '../../domain/alexa.dart';
import '../../domain/ids.dart';
import '../../domain/user_settings.dart';
import '../../domain/wake_override.dart';
import '../../ui/common.dart';
import '../../ui/org_theme.dart';
import 'wake_device_actions.dart';
import 'wake_next.dart';
import '../../app/back_navigation.dart';

const _stopOptions = [
  (sec: 15, label: '15 s'),
  (sec: 30, label: '30 s'),
  (sec: 60, label: '1 min'),
  (sec: 120, label: '2 min'),
  (sec: 300, label: '5 min'),
];

const _delayOptions = [
  (sec: 5, label: '5 s'),
  (sec: 10, label: '10 s'),
  (sec: 20, label: '20 s'),
  (sec: 30, label: '30 s'),
  (sec: 60, label: '1 min'),
  (sec: 120, label: '2 min'),
  (sec: 180, label: '3 min'),
];

String _customDelayLabel(int sec) => sec >= 60 && sec % 60 == 0 ? '${sec ~/ 60} min' : '$sec s';

class WakePlanScreen extends ConsumerStatefulWidget {
  const WakePlanScreen({super.key, required this.planId});

  /// "novo" cria um despertar.
  final String planId;

  @override
  ConsumerState<WakePlanScreen> createState() => _WakePlanScreenState();
}

class _WakePlanScreenState extends ConsumerState<WakePlanScreen> {
  final _label = TextEditingController();
  final _spotify = TextEditingController();
  WakePlan? _draft;
  String? _error;
  bool _dirty = false; // alterações ainda não salvas
  final _advanced = ExpansibleController();
  // "Avançado" nasce aberto quando o plano já tem algum valor fora do padrão.
  bool _advancedOpen = false;

  bool get _isNew => widget.planId == 'novo';

  @override
  void dispose() {
    _label.dispose();
    _spotify.dispose();
    super.dispose();
  }

  WakePlan _initial(List<WakePlan> plans, List<AlexaDevice> echos) {
    if (!_isNew) {
      final existing = plans.where((p) => p.id == widget.planId).firstOrNull;
      if (existing != null) return existing;
    }
    return WakePlan(
      id: newId(),
      label: 'Despertar',
      days: const [1, 2, 3, 4, 5],
      hour: 7,
      minute: 0,
      briefingDelaySec: 10,
      echoDeviceId: echos.where((e) => e.online).firstOrNull?.id ?? echos.firstOrNull?.id ?? '',
    );
  }

  void _update(WakePlan Function(WakePlan d) change) => setState(() {
        _draft = change(_draft!);
        _dirty = true;
      });

  /// Algum valor da seção "Avançado" difere do padrão de um despertar novo?
  bool _hasAdvancedValues(WakePlan p) =>
      p.musicStopAfterSec != null ||
      p.afterMusic != AfterMusic.briefing ||
      p.effectiveBriefingDelaySec != 10 ||
      p.volume != 30 ||
      !p.fallbackAlarm ||
      !p.includeWeather ||
      p.deviceActions.isNotEmpty;

  Future<void> _pickTime() async {
    final d = _draft!;
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay(hour: d.hour, minute: d.minute));
    if (!mounted) return;
    if (picked != null) _update((d) => d.copyWith(hour: picked.hour, minute: picked.minute));
  }

  Future<void> _save() async {
    final query = _spotify.text.trim();
    final plan = _draft!.copyWith(
      label: _label.text.trim(),
      spotifyQuery: query,
      clearMusicStop: query.isEmpty, // sem busca do Spotify não há música para parar
    );
    final problem = validateWakePlan(plan);
    if (problem != null) {
      setState(() => _error = problem);
      // Nome, dias e Echo ficam no topo; qualquer outro erro mora em "Avançado".
      final basic = plan.label.isEmpty || plan.days.isEmpty || plan.echoDeviceId.isEmpty;
      if (!basic && !_advancedOpen) {
        _advancedOpen = true;
        _advanced.expand();
      }
      return;
    }
    try {
      await ref.read(alexaRepositoryProvider).upsertWakePlan(plan);
      if (mounted) context.popOrGo('/casa');
    } on RepositoryException {
      if (mounted) setState(() => _error = 'Não foi possível salvar.');
    }
  }

  Future<void> _test() async {
    try {
      final outcome = await runCommand(
        ref.read(alexaRepositoryProvider),
        'wake_test',
        {'planId': widget.planId},
        timeout: const Duration(seconds: 90),
      );
      if (!mounted) return;
      showError(context, outcome);
    } on RepositoryException {
      if (mounted) showError(context, 'Não foi possível enviar o comando.');
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir despertar?'),
        content: const Text('O alarme reserva já agendado também será cancelado pela ponte.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Excluir')),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed != true) return;
    try {
      await ref.read(alexaRepositoryProvider).deleteWakePlan(widget.planId);
      if (mounted) context.popOrGo('/casa');
    } on RepositoryException {
      if (mounted) setState(() => _error = 'Não foi possível excluir.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final plansAsync = ref.watch(wakePlansProvider);
    final echos = (ref.watch(alexaDevicesProvider).value ?? const <AlexaDevice>[])
        .where((d) => d.kind == 'echo')
        .toList();
    return asyncView(plansAsync, (plans) {
      if (_draft == null) {
        if (!_isNew && !plans.any((p) => p.id == widget.planId)) {
          return Scaffold(appBar: AppBar(), body: const Center(child: EmptyHint('Despertar não encontrado.')));
        }
        _draft = _initial(plans, echos);
        _label.text = _draft!.label;
        _spotify.text = _draft!.spotifyQuery ?? '';
        _advancedOpen = _hasAdvancedValues(_draft!);
      }
      if (_draft!.echoDeviceId.isEmpty && echos.isNotEmpty) {
        _draft = _draft!.copyWith(echoDeviceId: echos.first.id); // dispositivos chegaram depois dos planos
      }
      final d = _draft!;
      final hasMusic = _spotify.text.trim().isNotEmpty;
      final stopping = hasMusic && d.musicStopAfterSec != null;
      final theme = Theme.of(context);
      final mobile = MediaQuery.sizeOf(context).width < 720;
      final next = wakeInLabelFor(
        d,
        ref.watch(wakeOverridesProvider).value ?? const <WakeOverride>[],
        ref.watch(clockProvider)(),
      );
      return Scaffold(
        appBar: AppBar(
          title: Text(_isNew ? 'Novo despertar' : 'Despertar'),
          actions: [
            if (!_isNew)
              IconButton(
                key: const Key('wake-delete'),
                tooltip: 'Excluir',
                icon: const Icon(Icons.delete_outline),
                onPressed: _delete,
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              key: const Key('wake-label'),
              controller: _label,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() => _dirty = true),
              decoration: const InputDecoration(labelText: 'Nome'),
            ),
            ListTile(
              key: const Key('wake-time'),
              leading: const Icon(Icons.alarm),
              title: Text('${twoDigits(d.hour)}:${twoDigits(d.minute)}'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Horário'),
                  if (next != null) Text(next, key: const Key('wake-next')),
                ],
              ),
              onTap: _pickTime,
            ),
            const SectionHeader('Dias'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final i in daysSundayFirst)
                  FilterChip(
                    key: ValueKey('day-$i'),
                    label: Text(weekdayShort[i - 1]),
                    selected: d.days.contains(i),
                    onSelected: (on) => _update((d) => d.copyWith(
                          days: on ? ([...d.days, i]..sort()) : d.days.where((x) => x != i).toList(),
                        )),
                  ),
              ],
            ),
            const SectionHeader('Echo'),
            if (echos.isEmpty)
              const EmptyHint('Nenhum Echo sincronizado. Toque em sincronizar na tela Casa.')
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in echos)
                    ChoiceChip(
                      key: ValueKey('echo-${e.id}'),
                      label: Text(e.name),
                      selected: d.echoDeviceId == e.id,
                      onSelected: (_) => _update((d) => d.copyWith(echoDeviceId: e.id)),
                    ),
                ],
              ),
            const SectionHeader('Música'),
            TextField(
              key: const Key('wake-spotify'),
              controller: _spotify,
              onChanged: (v) => setState(() {
                _dirty = true;
                // Sem busca não há música: "Encerrar" deixaria o despertar mudo.
                if (v.trim().isEmpty && _draft!.afterMusic == AfterMusic.end) {
                  _draft = _draft!.copyWith(afterMusic: AfterMusic.briefing);
                }
              }),
              decoration: const InputDecoration(
                labelText: 'Buscar no Spotify (opcional)',
                hintText: 'Ex.: playlist Bom Dia',
              ),
            ),
            SwitchListTile(
              title: const Text('Música antes do resumo'),
              value: d.musicFirst,
              onChanged: (v) => _update((d) => d.copyWith(musicFirst: v)),
            ),
            Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                key: const Key('wake-advanced'),
                controller: _advanced,
                initiallyExpanded: _advancedOpen,
                onExpansionChanged: (open) => _advancedOpen = open,
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                title: Text('Avançado', style: theme.textTheme.titleMedium),
                children: [
                  if (hasMusic) ...[
                    const SectionHeader('Parar a música após'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          key: const Key('music-stop-none'),
                          label: const Text('Não parar'),
                          selected: d.musicStopAfterSec == null,
                          onSelected: (_) => _update((d) => d.copyWith(clearMusicStop: true)),
                        ),
                        for (final o in _stopOptions)
                          ChoiceChip(
                            key: Key('music-stop-${o.sec}'),
                            label: Text(o.label),
                            selected: d.musicStopAfterSec == o.sec,
                            onSelected: (_) => _update((d) => d.copyWith(musicStopAfterSec: o.sec)),
                          ),
                      ],
                    ),
                  ],
                  if (d.musicFirst) ...[
                    const SectionHeader('Depois da música'),
                    SegmentedButton<AfterMusic>(
                      showSelectedIcon: false,
                      segments: [
                        for (final a in AfterMusic.values)
                          ButtonSegment(
                            value: a,
                            enabled: a != AfterMusic.end || hasMusic, // "Encerrar" só existe com música
                            label: Text(
                              a.label,
                              key: Key('after-music-${a.name}'),
                              textAlign: TextAlign.center,
                              softWrap: true,
                            ),
                          ),
                      ],
                      selected: {d.afterMusic},
                      onSelectionChanged: (s) => _update((d) => d.copyWith(afterMusic: s.first)),
                    ),
                    if (d.afterMusic == AfterMusic.end)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('Depois da música não haverá resumo falado.', key: Key('after-music-end-hint')),
                      ),
                    if (stopping)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('O resumo começa assim que a música parar.'),
                      )
                    else ...[
                      const SectionHeader('Falar o resumo após'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final o in _delayOptions)
                            ChoiceChip(
                              key: Key('briefing-delay-${o.sec}'),
                              label: Text(o.label),
                              selected: d.effectiveBriefingDelaySec == o.sec,
                              onSelected: (_) => _update((d) => d.copyWith(briefingDelaySec: o.sec)),
                            ),
                          if (!_delayOptions.any((o) => o.sec == d.effectiveBriefingDelaySec))
                            ChoiceChip(
                              key: const Key('briefing-delay-custom'),
                              label: Text('Personalizado (${_customDelayLabel(d.effectiveBriefingDelaySec)})'),
                              selected: true,
                              onSelected: (_) {},
                            ),
                        ],
                      ),
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('A música toca primeiro para você acordar de verdade.'),
                      ),
                    ],
                  ],
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Volume ${d.volume}%'),
                    subtitle: Slider(
                      value: d.volume.toDouble(),
                      max: 100,
                      divisions: 10,
                      onChanged: (v) => _update((d) => d.copyWith(volume: v.round())),
                    ),
                  ),
                  SwitchListTile(
                    key: const Key('wake-fallback'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Alarme reserva'),
                    subtitle: const Text('Se a ponte falhar, um alarme comum toca 10 minutos depois.'),
                    value: d.fallbackAlarm,
                    onChanged: (v) => _update((d) => d.copyWith(fallbackAlarm: v)),
                  ),
                  SwitchListTile(
                    key: const Key('weather-switch'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Falar o clima'),
                    subtitle: const Text('Temperatura, máxima, mínima e chance de chuva logo depois do cumprimento.'),
                    value: d.includeWeather,
                    onChanged: (v) => _update((d) => d.copyWith(includeWeather: v)),
                  ),
                  WakeDeviceActionsSection(
                    actions: d.deviceActions,
                    devices: ref.watch(alexaDevicesProvider).value ?? const <AlexaDevice>[],
                    hiddenIds: (ref.watch(settingsProvider).value ?? const UserSettings()).hiddenAlexaDevices.toSet(),
                    onChanged: (list) => _update((d) => d.copyWith(deviceActions: list)),
                  ),
                ],
              ),
            ),
            if (!_isNew) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  key: const Key('wake-test'),
                  onPressed: _dirty ? null : _test,
                  child: const Text('Testar agora'),
                ),
              ),
              if (_dirty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Salve para testar',
                    key: const Key('wake-test-hint'),
                    style: theme.textTheme.bodySmall?.copyWith(color: context.org.inkMuted),
                  ),
                ),
            ],
          ],
        ),
        bottomNavigationBar: Material(
          color: context.org.surfaceRaised,
          elevation: 3,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(mobile ? 16 : 24, 8, mobile ? 16 : 24, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(_error!, key: const Key('wake-error'), style: TextStyle(color: theme.colorScheme.error)),
                    ),
                  FilledButton(key: const Key('wake-save'), onPressed: _save, child: const Text('Salvar')),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}
