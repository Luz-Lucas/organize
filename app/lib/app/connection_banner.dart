import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// Texto do aviso global de conexão.
const connectionNoticeText = 'Sem conexão com o servidor. Tentando de novo…';

/// Envolve o conteúdo do shell com o aviso único de conexão. A estrutura é
/// sempre a mesma (faixa animada + conteúdo): mostrar/esconder o aviso não
/// recria as telas, então nada do que o usuário digitou ou escolheu se perde.
class ConnectionBannerHost extends ConsumerWidget {
  const ConnectionBannerHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final show = ref.watch(connectionProblemProvider);
    return Column(
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: show ? const _ConnectionNotice() : const SizedBox(width: double.infinity),
        ),
        // Com a faixa no topo, ela já consumiu a área do recorte/barra de status.
        Expanded(child: MediaQuery.removePadding(context: context, removeTop: show, child: child)),
      ],
    );
  }
}

class _ConnectionNotice extends StatelessWidget {
  const _ConnectionNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      key: const Key('connection-notice'),
      color: theme.colorScheme.errorContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.cloud_off_outlined, size: 18, color: theme.colorScheme.onErrorContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  connectionNoticeText,
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
