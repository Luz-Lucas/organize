import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/drive_repository.dart';
import '../../domain/drive.dart';
import '../../ui/org_theme.dart';
import '../../ui/org_widgets.dart';

/// Texto de ajuda para quem usa o Samsung Notes (não há API; o caminho é compartilhar).
const samsungNotesHelp =
    'No Samsung Notes: abra a nota → Compartilhar → Organizacional (texto) ou salve como Arquivo do Samsung Notes (.sdocx) '
    'para editar em outro aparelho (PDF, para só visualizar) e compartilhe.';

/// Ajustes > "Google Drive": conectar e desconectar (Documentos e arquivos importados).
class DriveCard extends ConsumerStatefulWidget {
  const DriveCard({super.key});

  @override
  ConsumerState<DriveCard> createState() => _DriveCardState();
}

class _DriveCardState extends ConsumerState<DriveCard> {
  bool _busy = false;
  String? _error;
  String? _info;

  Future<void> _run(Future<void> Function() op) async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await op();
    } catch (e) {
      if (mounted) setState(() => _error = 'Não foi possível concluir. Tente de novo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() => _run(() async {
        final url = await ref.read(driveRepositoryProvider).connectUrl(email: defaultDriveAccount);
        final opened = await ref.read(linkOpenerProvider)(url);
        if (!mounted) return;
        setState(() {
          if (opened) {
            _info = 'Conclua a permissão no navegador e volte ao app.';
          } else {
            _error = 'Não consegui abrir o navegador.';
          }
        });
      });

  Future<void> _disconnect() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desconectar o Google Drive?'),
        content: const Text('O acesso é revogado. Seus arquivos continuam no Drive; só deixam de aparecer em Documentos.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(key: const Key('drive-confirm-disconnect'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Desconectar')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() => ref.read(driveRepositoryProvider).disconnect());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final org = context.org;
    final state = ref.watch(driveStateProvider).value;
    final status = state?.status ?? DriveStatus.notConnected;

    final String summary = switch (status) {
      DriveStatus.notConnected => 'Não conectado',
      DriveStatus.authRequired => 'Acesso expirado — reconecte',
      DriveStatus.error => 'Conectado, com falha na última operação',
      DriveStatus.ok => 'Conectado',
    };

    return OrgCard(
      key: const Key('drive-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Google Drive', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Mostra suas pastas em Mais > Documentos e guarda os arquivos que você compartilha com o app '
            '(em "Organizacional/Importados"). O app pode ver e organizar o seu Drive inteiro; o acesso fica só no servidor.',
            style: theme.textTheme.bodySmall?.copyWith(color: org.inkMuted),
          ),
          const SizedBox(height: 8),
          Text(samsungNotesHelp, key: const Key('drive-samsung-help'), style: theme.textTheme.bodySmall?.copyWith(color: org.inkMuted)),
          const SizedBox(height: 12),
          Text(summary, key: const Key('drive-status'), style: theme.textTheme.bodyMedium),
          if (state?.accountEmail != null) Text(state!.accountEmail!, style: theme.textTheme.bodySmall?.copyWith(color: org.inkMuted)),
          if (_info != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_info!, key: const Key('drive-info'), style: theme.textTheme.bodySmall)),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, key: const Key('drive-error'), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (status == DriveStatus.notConnected || status == DriveStatus.authRequired)
                FilledButton(
                  key: const Key('drive-connect'),
                  onPressed: _busy ? null : _connect,
                  child: Text(status == DriveStatus.authRequired ? 'Reconectar' : 'Conectar Google Drive'),
                ),
              if (status == DriveStatus.ok)
                FilledButton.tonal(
                  key: const Key('drive-open-docs'),
                  onPressed: () => context.push('/documentos'),
                  child: const Text('Abrir Documentos'),
                ),
              if (status != DriveStatus.notConnected)
                OutlinedButton(key: const Key('drive-disconnect'), onPressed: _busy ? null : _disconnect, child: const Text('Desconectar')),
            ],
          ),
        ],
      ),
    );
  }
}
