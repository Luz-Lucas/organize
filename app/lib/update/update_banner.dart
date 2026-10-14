import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui/org_theme.dart';
import 'update_controller.dart';

/// Envolve o conteúdo do shell: dispara a checagem ao abrir o app (no máximo 1 vez a cada 24 h), retoma a
/// instalação quando o usuário volta dos ajustes de permissão e mostra o [UpdateBanner] acima das telas.
class UpdateBannerHost extends ConsumerStatefulWidget {
  const UpdateBannerHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UpdateBannerHost> createState() => _UpdateBannerHostState();
}

class _UpdateBannerHostState extends ConsumerState<UpdateBannerHost> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(updateControllerProvider.notifier).checkIfDue();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Voltou dos ajustes de "apps desconhecidos": tenta instalar de novo, sem reabrir os ajustes.
    if (state == AppLifecycleState.resumed) ref.read(updateControllerProvider.notifier).retryInstall();
  }

  @override
  Widget build(BuildContext context) {
    final show = ref.watch(updateControllerProvider.select((s) => s.showBanner));
    // Estrutura sempre igual (faixa + conteúdo): ligar/desligar o banner não recria as telas.
    return Column(
      children: [
        if (show) SafeArea(bottom: false, child: const UpdateBanner()) else const SizedBox.shrink(),
        Expanded(
          // Com o banner no topo, ele já consumiu a área do recorte/barra de status.
          child: MediaQuery.removePadding(context: context, removeTop: show, child: widget.child),
        ),
      ],
    );
  }
}

/// Aviso discreto "Atualização X disponível" com as novidades e os botões Atualizar / Depois.
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key = const Key('update-banner')});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(updateControllerProvider);
    final release = s.release;
    if (release == null) return const SizedBox.shrink();
    final ctl = ref.read(updateControllerProvider.notifier);
    final org = context.org;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Material(
        color: org.accentSoft,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(org.radiusMd),
          side: BorderSide(color: org.line),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.system_update_alt, size: 18, color: org.accentText),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Atualização ${release.version} disponível',
                      style: theme.textTheme.titleSmall?.copyWith(color: org.accentText),
                    ),
                  ),
                ],
              ),
              if (release.notes.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(release.notes.trim(),
                      maxLines: 3, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                ),
              if (s.message != null && s.phase != UpdatePhase.downloading)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    s.message!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: s.phase == UpdatePhase.error ? theme.colorScheme.error : org.ink,
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              UpdateActions(state: s, controller: ctl, banner: true),
            ],
          ),
        ),
      ),
    );
  }
}

/// Botões/progresso conforme a fase. [banner] usa "Depois"/"Fechar"; o Ajustes usa só "Atualizar".
class UpdateActions extends StatelessWidget {
  const UpdateActions({super.key, required this.state, required this.controller, this.banner = false});

  final UpdateState state;
  final UpdateController controller;
  final bool banner;

  @override
  Widget build(BuildContext context) {
    switch (state.phase) {
      case UpdatePhase.downloading:
        final p = state.progress;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(value: p),
            Row(
              children: [
                Expanded(
                  child: Text(p == null ? 'Baixando…' : 'Baixando… ${(p * 100).round()}%',
                      style: Theme.of(context).textTheme.bodySmall),
                ),
                TextButton(
                  key: const Key('update-cancel'),
                  onPressed: controller.cancelDownload,
                  child: const Text('Cancelar'),
                ),
              ],
            ),
          ],
        );
      case UpdatePhase.installing:
        return const Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: LinearProgressIndicator(),
        );
      case UpdatePhase.needsPermission:
        return Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            key: const Key('update-retry'),
            onPressed: () => controller.retryInstall(prompt: true),
            child: const Text('Tentar de novo'),
          ),
        );
      case UpdatePhase.error:
        return Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          children: [
            TextButton(
              key: const Key('update-close'),
              onPressed: controller.acknowledgeError,
              child: const Text('Fechar'),
            ),
            FilledButton(
              key: const Key('update-retry'),
              onPressed: controller.startUpdate,
              child: const Text('Tentar de novo'),
            ),
          ],
        );
      default:
        return Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          children: [
            if (banner)
              TextButton(
                key: const Key('update-later'),
                onPressed: controller.dismiss,
                child: const Text('Depois'),
              ),
            FilledButton(
              key: Key(banner ? 'update-install' : 'about-update'),
              onPressed: controller.startUpdate,
              child: const Text('Atualizar'),
            ),
          ],
        );
    }
  }
}
