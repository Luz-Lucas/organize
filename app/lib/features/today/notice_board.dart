import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/repository.dart';
import '../../domain/notice.dart';
import '../../domain/system_notices.dart';
import '../../ui/common.dart';
import '../../ui/org_theme.dart';
import '../../ui/org_widgets.dart';
import 'notice_dialog.dart';

enum _NoticeAction { edit, pin, archive, delete }

/// Cartão "Quadro de avisos": avisos do sistema primeiro, depois os do usuário.
class NoticeBoard extends ConsumerWidget {
  const NoticeBoard({super.key, required this.system, required this.notices, required this.now});

  final List<SystemNotice> system;
  final List<Notice> notices;
  final DateTime now;

  Future<void> _act(BuildContext context, WidgetRef ref, Notice n, _NoticeAction a) async {
    final repo = ref.read(repositoryProvider);
    try {
      switch (a) {
        case _NoticeAction.edit:
          await showDialog<void>(context: context, builder: (_) => NoticeDialog(existing: n));
        case _NoticeAction.pin:
          await repo.upsertNotice(n.copyWith(pinned: !n.pinned));
        case _NoticeAction.archive:
          await repo.upsertNotice(n.copyWith(archivedAt: now));
        case _NoticeAction.delete:
          await repo.deleteNotice(n.id);
      }
    } on RepositoryException {
      if (context.mounted) showError(context, 'Não foi possível atualizar o aviso.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final org = context.org;
    final empty = system.isEmpty && notices.isEmpty;
    return OrgCard(
      key: const Key('notice-board'),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Quadro de avisos',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
              ),
              IconButton(
                key: const Key('new-notice'),
                tooltip: 'Novo aviso',
                icon: Icon(Icons.add, color: org.accentText),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const NoticeDialog(),
                ),
              ),
            ],
          ),
          if (empty) const Padding(padding: EdgeInsets.only(bottom: 4), child: EmptyHint('Nenhum aviso por enquanto.')),
          for (final s in system)
            InkWell(
              key: ValueKey('system-notice-${s.id}'),
              borderRadius: BorderRadius.circular(org.radiusSm),
              onTap: s.route == null ? null : () => context.go(s.route!),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_outlined, size: 20, color: org.inkMuted),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(s.text,
                          style: theme.textTheme.bodyMedium?.copyWith(color: org.inkMuted)),
                    ),
                    const SizedBox(width: 8),
                    const OrgBadge('sistema', tone: OrgBadgeTone.neutral),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
          for (final n in notices) _NoticeRow(notice: n, onAction: (a) => _act(context, ref, n, a)),
        ],
      ),
    );
  }
}

class _NoticeRow extends StatelessWidget {
  const _NoticeRow({required this.notice, required this.onAction});

  final Notice notice;
  final void Function(_NoticeAction) onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final org = context.org;
    final n = notice;
    return Padding(
      key: ValueKey('notice-${n.id}'),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(org.glyph, style: TextStyle(color: org.accentText, fontSize: 18)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(child: Text(n.title, style: theme.textTheme.titleSmall)),
                    if (n.priority == NoticePriority.alta) ...[
                      const SizedBox(width: 8),
                      const OrgBadge('alta', tone: OrgBadgeTone.danger),
                    ],
                    if (n.pinned) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.push_pin_outlined, size: 16, color: org.inkMuted),
                    ],
                  ],
                ),
                if (n.body.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      n.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(color: org.inkMuted),
                    ),
                  ),
              ],
            ),
          ),
          PopupMenuButton<_NoticeAction>(
            key: ValueKey('notice-menu-${n.id}'),
            tooltip: 'Opções do aviso',
            icon: Icon(Icons.more_vert, size: 20, color: org.inkMuted),
            onSelected: onAction,
            itemBuilder: (_) => [
              const PopupMenuItem(value: _NoticeAction.edit, child: Text('Editar')),
              PopupMenuItem(
                value: _NoticeAction.pin,
                child: Text(n.pinned ? 'Desafixar' : 'Fixar'),
              ),
              PopupMenuItem(
                key: ValueKey('archive-notice-${n.id}'),
                value: _NoticeAction.archive,
                child: const Text('Arquivar'),
              ),
              const PopupMenuItem(value: _NoticeAction.delete, child: Text('Excluir')),
            ],
          ),
        ],
      ),
    );
  }
}
