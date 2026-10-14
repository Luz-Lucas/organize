import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/repository.dart';
import '../../domain/event_tag.dart';
import '../../domain/ids.dart';
import '../../ui/common.dart';
import '../../ui/org_theme.dart';
import '../notes/notebooks/folder_actions.dart' show PaletteSwatch;
import '../notes/notebooks/notebooks_logic.dart';

/// Gerenciar etiquetas: criar, renomear, recolorir, mudar o papel, reordenar e excluir.
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

  Future<void> _edit(BuildContext context, WidgetRef ref, List<EventTag> tags, {EventTag? existing}) async {
    final repo = ref.read(repositoryProvider);
    await showDialog<void>(
      context: context,
      builder: (_) => TagEditorDialog(
        existing: existing,
        initialColor: folderColorHex(folderPalette[tags.length % folderPalette.length]),
        onSave: (draft) async {
          try {
            // Etiqueta nova vai para o fim da lista.
            await repo.upsertTag(existing == null ? draft.copyWith(position: tags.length) : draft);
            return null;
          } on RepositoryException catch (e) {
            return e.duplicate ? 'Já existe uma etiqueta com esse nome.' : 'Não foi possível salvar a etiqueta.';
          }
        },
        onDelete: existing == null
            ? null
            : () async {
                try {
                  await repo.deleteTag(existing.id);
                  return null;
                } on RepositoryException {
                  return 'Não foi possível excluir a etiqueta.';
                }
              },
      ),
    );
  }

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
                onTap: () => _edit(context, ref, tags, existing: tags[i]),
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
          onPressed: () => _edit(context, ref, tags),
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

/// Editor de uma etiqueta: nome, cor (paleta fixa) e papel.
///
/// [onSave] e [onDelete] devolvem `null` em caso de sucesso (o diálogo fecha) ou a mensagem de erro
/// (o diálogo continua aberto, sem perder o que foi digitado).
class TagEditorDialog extends StatefulWidget {
  const TagEditorDialog({
    super.key,
    required this.onSave,
    required this.initialColor,
    this.existing,
    this.onDelete,
  });

  final Future<String?> Function(EventTag draft) onSave;
  final Future<String?> Function()? onDelete;
  final EventTag? existing;

  /// Cor sugerida para etiqueta nova.
  final String initialColor;

  @override
  State<TagEditorDialog> createState() => _TagEditorDialogState();
}

class _TagEditorDialogState extends State<TagEditorDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late String _color = (widget.existing?.color ?? widget.initialColor).toUpperCase();
  late EventTagRole _role = widget.existing?.role ?? EventTagRole.normal;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Dê um nome à etiqueta.');
      return;
    }
    if (name.length > 40) {
      setState(() => _error = 'O nome pode ter até 40 caracteres.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final old = widget.existing;
    final draft = EventTag(
      id: old?.id ?? newId(),
      name: name,
      color: _color,
      role: _role,
      position: old?.position ?? 0,
    );
    final failure = await widget.onSave(draft);
    if (!mounted) return;
    if (failure != null) {
      setState(() {
        _busy = false;
        _error = failure;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Excluir a etiqueta “${widget.existing!.name}”?', maxLines: 3, overflow: TextOverflow.ellipsis),
        content: const Text('Os eventos com essa etiqueta ficarão sem etiqueta. Eles não são apagados.'),
        actions: [
          TextButton(
            key: const Key('tag-delete-cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('tag-delete-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Excluir etiqueta'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final failure = await widget.onDelete!();
    if (!mounted) return;
    if (failure != null) {
      setState(() {
        _busy = false;
        _error = failure;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.labelMedium?.copyWith(color: context.org.inkMuted);
    final editing = widget.existing != null;
    return AlertDialog(
      title: Text(editing ? 'Editar etiqueta' : 'Nova etiqueta'),
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('tag-name'),
              controller: _name,
              autofocus: !editing,
              maxLength: 40,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nome', counterText: ''),
              onSubmitted: (_) => _busy ? null : _save(),
            ),
            const SizedBox(height: 16),
            Text('Cor', style: muted),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in folderPalette)
                  PaletteSwatch(
                    key: Key('tag-color-${folderColorHex(c).substring(1)}'),
                    color: c,
                    selected: folderColorHex(c) == _color,
                    onTap: () => setState(() => _color = folderColorHex(c)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Papel no calendário', style: muted),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in EventTagRole.values)
                  ChoiceChip(
                    key: Key('tag-role-${r.name}'),
                    label: Text(r.label),
                    selected: _role == r,
                    onSelected: (_) => setState(() => _role = r),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(_roleHelp(_role), style: theme.textTheme.bodySmall?.copyWith(color: context.org.inkMuted)),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ),
          ],
        ),
      ),
      actions: [
        if (editing)
          TextButton(
            key: const Key('tag-delete'),
            onPressed: _busy ? null : _delete,
            child: Text('Excluir', style: TextStyle(color: theme.colorScheme.error)),
          ),
        TextButton(
          key: const Key('tag-cancel'),
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(key: const Key('tag-save'), onPressed: _busy ? null : _save, child: const Text('Salvar')),
      ],
    );
  }
}

String _roleHelp(EventTagRole r) => switch (r) {
      EventTagRole.main => 'Destaque: título em negrito e fundo mais forte (ex.: aulas).',
      EventTagRole.secondary => 'Discreta: fundo mais claro, para não competir com o principal (ex.: academia).',
      EventTagRole.seasonal => 'Eventos de época do ano, como viagens e feriados.',
      EventTagRole.meeting => 'Reuniões, em horários variados.',
      EventTagRole.normal => 'Sem peso especial.',
    };
