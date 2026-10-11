import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/location_repository.dart';
import '../../data/repository.dart';
import '../../data/settings_repository.dart';
import '../../domain/home_presence.dart';
import '../../domain/user_settings.dart';
import '../../location/location_service.dart';
import '../../ui/org_theme.dart';
import '../../ui/org_widgets.dart';

/// Precisão do GPS acima da qual avisamos que o sinal está fraco.
const weakAccuracyM = 30;

/// Texto da situação atual em relação à casa.
String homeStatusText(PresenceStatus status) => switch (status.state) {
      PresenceState.home => 'Em casa',
      PresenceState.away => 'Fora (a ${formatDistance(status.distanceM ?? 0)})',
      PresenceState.unknown when status.distanceM != null =>
        'Posição incerta (a ${formatDistance(status.distanceM!)})',
      _ => 'Sem localização recente',
    };

/// Ajustes > "Minha casa": define o ponto da casa e a regra de presença do despertar.
class HomeLocationCard extends ConsumerStatefulWidget {
  const HomeLocationCard({super.key});

  @override
  ConsumerState<HomeLocationCard> createState() => _HomeLocationCardState();
}

class _HomeLocationCardState extends ConsumerState<HomeLocationCard> {
  bool _busy = false;
  String? _error;
  bool _permissionBlocked = false;
  LocationPermissionLevel? _level;

  @override
  void initState() {
    super.initState();
    _refreshLevel();
  }

  Future<void> _refreshLevel() async {
    try {
      final level = await ref.read(locationServiceProvider).permission();
      if (mounted) setState(() => _level = level);
    } catch (_) {
      // Sem leitura da permissão: apenas não mostramos o lembrete.
    }
  }

  void _fail(String message, {bool blocked = false}) => setState(() {
        _error = message;
        _permissionBlocked = blocked;
      });

  void _startBusy() => setState(() {
        _busy = true;
        _error = null;
        _permissionBlocked = false;
      });

  /// Garante a permissão com o app em uso; devolve o nível final ou null (erro já mostrado).
  Future<LocationPermissionLevel?> _ensureForeground(LocationService svc) async {
    var level = await svc.permission();
    if (level == LocationPermissionLevel.denied) level = await svc.requestPermission();
    if (!mounted) return null;
    switch (level) {
      case LocationPermissionLevel.whileInUse:
      case LocationPermissionLevel.always:
        return level;
      case LocationPermissionLevel.deniedForever:
        _fail('A permissão de localização está bloqueada.', blocked: true);
      case LocationPermissionLevel.serviceDisabled:
        _fail('O GPS está desligado. Ligue a localização do aparelho e tente de novo.');
      case LocationPermissionLevel.denied:
        _fail('Sem a permissão de localização não dá para definir a casa.');
    }
    return null;
  }

