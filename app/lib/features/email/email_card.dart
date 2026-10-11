import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/email_repository.dart';
import '../../domain/email.dart';
import '../../ui/org_theme.dart';
import '../../ui/org_widgets.dart';

/// "há 5 min", "há 3 h", "ontem" ou "26 set" — horário curto de uma mensagem ou sincronização.
String emailAgoLabel(DateTime at, DateTime now) {
  final diff = now.difference(at);
  if (diff.inMinutes < 1) return 'agora';
  if (diff.inMinutes < 60) return 'há ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'há ${diff.inHours} h';
  if (diff.inDays < 2) return 'ontem';
  const months = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
  return '${at.day} ${months[at.month - 1]}';
}

/// Cartão "E-mail" do painel da Início: não lidos e últimas mensagens (só cabeçalhos).
class EmailCard extends ConsumerStatefulWidget {
  const EmailCard({super.key});

  @override
  ConsumerState<EmailCard> createState() => _EmailCardState();
}

class _EmailCardState extends ConsumerState<EmailCard> {
  bool _syncing = false;

  Future<void> _sync() async {
    setState(() => _syncing = true);
    try {
      await ref.read(emailRepositoryProvider).syncNow();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível atualizar o e-mail.')));
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final org = context.org;
    final state = ref.watch(emailStateProvider).value;
    final items = ref.watch(emailItemsProvider).value ?? const <EmailItem>[];
    final now = ref.watch(clockProvider)();
    final status = state?.status ?? EmailStatus.notConnected;

    Widget body;
    if (status == EmailStatus.notConnected) {
      body = _Invite(
        text: 'Conecte seu Gmail em Ajustes para ver as notificações aqui',
        button: 'Abrir Ajustes',
        buttonKey: const Key('email-open-settings'),
      );
    } else if (status == EmailStatus.authRequired) {
      body = _Invite(
        text: 'O acesso ao Gmail expirou. Reconecte em Ajustes.',
        button: 'Reconectar',
        buttonKey: const Key('email-reconnect'),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (status == EmailStatus.error)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Não foi possível sincronizar agora. Mostrando o último estado.',
                key: const Key('email-error'),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
              ),
            ),
          if (items.isEmpty)
            Text('Nenhuma mensagem recente', style: theme.textTheme.bodyMedium?.copyWith(color: org.inkMuted))
          else
            for (final m in items) _EmailRow(item: m, now: now),
        ],
      );
    }

    final unread = state?.unreadCount ?? 0;
    return OrgCard(
      key: const Key('email-card'),
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              children: [
                Icon(Icons.mail_outline, size: 20, color: org.accentText),
                const SizedBox(width: 12),
                Expanded(child: Text('E-mail', style: theme.textTheme.titleMedium)),
                if (status == EmailStatus.ok || status == EmailStatus.error) ...[
                  if (unread > 0)
                    Container(
                      key: const Key('email-unread'),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: org.accent, borderRadius: BorderRadius.circular(12)),
                      child: Text(
                        unread > 99 ? '99+ não lidos' : '$unread não ${unread == 1 ? 'lido' : 'lidos'}',
                        style: theme.textTheme.labelMedium?.copyWith(color: org.onAccent),
                      ),
                    ),
                  IconButton(
                    key: const Key('email-refresh'),
                    tooltip: 'Atualizar e-mail',
                    onPressed: _syncing ? null : _sync,
                    icon: _syncing
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh),
                  ),
                ],
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.only(right: 8), child: body),
        ],
      ),
    );
  }
}

class _Invite extends StatelessWidget {
  const _Invite({required this.text, required this.button, required this.buttonKey});

  final String text;
  final String button;
  final Key buttonKey;

  @override
  Widget build(BuildContext context) {
    final org = context.org;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: org.inkMuted)),
        const SizedBox(height: 12),
        FilledButton.tonal(key: buttonKey, onPressed: () => context.go('/ajustes'), child: Text(button)),
      ],
    );
  }
}

class _EmailRow extends StatelessWidget {
  const _EmailRow({required this.item, required this.now});

  final EmailItem item;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final org = context.org;
    final weight = item.unread ? FontWeight.w700 : FontWeight.w400;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 10),
            child: Icon(Icons.circle, size: 8, color: item.unread ? org.accent : Colors.transparent),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.sender,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: weight)),
                Text(item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: org.inkMuted)),
              ],
            ),
          ),
          if (item.receivedAt != null)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 2),
              child: Text(emailAgoLabel(item.receivedAt!, now),
                  style: theme.textTheme.labelSmall?.copyWith(color: org.inkMuted)),
            ),
        ],
      ),
    );
  }
}
