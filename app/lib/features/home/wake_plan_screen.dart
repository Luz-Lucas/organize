import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/alexa_repository.dart';
import '../../data/repository.dart';
import '../../domain/alexa.dart';
import '../../domain/ids.dart';
import '../../ui/common.dart';

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
      echoDeviceId: echos.where((e) => e.online).firstOrNull?.id ?? echos.firstOrNull?.id ?? '',
    );
  }

  void _update(WakePlan Function(WakePlan d) change) => setState(() {
        _draft = change(_draft!);
        _dirty = true;
      });

  Future<void> _pickTime() async {
    final d = _draft!;
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay(hour: d.hour, minute: d.minute));
    if (!mounted) return;
    if (picked != null) _update((d) => d.copyWith(hour: picked.hour, minute: picked.minute));
  }

  Future<void> _save() async {
    final plan = _draft!.copyWith(label: _label.text.trim(), spotifyQuery: _spotify.text.trim());
    final problem = validateWakePlan(plan);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    try {
      await ref.read(alexaRepositoryProvider).upsertWakePlan(plan);
      if (mounted) context.go('/casa');
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
      if (mounted) context.go('/casa');
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
      }
      if (_draft!.echoDeviceId.isEmpty && echos.isNotEmpty) {
        _draft = _draft!.copyWith(echoDeviceId: echos.first.id); // dispositivos chegaram depois dos planos
      }
      final d = _draft!;
      final theme = Theme.of(context);
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
              onChanged: (_) => setState(() => _dirty = true),
              decoration: const InputDecoration(labelText: 'Nome'),
            ),
            ListTile(
              key: const Key('wake-time'),
              leading: const Icon(Icons.alarm),
              title: Text('${twoDigits(d.hour)}:${twoDigits(d.minute)}'),
              subtitle: const Text('Horário'),
              onTap: _pickTime,
            ),
            const SectionHeader('Dias'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 1; i <= 7; i++)
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
              onChanged: (_) => setState(() => _dirty = true),
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
            if (d.musicFirst)
              Wrap(
                spacing: 8,
                children: [
                  for (final m in const [1, 3, 5])
                    ChoiceChip(
                      label: Text('Resumo após $m min'),
                      selected: d.briefingDelayMin == m,
                      onSelected: (_) => _update((d) => d.copyWith(briefingDelayMin: m)),
                    ),
                ],
              ),
            ListTile(
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
              title: const Text('Alarme reserva'),
              subtitle: const Text('Se a ponte falhar, um alarme comum toca 10 minutos depois.'),
              value: d.fallbackAlarm,
              onChanged: (v) => _update((d) => d.copyWith(fallbackAlarm: v)),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, key: const Key('wake-error'), style: TextStyle(color: theme.colorScheme.error)),
              ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              children: [
                FilledButton(key: const Key('wake-save'), onPressed: _save, child: const Text('Salvar')),
                if (!_isNew)
                  OutlinedButton(key: const Key('wake-test'), onPressed: _dirty ? null : _test, child: const Text('Testar agora')),
              ],
            ),
          ],
        ),
      );
    });
  }
}
