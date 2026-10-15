import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../data/repository.dart';
import '../../../domain/note.dart';
import '../../../domain/notebook_cover.dart';
import '../../../domain/space.dart';
import '../../../notebook/core/ink_types.dart' show pageHeight, pageWidth;
import '../../../notebook/create_notebook.dart';
import '../../../notebook/notebook_cover_view.dart';
import '../../../notebook/notebook_thumbnail.dart';
import '../../../notebook/pdf/pdf_import.dart' show notebookTitleForPdf;
import '../../../notebook/pdf/pdf_providers.dart';
import '../../../notebook/state/notebook_providers.dart';
import '../../../ui/common.dart';
import '../../../ui/org_theme.dart';
import 'folder_actions.dart';
import 'notebook_actions.dart';
import 'notebooks_logic.dart';
import 'notebooks_prefs.dart';

/// Aba "Cadernos" da tela Notas: pastas (espaços) à esquerda ou em chips no topo, e a grade
/// de cadernos da pasta aberta, com busca e ordem.
class NotebooksView extends ConsumerStatefulWidget {
  const NotebooksView({super.key});

  @override
  ConsumerState<NotebooksView> createState() => _NotebooksViewState();
}

class _NotebooksViewState extends ConsumerState<NotebooksView> {
  final _search = TextEditingController();
  String _query = '';
  NotebookSort _sort = NotebookSort.recent;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// A pasta aberta, ou "Todos" se ela deixou de existir (excluída em outro aparelho).
  String _effectiveFolder(String selected, List<Space> spaces) =>
      selected == kFolderAll || selected == kFolderNone || spaces.any((s) => s.id == selected)
          ? selected
          : kFolderAll;

  Future<void> _newNotebook(String folder) async {
    try {
      final note = await createNotebook(ref, spaceId: folder == kFolderAll || folder == kFolderNone ? null : folder);
      if (mounted) context.push('/caderno/${note.id}');
    } on RepositoryException {
      if (mounted) showError(context, 'Não foi possível criar o caderno.');
    }
  }

  /// "Novo caderno a partir de PDF": escolhe o PDF, cria o caderno com o nome do
  /// arquivo e abre já importando as páginas (a tela do caderno mostra o progresso).
  Future<void> _newNotebookFromPdf(String folder) async {
    final picked = await ref.read(pdfPickerProvider)();
    if (picked == null || !mounted) return;
    try {
      final note = await createNotebook(
        ref,
        spaceId: folder == kFolderAll || folder == kFolderNone ? null : folder,
        title: notebookTitleForPdf(picked.name),
      );
      if (mounted) context.push('/caderno/${note.id}', extra: picked);
    } on RepositoryException {
      if (mounted) showError(context, 'Não foi possível criar o caderno.');
    }
  }

  Future<void> _newFolder() async {
    final space = await createFolder(context, ref);
    if (space != null) ref.read(notebookFolderProvider.notifier).select(space.id);
  }

  void _folderMenu(Space space) => showFolderMenu(
        context,
        ref,
        space,
        onDeleted: () {
          if (ref.read(notebookFolderProvider) == space.id) {
            ref.read(notebookFolderProvider.notifier).select(kFolderAll);
          }
        },
      );

  @override
  Widget build(BuildContext context) {
    final spaces = ref.watch(spacesProvider).value ?? const <Space>[];
    final notes = ref.watch(notesProvider).value ?? const <Note>[];
    final folder = _effectiveFolder(ref.watch(notebookFolderProvider), spaces);
    final searching = _query.trim().isNotEmpty;
    final recognized = searching
        ? (ref.watch(notebookRecognizedTextProvider).value ?? const <String, String>{})
        : const <String, String>{};
    final items = selectNotebooks(notes, spaces,
        folder: folder, sort: _sort, query: _query, recognized: recognized);
    final groups = splitFolders(spaces);
    final wide = MediaQuery.sizeOf(context).width >= 720;
    void select(String f) => ref.read(notebookFolderProvider.notifier).select(f);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Toolbar(
          controller: _search,
          sort: _sort,
          onQuery: (v) => setState(() => _query = v),
          onSort: (s) => setState(() => _sort = s),
          onNewNotebook: () => _newNotebook(folder),
          onNewFromPdf: ref.watch(pdfRasterizerProvider).supported ? () => _newNotebookFromPdf(folder) : null,
        ),
        if (!wide)
          _FolderChips(
            groups: groups,
            selected: folder,
            onSelect: select,
            onMenu: _folderMenu,
            onNewFolder: _newFolder,
          ),
        Expanded(
          child: items.isEmpty
              ? Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
                    child: EmptyHint(searching
                        ? 'Nada encontrado.'
                        : folder == kFolderAll
                            ? 'Nenhum caderno ainda. Toque em “Novo caderno” para começar.'
                            : 'Nenhum caderno nesta pasta.'),
                  ),
                )
              : _Grid(notebooks: items, spaces: spaces),
        ),
      ],
    );

    if (!wide) return content;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FolderRail(
          groups: groups,
          selected: folder,
          onSelect: select,
          onMenu: _folderMenu,
          onNewFolder: _newFolder,
        ),
        VerticalDivider(width: 1, color: context.org.line),
        Expanded(child: content),
      ],
    );
  }
}

