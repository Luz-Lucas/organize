import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/drive_repository.dart';
import '../../domain/drive.dart';
import '../../domain/github.dart' show issueAgoLabel;
import '../../ui/org_theme.dart';
import '../../ui/org_widgets.dart';
import '../samsung_notes/samsung_folder.dart';
import '../samsung_notes/samsung_sync_controller.dart';

/// Como exportar uma nota do Samsung Notes para um arquivo (o app não tem API; o caminho é este).
/// O formato do meio aparece em negrito.
const samsungExportHelpBefore = 'No Samsung Notes: abra a nota → ⋮ → Salvar como arquivo. Para editar em outro aparelho, salve como ';
const samsungExportHelpBold = 'Arquivo do Samsung Notes (.sdocx)';
const samsungExportHelpAfter = '; para só visualizar, PDF.';
const samsungExportHelp = '$samsungExportHelpBefore$samsungExportHelpBold$samsungExportHelpAfter';

/// Ajustes > "Samsung Notes": acha a pasta onde o Samsung Notes salva os arquivos e os sincroniza com o
/// Google Drive (Organizacional/Samsung Notes), criando uma nota-link para cada um.
class SamsungNotesCard extends ConsumerStatefulWidget {
  const SamsungNotesCard({super.key});

  @override
  ConsumerState<SamsungNotesCard> createState() => _SamsungNotesCardState();
}

class _SamsungNotesCardState extends ConsumerState<SamsungNotesCard> {
  bool _driveBusy = false;

  bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  SamsungSyncController get _controller => ref.read(samsungSyncControllerProvider.notifier);

  Future<void> _find() async {
    final c = _controller;
    if (!await c.hasAllFilesAccess()) {
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          key: const Key('samsung-allfiles-dialog'),
          title: const Text('Acesso a todos os arquivos'),
          content: const Text(
            'Para achar sozinho a pasta onde o Samsung Notes salva os arquivos (e ler o que cair nela mesmo com o app '
            'fechado), o Android exige a permissão "Acesso a todos os arquivos". O app só lê essa pasta e nunca apaga nada. '
            'Na próxima tela, ative a chave do Organizacional e volte.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Agora não')),
            FilledButton(key: const Key('samsung-allfiles-continue'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Continuar')),
          ],
        ),
      );
      if (ok == true) {
        await c.requestAllFilesAccess();
        c.setMessage('Depois de conceder o acesso, volte aqui e toque em "Procurar pasta" de novo.');
      }
      return;
    }
    final found = await c.findCandidates();
    if (!mounted) return;
    if (found.isEmpty) {
      c.setMessage('Não achei a pasta do Samsung Notes. Toque em "Escolher outra pasta" e aponte onde ficam os arquivos exportados.');
      return;
    }
    // Prefere uma pasta específica do Samsung Notes; "Download" (geral) só com confirmação.
    final path = found.firstWhere((p) => !folderNeedsConfirmation(p), orElse: () => found.first);
    if (folderNeedsConfirmation(path)) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          key: const Key('samsung-confirm-download'),
          title: const Text('Usar a pasta Download?'),
          content: const Text(
            'Não achei uma pasta própria do Samsung Notes. A pasta Download tem arquivos de vários apps, e os PDFs, '
            'documentos e imagens dela seriam enviados ao seu Drive. Usar mesmo assim?',
          ),
          actions: [
            TextButton(key: const Key('samsung-confirm-no'), onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(key: const Key('samsung-confirm-yes'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Usar Download')),
          ],
        ),
      );
      if (ok != true) return;
    }
    await c.useFolder(SamsungFolder(path: path));
  }

  Future<void> _pick() async {
    final folder = await _controller.pickFolder();
    if (folder != null) await _controller.useFolder(folder);
  }

  Future<void> _connectDrive() async {
    setState(() => _driveBusy = true);
    try {
      final url = await ref.read(driveRepositoryProvider).connectUrl(email: defaultDriveAccount);
      final opened = await ref.read(linkOpenerProvider)(url);
      _controller.setMessage(opened ? 'Conclua a permissão no navegador e volte ao app.' : 'Não consegui abrir o navegador.');
    } catch (_) {
      _controller.setMessage('Não foi possível conectar. Tente de novo.');
    } finally {
      if (mounted) setState(() => _driveBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final org = context.org;
    final ui = ref.watch(samsungSyncControllerProvider);
    final driveState = ref.watch(driveStateProvider).value;
    final driveOk = driveState?.status == DriveStatus.ok && (driveState?.rootFolderId ?? '').isNotEmpty;
    final folder = ui.settings.folder;
    final lastRun = ui.settings.lastRun;
    final canSync = folder != null && driveOk;
    final now = ref.watch(clockProvider)();
    final muted = theme.textTheme.bodySmall?.copyWith(color: org.inkMuted);

    return OrgCard(
      key: const Key('samsung-notes-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Samsung Notes', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Acha a pasta onde o Samsung Notes salva os arquivos e envia tudo ao Google Drive '
            '(Organizacional/Samsung Notes), criando uma nota com o link de cada arquivo. '
            'Vale para o celular e para o tablet: o mesmo arquivo só sobe uma vez.',
            style: muted,
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              style: muted,
              children: const [
                TextSpan(text: samsungExportHelpBefore),
                TextSpan(text: samsungExportHelpBold, style: TextStyle(fontWeight: FontWeight.bold)),
                TextSpan(text: samsungExportHelpAfter),
              ],
            ),
            key: const Key('samsung-help'),
          ),
          const SizedBox(height: 12),
          Text(
            folder == null ? 'Nenhuma pasta escolhida' : 'Pasta: ${folder.label}',
            key: const Key('samsung-folder-status'),
            style: theme.textTheme.bodyMedium,
          ),
          if (lastRun != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Última sincronização ${issueAgoLabel(lastRun.at, now)} — ${lastRun.text}',
                key: const Key('samsung-last-sync'),
                style: muted,
              ),
            ),
          if (lastRun?.message != null && ui.message == null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(lastRun!.message!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
            ),
          if (ui.message != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(ui.message!, key: const Key('samsung-message'), style: theme.textTheme.bodySmall),
            ),
          if (!driveOk)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Conecte o Google Drive para sincronizar.',
                    key: const Key('samsung-drive-missing'),
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    key: const Key('samsung-connect-drive'),
                    onPressed: _driveBusy ? null : _connectDrive,
                    child: Text(driveState?.status == DriveStatus.authRequired ? 'Reconectar Google Drive' : 'Conectar Google Drive'),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: Text('Sincronizar automaticamente', style: theme.textTheme.bodyMedium)),
              Switch(
                key: const Key('samsung-sync-toggle'),
                value: ui.settings.enabled,
                onChanged: canSync ? (v) => _controller.setEnabled(v) : null,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_isAndroid)
                FilledButton.tonal(key: const Key('samsung-find-folder'), onPressed: ui.syncing ? null : _find, child: const Text('Procurar pasta')),
              OutlinedButton(key: const Key('samsung-pick-folder'), onPressed: ui.syncing ? null : _pick, child: const Text('Escolher outra pasta')),
              OutlinedButton(
                key: const Key('samsung-sync-now'),
                onPressed: canSync && !ui.syncing ? () => _controller.sync(force: true) : null,
                child: ui.syncing
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Sincronizar agora'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
