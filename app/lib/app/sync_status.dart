import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sync/sync_engine.dart';
import '../ui/org_theme.dart';
import 'providers.dart';
import 'sync_providers.dart';

/// "1 alteração aguardando envio" / "N alterações aguardando envio".
String pendingNoticeText(int n) => n == 1 ? '1 alteração aguardando envio' : '$n alterações aguardando envio';

const offlineNoticeText = 'Sem conexão — as alterações ficam salvas no aparelho';

String rejectionText(SyncRejection r) => 'Não foi possível salvar: ${syncRejectionReason(r.message)}';

/// O que o ícone de status mostra (nada quando está tudo enviado).
enum SyncIssue { rejected, offline, pending }

final syncIssueProvider = Provider<SyncIssue?>((ref) {
  if (ref.watch(syncRejectionLogProvider).isNotEmpty) return SyncIssue.rejected;
  // `connectionProblemProvider` = stream com erro há mais de 4 s (queda das assinaturas ao vivo).
  if (ref.watch(offlineNoticeProvider) || ref.watch(connectionProblemProvider)) return SyncIssue.offline;
  if (ref.watch(pendingNoticeProvider) > 0) return SyncIssue.pending;
  return null;
});

/// Envolve o conteúdo da casca com um ícone pequeno e discreto no canto superior direito que só existe
/// quando há algo a dizer: alterações aguardando envio, sem conexão ou recusa do servidor. Não ocupa
/// espaço (fica sobre o conteúdo) e a estrutura é sempre a mesma: nada do que o usuário digitou se perde.
/// Tocar abre os detalhes e o botão "Tentar agora".
class SyncStatusHost extends ConsumerWidget {
  const SyncStatusHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final issue = ref.watch(syncIssueProvider);
    final pending = ref.watch(pendingNoticeProvider);
    return Stack(
      children: [
        Positioned.fill(child: child),
        if (issue != null)
          Positioned.fill(
            child: SafeArea(
              left: false,
              bottom: false,
              child: Align(
                alignment: Alignment.topRight,
                child: _StatusIcon(issue: issue, pending: pending),
              ),
            ),
          ),
      ],
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.issue, required this.pending});

  final SyncIssue issue;
  final int pending;

  @override
  Widget build(BuildContext context) {
    final org = context.org;
    final (icon, color, label) = switch (issue) {
      SyncIssue.rejected => (Icons.sync_problem, Theme.of(context).colorScheme.error, 'Não foi possível salvar uma alteração'),
      SyncIssue.offline => (Icons.cloud_off_outlined, org.inkMuted.withValues(alpha: 0.75), offlineNoticeText),
      SyncIssue.pending => (Icons.cloud_upload_outlined, org.inkMuted.withValues(alpha: 0.75), pendingNoticeText(pending)),
    };
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: InkResponse(
          key: const Key('sync-status-icon'),
          onTap: () => showSyncDetails(context),
          radius: 12,
          // Só o próprio ícone recebe o toque: nos cabeçalhos com botões à direita não rouba o toque deles.
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}

/// Bottom sheet com o detalhe do que está pendente e o botão "Tentar agora".
Future<void> showSyncDetails(BuildContext context) {
  final container = ProviderScope.containerOf(context);
  final rejections = container.read(syncRejectionLogProvider);
  // Já foram vistas: o ícone de erro some (se nada mais estiver errado).
  container.read(syncRejectionLogProvider.notifier).clear();
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => UncontrolledProviderScope(
      container: container,
      child: _SyncDetails(rejections: rejections),
    ),
  );
}

class _SyncDetails extends ConsumerStatefulWidget {
  const _SyncDetails({required this.rejections});

  final List<SyncRejection> rejections;

  @override
  ConsumerState<_SyncDetails> createState() => _SyncDetailsState();
}

class _SyncDetailsState extends ConsumerState<_SyncDetails> {
  bool _trying = false;

  Future<void> _retry() async {
    final engine = ref.read(syncEngineProvider);
    if (engine == null) return;
    setState(() => _trying = true);
    try {
      await engine.refresh();
    } finally {
      if (mounted) setState(() => _trying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pending = ref.watch(pendingNoticeProvider);
    final offline = ref.watch(offlineNoticeProvider) || ref.watch(connectionProblemProvider);
    final lines = <(IconData, String, Color?)>[
      for (final r in widget.rejections.take(5)) (Icons.sync_problem, rejectionText(r), theme.colorScheme.error),
      if (widget.rejections.length > 5) (Icons.sync_problem, 'e mais ${widget.rejections.length - 5}', theme.colorScheme.error),
      if (offline) (Icons.cloud_off_outlined, offlineNoticeText, null),
      if (pending > 0) (Icons.cloud_upload_outlined, pendingNoticeText(pending), null),
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (lines.isEmpty)
              Row(children: [
                const Icon(Icons.cloud_done_outlined, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text('Tudo salvo e enviado.', style: theme.textTheme.bodyLarge)),
              ])
            else
              for (final (icon, text, color) in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    Icon(icon, size: 20, color: color),
                    const SizedBox(width: 12),
                    Expanded(child: Text(text, style: theme.textTheme.bodyLarge?.copyWith(color: color))),
                  ]),
                ),
            if (ref.watch(syncEngineProvider) != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  key: const Key('sync-retry'),
                  onPressed: _trying ? null : _retry,
                  child: Text(_trying ? 'Tentando…' : 'Tentar agora'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