typedef _Groups = ({List<Space> materias, List<Space> others});

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.controller,
    required this.sort,
    required this.onQuery,
    required this.onSort,
    required this.onNewNotebook,
    this.onNewFromPdf,
  });

  final TextEditingController controller;
  final NotebookSort sort;
  final ValueChanged<String> onQuery;
  final ValueChanged<NotebookSort> onSort;
  final VoidCallback onNewNotebook;

  /// "Novo caderno a partir de PDF" (`null` esconde: sem leitor de PDF).
  final VoidCallback? onNewFromPdf;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('nb-search'),
              controller: controller,
              onChanged: onQuery,
              decoration: const InputDecoration(
                hintText: 'Buscar caderno',
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 18),
              ),
            ),
          ),
          PopupMenuButton<NotebookSort>(
            key: const Key('nb-sort'),
            tooltip: 'Ordenar',
            icon: const Icon(Icons.sort),
            initialValue: sort,
            onSelected: onSort,
            itemBuilder: (_) => const [
              PopupMenuItem(
                  key: Key('nb-sort-recent'), value: NotebookSort.recent, child: Text('Mais recentes')),
              PopupMenuItem(key: Key('nb-sort-name'), value: NotebookSort.name, child: Text('Nome (A–Z)')),
            ],
          ),
          IconButton(
            key: const Key('new-notebook'),
            tooltip: 'Novo caderno',
            icon: const Icon(Icons.draw_outlined),
            onPressed: onNewNotebook,
          ),
          if (onNewFromPdf != null)
            IconButton(
              key: const Key('new-notebook-pdf'),
              tooltip: 'Novo caderno a partir de PDF',
              icon: const Icon(Icons.picture_as_pdf_outlined),
              onPressed: onNewFromPdf,
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pastas
// ---------------------------------------------------------------------------

class _FolderChips extends StatelessWidget {
  const _FolderChips({
    required this.groups,
    required this.selected,
    required this.onSelect,
    required this.onMenu,
    required this.onNewFolder,
  });

  final _Groups groups;
  final String selected;
  final ValueChanged<String> onSelect;
  final ValueChanged<Space> onMenu;
  final VoidCallback onNewFolder;

  @override
  Widget build(BuildContext context) {
    Widget chip(String key, String label, String id, {Space? space}) => _FolderChip(
          key: ValueKey(key),
          label: label,
          color: space == null ? null : parseFolderColor(space.color),
          icon: space == null ? (id == kFolderNone ? Icons.folder_off_outlined : Icons.apps_outlined) : null,
          selected: selected == id,
          onTap: () => onSelect(id),
          onLongPress: space == null ? null : () => onMenu(space),
        );
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 4),
            child: ActionChip(
              key: const Key('nb-new-folder'),
              avatar: const Icon(Icons.add, size: 18),
              label: const Text('Pasta'),
              tooltip: 'Nova pasta',
              onPressed: onNewFolder,
            ),
          ),
          Expanded(
            // Poucas pastas: um scroll simples (todas construídas) basta.
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: [
                  chip('nb-folder-all', 'Todos', kFolderAll),
                  for (final s in groups.materias) chip('nb-folder-${s.id}', s.name, s.id, space: s),
                  if (groups.materias.isNotEmpty && groups.others.isNotEmpty)
                    Container(
                      key: const Key('nb-folder-divider'),
                      width: 1,
                      height: 24,
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      color: context.org.line,
                    ),
                  for (final s in groups.others) chip('nb-folder-${s.id}', s.name, s.id, space: s),
                  chip('nb-folder-none', 'Sem pasta', kFolderNone),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FolderChip extends StatelessWidget {
  const _FolderChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
    this.icon,
    this.onLongPress,
  });

  final String label;
  final bool selected;
  final Color? color;
  final IconData? icon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final org = context.org;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Center(
        child: Material(
          color: selected ? org.accentSoft : org.surfaceRaised,
          shape: StadiumBorder(side: BorderSide(color: selected ? org.accent : org.line)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40, maxWidth: 200),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null)
                      Icon(icon, size: 16, color: org.inkMuted)
                    else
                      FolderDot(color: color),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: selected ? org.accentText : org.ink,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FolderRail extends StatelessWidget {
  const _FolderRail({
    required this.groups,
    required this.selected,
    required this.onSelect,
    required this.onMenu,
    required this.onNewFolder,
  });

  final _Groups groups;
  final String selected;
  final ValueChanged<String> onSelect;
  final ValueChanged<Space> onMenu;
  final VoidCallback onNewFolder;

  @override
  Widget build(BuildContext context) {
    final org = context.org;
    final theme = Theme.of(context);
    Widget label(String key, String text) => Padding(
          key: Key(key),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Text(text, style: theme.textTheme.labelSmall?.copyWith(color: org.inkMuted)),
        );
    Widget tile(String key, String text, String id, {Space? space, IconData? icon}) => _RailTile(
          key: ValueKey(key),
          label: text,
          color: space == null ? null : parseFolderColor(space.color),
          icon: icon,
          selected: selected == id,
          onTap: () => onSelect(id),
          onLongPress: space == null ? null : () => onMenu(space),
        );
    return SizedBox(
      key: const Key('nb-folder-rail'),
      width: 232,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          tile('nb-folder-all', 'Todos', kFolderAll, icon: Icons.apps_outlined),
          if (groups.materias.isNotEmpty) ...[
            label('nb-folder-label-materias', 'Matérias'),
            for (final s in groups.materias) tile('nb-folder-${s.id}', s.name, s.id, space: s),
          ],
          if (groups.others.isNotEmpty) ...[
            label('nb-folder-label-pastas', 'Pastas'),
            for (final s in groups.others) tile('nb-folder-${s.id}', s.name, s.id, space: s),
          ],
          const SizedBox(height: 8),
          tile('nb-folder-none', 'Sem pasta', kFolderNone, icon: Icons.folder_off_outlined),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('nb-new-folder'),
                onPressed: onNewFolder,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Pasta'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RailTile extends StatelessWidget {
  const _RailTile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
    this.icon,
    this.onLongPress,
  });

  final String label;
  final bool selected;
  final Color? color;
  final IconData? icon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final org = context.org;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: selected ? org.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(org.radiusSm),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  if (icon != null) Icon(icon, size: 16, color: org.inkMuted) else FolderDot(color: color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: selected ? org.accentText : org.ink,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Grade de cadernos
// ---------------------------------------------------------------------------

class _Grid extends ConsumerWidget {
  const _Grid({required this.notebooks, required this.spaces});

  final List<Note> notebooks;
  final List<Space> spaces;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.5);
    final now = ref.watch(clockProvider)();
    final byId = {for (final s in spaces) s.id: s};
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 190,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        // Miniatura (~150) + título de até 2 linhas + data, que crescem com a fonte.
        mainAxisExtent: 150 + 66 * scale,
      ),
      itemCount: notebooks.length,
      itemBuilder: (context, i) {
        final n = notebooks[i];
        return _NotebookCard(
          key: ValueKey('nb-card-${n.id}'),
          note: n,
          folder: byId[n.spaceId],
          dateLabel: notebookDateLabel(n.updatedAt, now),
          onTap: () => context.push('/caderno/${n.id}'),
          onLongPress: () => showNotebookMenu(context, ref, n),
        );
      },
    );
  }
}

class _NotebookCard extends StatelessWidget {
  const _NotebookCard({
    super.key,
    required this.note,
    required this.folder,
    required this.dateLabel,
    required this.onTap,
    required this.onLongPress,
  });

  final Note note;
  final Space? folder;
  final String dateLabel;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final org = context.org;
    final theme = Theme.of(context);
    return Material(
      color: org.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(org.radiusMd),
        side: BorderSide(color: org.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) {
                    final w = (c.maxHeight * pageWidth / pageHeight).clamp(0.0, c.maxWidth);
                    return Center(
                      child: SizedBox(
                        width: w,
                        height: w * pageHeight / pageWidth,
                        child: switch (note.cover) {
                          final cover? => NotebookCoverView(noteId: note.id, cover: cover),
                          null => Stack(
                              fit: StackFit.expand,
                              children: [
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: org.surface,
                                    border: Border.all(color: org.line, width: 0.5),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                  child:
                                      Icon(Icons.menu_book_outlined, color: org.inkMuted, size: (w * 0.4).clamp(0, 40)),
                                ),
                                NotebookThumbnail(
                                    noteId: note.id, stamp: note.updatedAt?.millisecondsSinceEpoch ?? 0, width: w),
                              ],
                            ),
                        },
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 6),
              Text(
                note.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              Row(
                children: [
                  if (folder != null) ...[
                    FolderDot(color: parseFolderColor(folder!.color), size: 8),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(
                      dateLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: org.inkMuted),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
