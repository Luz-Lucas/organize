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
import '../../notebook/create_notebook.dart';
import '../../notebook/notebook_thumbnail.dart';
import '../../notebook/state/notebook_providers.dart';
import '../../ui/org_theme.dart';
import '../import/import_flow.dart';
import '../spaces/spaces_screen.dart' show iconForKind;
import 'notebooks/notebook_actions.dart';
import 'search_fold.dart';

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
    final path = note.isNotebook ? '/caderno/${note.id}' : '/nota/${note.id}';
    // Já dentro de uma nota (barra lateral): troca a nota em vez de empilhar,
    // para o histórico não crescer a cada toque; voltar leva à lista/página anterior.
    // Caderno abre sempre empilhado (tela cheia, fora da casca).
    if (widget.activeNoteId != null && !note.isNotebook) {
      context.pushReplacement(path);
    } else {
      context.push(path);
    }
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

  Future<void> _createNotebook() async {
    try {
      final note = await createNotebook(ref);
      if (mounted) _open(note);
    } on RepositoryException {
      if (mounted) showError(context, 'Não foi possível criar o caderno.');
    }
  }

  Future<void> _notebookMenu(Note note) => showNotebookMenu(context, ref, note);

  @override
  Widget build(BuildContext context) {
    final spaces = ref.watch(spacesProvider).value ?? const <Space>[];
    final notes = ref.watch(notesProvider).value ?? const <Note>[];
    final q = foldSearch(_query);
    final searching = q.isNotEmpty;
    // Busca no título e no corpo; quem casa pelo título vem primeiro.
    bool titleHit(Note n) => foldSearch(n.title).contains(q);
    // Cadernos: também o texto reconhecido da escrita (só buscado quando há busca).
    final recognized = searching ? (ref.watch(notebookRecognizedTextProvider).value ?? const <String, String>{}) : const <String, String>{};
    bool bodyHit(Note n) =>
        foldSearch(n.body).contains(q) || (n.isNotebook && foldSearch(recognized[n.id] ?? '').contains(q));
    final visible = [
      for (final n in notes)
        if (!searching || titleHit(n) || bodyHit(n)) n,
    ]..sort((a, b) {
        if (searching) {
          final byHit = (titleHit(a) ? 0 : 1).compareTo(titleHit(b) ? 0 : 1);
          if (byHit != 0) return byHit;
        }
        return foldSearch(a.title).compareTo(foldSearch(b.title));
      });
    final mobile = MediaQuery.sizeOf(context).width < 720;

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
                  height: mobile ? 48 : 36,
                  child: TextField(
                    key: const Key('notes-search'),
                    controller: _search,
                    style: Theme.of(context).textTheme.bodyMedium,
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: 'Buscar nota',
                      isDense: !mobile,
                      prefixIcon: const Icon(Icons.search, size: 18),
                      prefixIconConstraints: const BoxConstraints(minWidth: 36),
                      contentPadding: EdgeInsets.symmetric(vertical: mobile ? 12 : 8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                key: const Key('tree-new-note'),
                tooltip: 'Nova nota',
                visualDensity: mobile ? null : VisualDensity.compact,
                icon: const Icon(Icons.add, size: 20),
                onPressed: () => _create(notes),
              ),
              IconButton(
                key: const Key('new-notebook'),
                tooltip: 'Novo caderno',
                visualDensity: mobile ? null : VisualDensity.compact,
                icon: const Icon(Icons.draw_outlined, size: 20),
                onPressed: _createNotebook,
              ),
              PopupMenuButton<String>(
                key: const Key('notes-menu'),
                tooltip: 'Mais opções',
                icon: const Icon(Icons.more_vert, size: 20),
                padding: EdgeInsets.zero,
                onSelected: (v) {
                  if (v == 'import') runBatchImport(context, ref);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(key: Key('notes-import'), value: 'import', child: Text('Importar arquivos')),
                ],
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
                  onMenu: _notebookMenu,
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
            for (final n in loose)
              _NoteRow(note: n, active: n.id == widget.activeNoteId, onOpen: _open, onMenu: _notebookMenu),
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
    required this.onMenu,
  });

  final Space space;
  final List<Note> notes;
  final bool expanded;
  final String? activeNoteId;
  final void Function(Note) onOpen;
  final void Function(Note) onMenu;

  @override
  Widget build(BuildContext context) {
    final org = context.org;
    final theme = Theme.of(context);
    final mobile = MediaQuery.sizeOf(context).width < 720;
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: ValueKey('tree-space-${space.id}'),
        initiallyExpanded: expanded,
        dense: true,
        minTileHeight: mobile ? 48 : 34,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: EdgeInsets.zero,
        shape: const Border(),
        collapsedShape: const Border(),
        iconColor: org.inkMuted,
        collapsedIconColor: org.inkMuted,
        leading: Icon(iconForKind(space.kind), size: 18, color: org.inkMuted),
        title: Row(
          children: [
            Expanded(
              child: Text(space.name, style: theme.textTheme.bodyMedium, overflow: TextOverflow.ellipsis),
            ),
            IconButton(
              key: ValueKey('tree-space-open-${space.id}'),
              tooltip: 'Abrir espaço',
              visualDensity: mobile ? null : VisualDensity.compact,
              icon: Icon(Icons.open_in_new, size: 18, color: org.inkMuted),
              onPressed: () => context.push('/espacos/${space.id}'),
            ),
          ],
        ),
        children: [
          if (notes.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(44, 2, 12, 8),
              child: Text('Vazio',
                  style: theme.textTheme.bodySmall?.copyWith(color: org.inkMuted)),
            ),
          for (final n in notes)
            _NoteRow(note: n, active: n.id == activeNoteId, onOpen: onOpen, onMenu: onMenu, indent: 28),
        ],
      ),
    );
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow({
    required this.note,
    required this.active,
    required this.onOpen,
    required this.onMenu,
    this.indent = 0,
  });

  final Note note;
  final bool active;
  final void Function(Note) onOpen;
  final void Function(Note) onMenu;
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
          onLongPress: note.isNotebook ? () => onMenu(note) : null,
          child: Container(
            constraints: BoxConstraints(minHeight: MediaQuery.sizeOf(context).width < 720 ? 48 : 0),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Icon(note.isNotebook ? Icons.menu_book_outlined : Icons.description_outlined,
                    key: ValueKey('tree-note-icon-${note.id}'),
                    size: 16,
                    color: active ? org.accentText : org.inkMuted),
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
                if (note.isNotebook) ...[
                  const SizedBox(width: 8),
                  NotebookThumbnail(noteId: note.id, stamp: note.updatedAt?.millisecondsSinceEpoch ?? 0, width: 20),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
