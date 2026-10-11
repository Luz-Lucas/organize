import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/repository.dart';
import '../../domain/ids.dart';
import '../../domain/note.dart';
import '../../domain/space.dart';
import '../../domain/wikilinks.dart';
import '../../ui/common.dart';
import '../../ui/org_theme.dart';
import '../spaces/spaces_screen.dart' show iconForKind;

const _accents = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
  'ç': 'c', 'ñ': 'n',
};

/// Minúsculas, sem acento, espaços normalizados (para a busca da árvore).
String _fold(String s) => normalizeTitle(s).replaceAllMapped(
      RegExp('[${_accents.keys.join()}]'),
      (m) => _accents[m.group(0)]!,
    );

/// Árvore de notas: campo de busca, espaços expansíveis com suas notas,
/// grupo "Sem espaço" e botão de nova nota.
///
/// Não rola sozinha (ocupa a altura do conteúdo): coloque dentro de um
/// scrollable. Precisa de um `Material` acima (a barra lateral e `Scaffold`
/// já têm). Tocar numa nota faz `context.push('/nota/<id>')` e chama [onOpen].
class NotesTree extends ConsumerStatefulWidget {
  const NotesTree({super.key, this.onOpen, this.activeNoteId});

  /// Chamado depois de abrir uma nota (ex.: fechar uma gaveta).
  final VoidCallback? onOpen;

  /// Nota aberta no momento; fica destacada e seu espaço começa expandido.
  final String? activeNoteId;

  @override
  ConsumerState<NotesTree> createState() => _NotesTreeState();
}

class _NotesTreeState extends ConsumerState<NotesTree> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _open(Note note) {
    context.push('/nota/${note.id}');
    widget.onOpen?.call();
  }

  Future<void> _create(List<Note> all) async {
    final note = Note(id: newId(), title: uniqueTitle('Sem título', all));
    try {
      await ref.read(repositoryProvider).upsertNote(note);
    } on RepositoryException {
      if (mounted) showError(context, 'Não foi possível criar a nota.');
      return;
    }
    if (mounted) _open(note);
  }

  @override
  Widget build(BuildContext context) {
    final spaces = ref.watch(spacesProvider).value ?? const <Space>[];
    final notes = ref.watch(notesProvider).value ?? const <Note>[];
    final q = _fold(_query);
    final searching = q.isNotEmpty;
    final visible = [
      for (final n in notes)
        if (!searching || _fold(n.title).contains(q)) n,
    ]..sort((a, b) => _fold(a.title).compareTo(_fold(b.title)));

    final spaceIds = {for (final s in spaces) s.id};
    List<Note> inSpace(String id) => [for (final n in visible) if (n.spaceId == id) n];
    final loose = [for (final n in visible) if (n.spaceId == null || !spaceIds.contains(n.spaceId)) n];
    final sortedSpaces = [...spaces]..sort((a, b) => a.position.compareTo(b.position));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    key: const Key('notes-search'),
                    controller: _search,
                    style: Theme.of(context).textTheme.bodyMedium,
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: 'Buscar nota',
                      isDense: true,
                      prefixIcon: const Icon(Icons.search, size: 18),
                      prefixIconConstraints: const BoxConstraints(minWidth: 36),
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                key: const Key('tree-new-note'),
                tooltip: 'Nova nota',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add, size: 20),
                onPressed: () => _create(notes),
              ),
            ],
          ),
        ),
        if (notes.isEmpty && spaces.isEmpty)
          const EmptyHint('Nenhuma nota ainda.')
        else if (searching && visible.isEmpty)
          const EmptyHint('Nada encontrado.')
        else ...[
          for (final space in sortedSpaces)
            // Sem busca, espaços vazios aparecem; com busca, só os que têm resultado.
            if (!searching || inSpace(space.id).isNotEmpty)
              KeyedSubtree(
                // Recria o tile ao ligar/desligar a busca para reaplicar initiallyExpanded.
                key: ValueKey('tree-group-$searching-${space.id}'),
                child: _SpaceTile(
                  space: space,
                  notes: inSpace(space.id),
                  expanded: searching || inSpace(space.id).any((n) => n.id == widget.activeNoteId),
                  activeNoteId: widget.activeNoteId,
                  onOpen: _open,
                ),
              ),
          if (loose.isNotEmpty) ...[
            if (sortedSpaces.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: Text(
                  'Sem espaço',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            for (final n in loose) _NoteRow(note: n, active: n.id == widget.activeNoteId, onOpen: _open),
          ],
        ],
      ],
    );
  }
}

class _SpaceTile extends StatelessWidget {
  const _SpaceTile({
    required this.space,
    required this.notes,
    required this.expanded,
    required this.activeNoteId,
    required this.onOpen,
  });

  final Space space;
  final List<Note> notes;
  final bool expanded;
  final String? activeNoteId;
  final void Function(Note) onOpen;

  @override
  Widget build(BuildContext context) {
    final org = context.org;
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: ValueKey('tree-space-${space.id}'),
        initiallyExpanded: expanded,
        dense: true,
        minTileHeight: 34,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: EdgeInsets.zero,
        shape: const Border(),
        collapsedShape: const Border(),
        iconColor: org.inkMuted,
        collapsedIconColor: org.inkMuted,
        leading: Icon(iconForKind(space.kind), size: 18, color: org.inkMuted),
        title: Text(space.name, style: theme.textTheme.bodyMedium, overflow: TextOverflow.ellipsis),
        children: [
          if (notes.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(44, 2, 12, 8),
              child: Text('Vazio',
                  style: theme.textTheme.bodySmall?.copyWith(color: org.inkMuted)),
            ),
          for (final n in notes)
            _NoteRow(note: n, active: n.id == activeNoteId, onOpen: onOpen, indent: 28),
        ],
      ),
    );
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow({required this.note, required this.active, required this.onOpen, this.indent = 0});

  final Note note;
  final bool active;
  final void Function(Note) onOpen;
  final double indent;

  @override
  Widget build(BuildContext context) {
    final org = context.org;
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(8 + indent, 1, 8, 1),
      child: Material(
        color: active ? org.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(org.radiusSm),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('tree-note-${note.id}'),
          onTap: () => onOpen(note),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            child: Row(
              children: [
                Icon(Icons.description_outlined,
                    size: 16, color: active ? org.accentText : org.inkMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    note.title,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: active ? org.accentText : org.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
