import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../ui/org_widgets.dart';
import '../spaces/spaces_screen.dart';
import 'notes_tree.dart';

/// Tela `/notas`. No celular mostra a árvore de notas em tela cheia; no
/// computador (>= 720px) a árvore já está na barra lateral, então mostra a
/// lista de espaços.
class NotesScreen extends StatelessWidget {
  const NotesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width >= 720) return const SpacesScreen();
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
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
            const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: NotesTree()),
          ],
        ),
      ),
    );
  }
}
