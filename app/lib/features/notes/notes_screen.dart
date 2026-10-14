import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../ui/org_widgets.dart';
import '../spaces/spaces_screen.dart';
import 'notebooks/notebooks_prefs.dart';
import 'notebooks/notebooks_view.dart';
import 'notes_tree.dart';

/// Tela `/notas`, com duas abas: **Notas** e **Cadernos** (a escolha fica guardada no aparelho).
///
/// Notas: no celular mostra a árvore de notas em tela cheia; no computador (>= 720px) a árvore
/// já está na barra lateral, então mostra a lista de espaços.
/// Cadernos: pastas (espaços) e a grade de cadernos.
class NotesScreen extends ConsumerWidget {
  const NotesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(notesTabProvider);
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final selector = Padding(
      padding: EdgeInsets.fromLTRB(wide ? 24 : 16, wide ? 12 : 0, 16, 8),
      child: SegmentedButton<NotesTab>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: NotesTab.notes, label: Text('Notas', key: Key('notes-tab-notes'))),
          ButtonSegment(value: NotesTab.notebooks, label: Text('Cadernos', key: Key('notes-tab-notebooks'))),
        ],
        selected: {tab},
        onSelectionChanged: (s) => ref.read(notesTabProvider.notifier).select(s.first),
      ),
    );

    if (wide) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(alignment: Alignment.centerLeft, child: selector),
              Expanded(child: tab == NotesTab.notes ? const SpacesScreen() : const NotebooksView()),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Notas',
              actions: [
                IconButton(
                  key: const Key('open-spaces'),
                  tooltip: 'Espaços',
                  icon: const Icon(Icons.folder_outlined),
                  onPressed: () => context.push('/espacos'),
                ),
              ],
            ),
            selector,
            Expanded(
              child: tab == NotesTab.notes
                  ? ListView(
                      padding: const EdgeInsets.only(bottom: 24),
                      children: const [
                        Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: NotesTree()),
                      ],
                    )
                  : const NotebooksView(),
            ),
          ],
        ),
      ),
    );
  }
}
