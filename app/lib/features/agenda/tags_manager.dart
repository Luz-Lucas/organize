import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/repository.dart';
import '../../domain/event_tag.dart';
import '../../ui/common.dart';
import '../../ui/org_theme.dart';
import '../notes/notebooks/notebooks_logic.dart' show parseFolderColor;
import 'tag_editor.dart';

/// Gerenciar etiquetas: criar, renomear, recolorir, mudar o papel, reordenar e excluir (o editor é o
/// [TagEditorDialog], o mesmo da fileira de filtros e do editor de evento).
Future<void> showTagsManager(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const TagsManagerDialog());

class TagsManagerDialog extends ConsumerWidget {
  const TagsManagerDialog({super.key});

  Future<void> _reorder(BuildContext context, WidgetRef ref, List<EventTag> tags, int from, int to) async {
    final next = [...tags];
    next.insert(to, next.removeAt(from));
    try {
      await ref.read(repositoryProvider).reorderTags(next);
    } on RepositoryException {
      if (context.mounted) showError(context, 'Não foi possível reordenar as etiquetas.');
    }
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, {EventTag? existing}) =>
      showTagEditor(context, ref, existing: existing);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final org = context.org;
    final theme = Theme.of(context);
    final tags = ref.watch(eventTagsProvider).value ?? const <EventTag>[];
    return AlertDialog(
      key: const Key('tags-manager'),
      title: const Text('Etiquetas'),
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (tags.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('Nenhuma etiqueta ainda.', style: theme.textTheme.bodyMedium?.copyWith(color: org.inkMuted)),
              ),
            for (var i = 0; i < tags.length; i++)
              ListTile(
                key: ValueKey('tag-row-${tags[i].id}'),
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 10,
                  backgroundColor: parseFolderColor(tags[i].color) ?? org.accentDeep,
                ),
                title: Text(tags[i].name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(tags[i].role.label),
                onTap: () => _edit(context, ref, existing: tags[i]),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      key: ValueKey('tag-up-${tags[i].id}'),
                      tooltip: 'Subir',
                      icon: const Icon(Icons.keyboard_arrow_up),
                      onPressed: i == 0 ? null : () => _reorder(context, ref, tags, i, i - 1),
                    ),
                    IconButton(
                      key: ValueKey('tag-down-${tags[i].id}'),
                      tooltip: 'Descer',
                      icon: const Icon(Icons.keyboard_arrow_down),
                      onPressed: i == tags.length - 1 ? null : () => _reorder(context, ref, tags, i, i + 1),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          key: const Key('tag-new'),
          onPressed: () => _edit(context, ref),
          icon: const Icon(Icons.add),
          label: const Text('Nova etiqueta'),
        ),
        TextButton(
          key: const Key('tags-manager-close'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}
