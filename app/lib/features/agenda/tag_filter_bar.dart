import 'package:flutter/material.dart';

import '../../domain/event_tag.dart';
import '../../ui/org_theme.dart';
import '../notes/notebooks/notebooks_logic.dart' show parseFolderColor;
import 'agenda_filter.dart';

/// Fileira de chips no topo da agenda: uma por etiqueta mais "Sem etiqueta". Chip marcado = eventos
/// visíveis; tocar esconde/mostra. Rola na horizontal quando não cabe.
class TagFilterBar extends StatelessWidget {
  const TagFilterBar({super.key, required this.tags, required this.hidden, required this.onToggle});

  final List<EventTag> tags;
  final Set<String> hidden;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final org = context.org;
    final gutter = MediaQuery.sizeOf(context).width < 720 ? 16.0 : 24.0;
    Widget chip(Key key, String label, Color? dot, String filterKey) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: FilterChip(
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
          ),
        );
    return SingleChildScrollView(
      key: const Key('tag-filter-bar'),
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 8),
      child: Row(
        children: [
          for (final t in tags)
            chip(Key('tag-filter-${t.id}'), t.name, parseFolderColor(t.color) ?? org.accentDeep, t.id),
          chip(const Key('tag-filter-none'), 'Sem etiqueta', null, kNoTagFilter),
        ],
      ),
    );
  }
}