  Future<bool> _confirmFix(GeoFix fix, {required bool reset}) async {
    final acc = fix.accuracyM;
    final weak = acc != null && acc > weakAccuracyM;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(reset ? 'Redefinir a casa aqui?' : 'Definir a casa aqui?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Vamos usar a sua posição de agora como o centro da casa. Fique dentro de casa ao confirmar.'),
            const SizedBox(height: 12),
            Text(
              acc == null ? 'Precisão do GPS: desconhecida' : 'Precisão do GPS: cerca de ${acc.round()} m',
              key: const Key('home-accuracy'),
            ),
            if (weak)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Sinal fraco; tente perto de uma janela.',
                  key: const Key('home-weak-signal'),
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            key: const Key('home-cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('home-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(weak ? 'Definir mesmo assim' : 'Definir aqui'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _define({required bool reset}) async {
    if (_busy) return;
    _startBusy();
    try {
      final svc = ref.read(locationServiceProvider);
      final level = await _ensureForeground(svc);
      if (level == null || !mounted) return;
      final fix = await svc.currentFix();
      if (!mounted) return;
      if (fix == null) {
        _fail('Não foi possível obter a sua localização. Tente perto de uma janela.');
        return;
      }
      if (!await _confirmFix(fix, reset: reset) || !mounted) return;
      await ref.read(settingsRepositoryProvider).setHome(fix.lat, fix.lon);
      if (!mounted) return;
      setState(() => _level = level);
      if (level != LocationPermissionLevel.always) await _askBackground(svc);
    } on RepositoryException {
      if (mounted) _fail('Não foi possível salvar a casa.');
    } catch (_) {
      if (mounted) _fail('Não foi possível obter a sua localização.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Segundo passo: explica e pede "permitir o tempo todo" (o Android exige à parte).
  Future<void> _askBackground(LocationService svc) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Permitir o tempo todo'),
        content: const Text(
          'Para saber se você está em casa na hora do despertar, o app precisa atualizar a sua '
          'localização mesmo fechado. Na próxima tela, escolha "Permitir o tempo todo".',
        ),
        actions: [
          TextButton(
            key: const Key('home-bg-skip'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Agora não'),
          ),
          FilledButton(
            key: const Key('home-bg-continue'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    final level = await svc.requestPermission(background: true);
    if (!mounted) return;
    setState(() {
      _level = level;
      if (level == LocationPermissionLevel.deniedForever) {
        _error = 'A permissão "o tempo todo" está bloqueada.';
        _permissionBlocked = true;
      }
    });
  }

  Future<void> _requestBackgroundOnly() async {
    if (_busy) return;
    _startBusy();
    try {
      final svc = ref.read(locationServiceProvider);
      final level = await _ensureForeground(svc);
      if (level == null || !mounted) return;
      if (level != LocationPermissionLevel.always) await _askBackground(svc);
    } catch (_) {
      if (mounted) _fail('Não foi possível pedir a permissão.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _guarded(Future<void> Function() op, String failure) async {
    setState(() => _error = null);
    try {
      await op();
    } on RepositoryException {
      if (mounted) _fail(failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).value ?? const UserSettings();
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: context.org.inkMuted);
    final repo = ref.read(settingsRepositoryProvider);
    return OrgCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.home_outlined, color: context.org.inkMuted),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  settings.hasHome ? 'Casa definida · raio ${settings.homeRadiusM} m' : 'Casa não definida',
                  key: const Key('home-summary'),
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (settings.hasHome) ..._definedChildren(settings, repo, muted) else ..._undefinedChildren(muted),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, key: const Key('home-error'), style: TextStyle(color: theme.colorScheme.error)),
          ],
          if (_permissionBlocked)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Para liberar: abra os Ajustes do Android, entre em Apps > Organizacional > Permissões > '
                'Localização e escolha "Permitir o tempo todo" (ou, no mínimo, "Permitir só com o app em uso"). '
                'Depois volte aqui e tente de novo.',
                key: const Key('home-permission-help'),
                style: muted,
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'Para saber se você está em casa, o app envia a sua localização ao servidor quando você o abre '
            'e, com a permissão "o tempo todo", a cada cerca de 15 minutos em segundo plano. Isso usa um '
            'pouco de bateria. Só você acessa esse dado.',
            key: const Key('home-privacy-note'),
            style: muted,
          ),
        ],
      ),
    );
  }

  List<Widget> _undefinedChildren(TextStyle? muted) => [
        Text(
          'Defina a sua casa para o despertar tocar só quando você estiver nela. '
          'Faça isso estando dentro de casa.',
          style: muted,
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          key: const Key('home-set'),
          onPressed: _busy ? null : () => _define(reset: false),
          icon: const Icon(Icons.my_location, size: 18),
          label: const Text('Definir minha casa aqui'),
        ),
      ];

  List<Widget> _definedChildren(UserSettings settings, SettingsRepository repo, TextStyle? muted) {
    final last = ref.watch(lastLocationProvider).value;
    final status = presenceStatus(
      home: settings.home,
      radiusM: settings.homeRadiusM,
      requireHome: true, // a situação aparece mesmo com a chave desligada
      last: last,
      now: ref.watch(clockProvider)(),
    );
    final needsBackground = _level != null && _level != LocationPermissionLevel.always;
    return [
      Text(homeStatusText(status), key: const Key('home-status')),
      SwitchListTile(
        key: const Key('home-require-switch'),
        contentPadding: EdgeInsets.zero,
        title: const Text('Só tocar o despertar quando eu estiver em casa'),
        subtitle: const Text('Sem localização recente, o despertar toca mesmo assim.'),
        value: settings.requireHome,
        onChanged: (v) => _guarded(() => repo.setRequireHome(v), 'Não foi possível salvar.'),
      ),
      if (needsBackground)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Sem a permissão "o tempo todo", sua posição só é atualizada com o app aberto.',
                  key: const Key('home-background-note'),
                  style: muted,
                ),
              ),
              TextButton(
                key: const Key('home-background'),
                onPressed: _busy ? null : _requestBackgroundOnly,
                child: const Text('Permitir'),
              ),
            ],
          ),
        ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            key: const Key('home-reset'),
            onPressed: _busy ? null : () => _define(reset: true),
            icon: const Icon(Icons.my_location, size: 18),
            label: const Text('Redefinir aqui'),
          ),
          TextButton.icon(
            key: const Key('home-remove'),
            onPressed: _busy ? null : () => _guarded(repo.clearHome, 'Não foi possível remover a casa.'),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Remover casa'),
          ),
        ],
      ),
    ];
  }
}
