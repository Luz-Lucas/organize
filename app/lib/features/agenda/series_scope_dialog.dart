import 'package:flutter/material.dart';

import '../../domain/recurrence.dart';

/// Pergunta a quais ocorrências de uma série a ação vale. Devolve `null` se o
/// usuário cancelar.
Future<SeriesScope?> showSeriesScopeDialog(BuildContext context, {required bool deleting}) =>
    showDialog<SeriesScope>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Este evento se repete'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(deleting ? 'O que você quer excluir?' : 'O que você quer alterar?'),
            const SizedBox(height: 8),
            _Option(
              key: const Key('series-scope-one'),
              label: 'Só este evento',
              onTap: () => Navigator.of(ctx).pop(SeriesScope.one),
            ),
            _Option(
              key: const Key('series-scope-following'),
              label: 'Este e os seguintes',
              onTap: () => Navigator.of(ctx).pop(SeriesScope.following),
            ),
            _Option(
              key: const Key('series-scope-all'),
              label: 'Todos os eventos da série',
              onTap: () => Navigator.of(ctx).pop(SeriesScope.all),
            ),
          ],
        ),
        actions: [
          TextButton(
            key: const Key('series-scope-cancel'),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );

class _Option extends StatelessWidget {
  const _Option({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(label),
        onTap: onTap,
      );
}
