import 'package:flutter/material.dart';

import '../../domain/recurrence.dart';

/// Textos da pergunta de escopo (evento ou tarefa).
class SeriesScopeLabels {
  const SeriesScopeLabels({required this.title, required this.one, required this.following, required this.all});

  final String title;
  final String one;
  final String following;
  final String all;

  static const event = SeriesScopeLabels(
    title: 'Este evento se repete',
    one: 'Só este evento',
    following: 'Este e os seguintes',
    all: 'Todos os eventos da série',
  );

  static const task = SeriesScopeLabels(
    title: 'Esta tarefa se repete',
    one: 'Só esta tarefa',
    following: 'Esta e as seguintes',
    all: 'Todas as tarefas da série',
  );
}

/// Pergunta a quais ocorrências de uma série a ação vale. Devolve `null` se o
/// usuário cancelar.
Future<SeriesScope?> showSeriesScopeDialog(
  BuildContext context, {
  required bool deleting,
  SeriesScopeLabels labels = SeriesScopeLabels.event,
}) =>
    showDialog<SeriesScope>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(labels.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(deleting ? 'O que você quer excluir?' : 'O que você quer alterar?'),
            const SizedBox(height: 8),
            _Option(
              key: const Key('series-scope-one'),
              label: labels.one,
              onTap: () => Navigator.of(ctx).pop(SeriesScope.one),
            ),
            _Option(
              key: const Key('series-scope-following'),
              label: labels.following,
              onTap: () => Navigator.of(ctx).pop(SeriesScope.following),
            ),
            _Option(
              key: const Key('series-scope-all'),
              label: labels.all,
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
