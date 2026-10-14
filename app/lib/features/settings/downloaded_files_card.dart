import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/drive.dart';
import '../../files/drive_file_opener.dart';
import '../../files/files_platform.dart';
import '../../ui/common.dart';
import '../../ui/org_theme.dart';
import '../../ui/org_widgets.dart';

final _downloadedBytesProvider = FutureProvider.autoDispose<int>((ref) => ref.watch(driveCacheProvider).totalBytes());

/// Ajustes > "Arquivos baixados": quanto espaço os arquivos do Drive abertos no aparelho ocupam e como limpar.
class DownloadedFilesCard extends ConsumerStatefulWidget {
  const DownloadedFilesCard({super.key});

  @override
  ConsumerState<DownloadedFilesCard> createState() => _DownloadedFilesCardState();
}

class _DownloadedFilesCardState extends ConsumerState<DownloadedFilesCard> {
  bool _busy = false;

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Limpar arquivos baixados?'),
        content: const Text(
          'As cópias do Drive guardadas neste aparelho serão apagadas. Os arquivos continuam no Drive; '
          'para abrir de novo será preciso baixar (e, sem internet, não abrem).',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(key: const Key('downloads-confirm-clear'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Limpar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(driveCacheProvider).clear();
    } catch (_) {
      if (mounted) showError(context, 'Não foi possível limpar os arquivos baixados.');
    } finally {
      ref.invalidate(_downloadedBytesProvider);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(filesPlatformProvider).supported) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final org = context.org;
    final bytes = ref.watch(_downloadedBytesProvider).value;
    final summary = bytes == null
        ? 'Calculando…'
        : bytes == 0
            ? 'Nenhum arquivo baixado'
            : '${formatBytes(bytes)} no aparelho';
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: OrgCard(
        key: const Key('downloads-card'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Arquivos baixados', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Os arquivos do Drive que você abre em Documentos ou nas notas ficam guardados aqui e abrem mesmo sem internet. '
              'Acima de 1 GB, os menos usados saem sozinhos.',
              style: theme.textTheme.bodySmall?.copyWith(color: org.inkMuted),
            ),
            const SizedBox(height: 12),
            Text(summary, key: const Key('downloads-size'), style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            OutlinedButton(
              key: const Key('downloads-clear'),
              onPressed: _busy || bytes == null || bytes == 0 ? null : _clear,
              child: const Text('Limpar'),
            ),
          ],
        ),
      ),
    );
  }
}
