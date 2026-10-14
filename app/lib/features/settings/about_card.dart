import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/org_theme.dart';
import '../../ui/org_widgets.dart';
import '../../update/update_banner.dart' show UpdateActions;
import '../../update/update_controller.dart';
import '../../update/update_providers.dart';

/// Ajustes > Sobre: versão instalada, "Procurar atualização" e as novidades.
class AboutCard extends ConsumerWidget {
  const AboutCard({super.key = const Key('about-card')});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(updateControllerProvider);
    final ctl = ref.read(updateControllerProvider.notifier);
    final installed = ref.watch(installedVersionProvider).value;
    final supported = ref.watch(updateInstallerProvider).supported;
    final theme = Theme.of(context);
    final org = context.org;
    final release = s.release;
    final available = s.phase == UpdatePhase.available ||
        s.phase == UpdatePhase.downloading ||
        s.phase == UpdatePhase.installing ||
        s.phase == UpdatePhase.needsPermission ||
        s.phase == UpdatePhase.error;
    final notes = release?.notes.trim() ?? '';
    return OrgCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: org.inkMuted),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  installed == null ? 'Organize' : 'Organize ${installed.label} (build ${installed.build})',
                  style: theme.textTheme.bodyLarge,
                ),
              ),
              if (supported)
                OutlinedButton.icon(
                  key: const Key('check-update'),
                  onPressed: s.busy ? null : () => ctl.check(manual: true),
                  icon: s.phase == UpdatePhase.checking
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh, size: 18),
                  label: const Text('Procurar atualização'),
                ),
            ],
          ),
          if (available && release != null) ...[
            const SizedBox(height: 12),
            Text('Atualização ${release.version} disponível',
                style: theme.textTheme.titleSmall?.copyWith(color: org.accentText)),
          ] else if (release != null && notes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('Novidades da versão ${release.version}', style: theme.textTheme.titleSmall),
            ),
          if (release != null && notes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(notes, style: theme.textTheme.bodyMedium),
            ),
          if (s.message != null && s.phase != UpdatePhase.downloading)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                s.message!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: s.phase == UpdatePhase.error ? theme.colorScheme.error : org.inkMuted,
                ),
              ),
            ),
          if (available && release != null) ...[
            const SizedBox(height: 8),
            UpdateActions(state: s, controller: ctl),
          ],
        ],
      ),
    );
  }
}
