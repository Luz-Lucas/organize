import 'package:flutter/material.dart';

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
          children: const [
            PageHeader(title: 'Notas'),
            Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: NotesTree()),
          ],
        ),
      ),
    );
  }
}
