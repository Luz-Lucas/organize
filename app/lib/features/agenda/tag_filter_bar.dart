import 'package:flutter/material.dart';

import '../../domain/event_tag.dart';
import '../../ui/org_theme.dart';
import '../notes/notebooks/notebooks_logic.dart' show parseFolderColor;
import 'agenda_filter.dart';

/// Fileira de chips no topo da agenda: uma por etiqueta mais "Sem etiqueta". Chip marcado = eventos
/// visíveis; tocar esconde/mostra, segurar abre o menu Editar/Excluir. O último chip, "+ Nova etiqueta",
/// cria uma. Rola na horizontal quando não cabe.
class TagFilterBar extends StatelessWidget {
  const TagFilterBar({
    super.key,
    required this.tags,
    required this.hidden,
    required this.onToggle,
    required this.onNew,
    required this.onEdit,
    required this.onDelete,
  });

  final List<EventTag> tags;
  final Set<String> hidden;
  final ValueChanged<String> onToggle;
  final VoidCallback onNew;
  final ValueChanged<EventTag> onEdit;
  final ValueChanged<EventTag> onDelete;

  Future<void> _menu(BuildContext chipContext, EventTag tag) async {
    final box = chipContext.findRenderObject() as RenderBox;
    final overlay = Overlay.of(chipContext).context.findRenderObject() as RenderBox;
    final rect = Rect.fromPoints(
      box.localToGlobal(Offset.zero, ancestor: overlay),
      box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
    );
    final choice = await showMenu<String>(
      context: chipContext,
      position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
      items: const [
        PopupMenuItem(key: Key('tag-menu-edit'), value: 'edit', child: Text('Editar')),
        PopupMenuItem(key: Key('tag-menu-delete'), value: 'delete', child: Text('Excluir')),
      ],
    );
    if (choice == 'edit') onEdit(tag);
    if (choice == 'delete') onDelete(tag);
  }

  @override
  Widget build(BuildContext context) {
    final org = context.org;
    final gutter = MediaQuery.sizeOf(context).width < 720 ? 16.0 : 24.0;
    Widget chip(Key key, String label, Color? dot, String filterKey, {EventTag? tag}) {
      final filter = FilterChip(
        key: key,
        showCheckmark: false,
        avatar: CircleAvatar(
          radius: 6,
          backgroundColor: dot ?? Colors.transparent,
          child: dot == null ? Icon(Icons.label_off_outlined, size: 12, color: org.inkMuted) : null,
        ),
        label: Text(label),
        selected: !hidden.contains(filterKey),
        onSelected: (_) => onToggle(filterKey),
      );
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: tag == null
            ? filter
            : Builder(
                builder: (ctx) => GestureDetector(onLongPress: () => _menu(ctx, tag), child: filter),
              ),
      );
    }

    return SingleChildScrollView(
      key: const Key('tag-filter-bar'),
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 8),
      child: Row(
        children: [
          for (final t in tags)
            chip(Key('tag-filter-${t.id}'), t.name, parseFolderColor(t.color) ?? org.accentDeep, t.id, tag: t),
          chip(const Key('tag-filter-none'), 'Sem etiqueta', null, kNoTagFilter),
          ActionChip(key: const Key('tag-new'), label: const Text('+ Nova etiqueta'), onPressed: onNew),
        ],
      ),
    );
  }
}
