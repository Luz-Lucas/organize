import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/org_theme.dart';
import '../../ui/org_widgets.dart';
import '../../widgets/widget_appearance.dart';
import '../../widgets/widget_sync.dart';

/// Ajustes > "Widgets": transparência do fundo de todos os widgets da tela inicial.
/// É preferência do aparelho (cada celular tem um papel de parede), por isso não vai ao Supabase.
class WidgetsCard extends ConsumerWidget {
  const WidgetsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(widgetBgTransparencyProvider);
    final theme = Theme.of(context);
    return OrgCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Transparência do fundo', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Deixa o fundo dos widgets mais transparente; o texto continua nítido. '
            'Vale para todos os widgets deste aparelho.',
            style: theme.textTheme.bodySmall?.copyWith(color: context.org.inkMuted),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final pct in widgetBgTransparencyOptions)
                ChoiceChip(
                  key: ValueKey('widget-bg-$pct'),
                  label: Text('$pct%'),
                  selected: pct == selected,
                  onSelected: (_) => ref.read(widgetBgTransparencyProvider.notifier).set(pct),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
