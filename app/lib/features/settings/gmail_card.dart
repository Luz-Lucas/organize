import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/email_repository.dart';
import '../../domain/email.dart';
import '../../ui/org_theme.dart';
import '../../ui/org_widgets.dart';
import '../email/email_card.dart';

/// Ajustes > "E-mail (Gmail)": conectar (somente leitura) e desconectar.
class GmailCard extends ConsumerStatefulWidget {
  const GmailCard({super.key});

  @override
  ConsumerState<GmailCard> createState() => _GmailCardState();
}

class _GmailCardState extends ConsumerState<GmailCard> {
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
        final repo = ref.read(emailRepositoryProvider);
        final url = await repo.connectUrl(email: defaultGmailAccount);
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
        title: const Text('Desconectar o Gmail?'),
        content: const Text('O acesso é revogado e as mensagens guardadas no app são apagadas.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(key: const Key('gmail-confirm-disconnect'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Desconectar')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() => ref.read(emailRepositoryProvider).disconnect());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final org = context.org;
    final state = ref.watch(emailStateProvider).value;
    final status = state?.status ?? EmailStatus.notConnected;
    final now = ref.watch(clockProvider)();

    final String summary = switch (status) {
      EmailStatus.notConnected => 'Não conectado',
      EmailStatus.authRequired => 'Acesso expirado — reconecte',
      EmailStatus.error => 'Conectado, com falha na última sincronização',
      EmailStatus.ok => 'Conectado'
    };

    return OrgCard(
      key: const Key('gmail-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('E-mail (Gmail)', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Mostra não lidos e remetente/assunto na Início. Acesso somente leitura aos cabeçalhos: o app nunca lê o corpo nem os anexos.',
            style: theme.textTheme.bodySmall?.copyWith(color: org.inkMuted),
          ),
          const SizedBox(height: 12),
          Text(summary, key: const Key('gmail-status'), style: theme.textTheme.bodyMedium),
          if (state?.accountEmail != null) Text(state!.accountEmail!, style: theme.textTheme.bodySmall?.copyWith(color: org.inkMuted)),
          if (state?.lastSyncedAt != null && status == EmailStatus.ok)
            Text('Atualizado ${emailAgoLabel(state!.lastSyncedAt!, now)}', style: theme.textTheme.bodySmall?.copyWith(color: org.inkMuted)),
          if (_info != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_info!, key: const Key('gmail-info'), style: theme.textTheme.bodySmall)),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, key: const Key('gmail-error'), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (status == EmailStatus.notConnected || status == EmailStatus.authRequired)
                FilledButton(
                  key: const Key('gmail-connect'),
                  onPressed: _busy ? null : _connect,
                  child: Text(status == EmailStatus.authRequired ? 'Reconectar' : 'Conectar Gmail'),
                ),
              if (status != EmailStatus.notConnected)
                OutlinedButton(key: const Key('gmail-disconnect'), onPressed: _busy ? null : _disconnect, child: const Text('Desconectar')),
            ],
          ),
        ],
      ),
    );
  }
}
