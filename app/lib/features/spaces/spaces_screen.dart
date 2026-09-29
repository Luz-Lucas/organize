import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/repository.dart';
import '../../domain/ids.dart';
import '../../domain/space.dart';
import '../../ui/common.dart';

IconData iconForKind(SpaceKind kind) => switch (kind) {
      SpaceKind.materia => Icons.school_outlined,
      SpaceKind.trabalho => Icons.assignment_outlined,
      SpaceKind.hobby => Icons.palette_outlined,
      SpaceKind.geral => Icons.folder_outlined,
    };

class SpacesScreen extends ConsumerWidget {
  const SpacesScreen({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref, List<Space> existing) async {
    final result = await showDialog<(String, SpaceKind)>(
      context: context,
      builder: (_) => const SpaceDialog(),
    );
    if (result == null) return;
    final (name, kind) = result;
    try {
      await ref
          .read(repositoryProvider)
          .upsertSpace(Space(id: newId(), name: name, kind: kind, position: existing.length));
    } on RepositoryException {
      if (context.mounted) showError(context, 'Não foi possível criar o espaço.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spaces = ref.watch(spacesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Espaços'),
        actions: [
          IconButton(
            key: const Key('sign-out'),
            tooltip: 'Sair',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(signOutProvider)(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('new-space'),
        tooltip: 'Novo espaço',
        onPressed: () => _create(context, ref, spaces.value ?? const []),
        child: const Icon(Icons.add),
      ),
      body: asyncView(spaces, (list) {
        if (list.isEmpty) {
          return const Center(
            child: EmptyHint('Crie um espaço para cada matéria, trabalho ou hobby.'),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final kind in SpaceKind.values)
              if (list.any((s) => s.kind == kind)) ...[
                SectionHeader(kind.plural),
                for (final s in list.where((s) => s.kind == kind))
                  ListTile(
                    leading: Icon(iconForKind(kind)),
                    title: Text(s.name),
                    onTap: () => context.go('/espacos/${s.id}'),
                  ),
              ],
          ],
        );
      }),
    );
  }
}

class SpaceDialog extends StatefulWidget {
  const SpaceDialog({super.key});

  @override
  State<SpaceDialog> createState() => _SpaceDialogState();
}

class _SpaceDialogState extends State<SpaceDialog> {
  final _name = TextEditingController();
  SpaceKind _kind = SpaceKind.materia;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = _name.text.trim();
    return AlertDialog(
      title: const Text('Novo espaço'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('space-name'),
            controller: _name,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Nome'),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final k in SpaceKind.values)
                ChoiceChip(
                  label: Text(k.singular),
                  selected: _kind == k,
                  onSelected: (_) => setState(() => _kind = k),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(
          onPressed: name.isEmpty ? null : () => Navigator.of(context).pop((name, _kind)),
          child: const Text('Criar'),
        ),
      ],
    );
  }
}
