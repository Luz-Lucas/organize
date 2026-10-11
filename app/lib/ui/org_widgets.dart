import 'package:flutter/material.dart';

import 'org_theme.dart';

/// Cartão padrão do app: fundo `surfaceRaised`, borda fina `line`, `radiusMd`.
/// Com [onTap] vira clicável (com efeito de toque recortado no raio).
class OrgCard extends StatelessWidget {
  const OrgCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final org = context.org;
    final radius = BorderRadius.circular(org.radiusMd);
    return Material(
      color: org.surfaceRaised,
      shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: org.line)),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? Padding(padding: padding, child: child)
          : InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

/// Tom de um [OrgBadge].
enum OrgBadgeTone {
  /// `accentSoft` + `accentText` (destaque principal).
  accent,

  /// `secondarySoft` + `secondary` (apoio decorativo).
  secondary,

  /// Fundo neutro + texto apagado.
  neutral,

  /// Vermelho de erro/atraso.
  danger,
}

/// Selo pequeno (status, prioridade, contagem).
class OrgBadge extends StatelessWidget {
  const OrgBadge(this.label, {super.key, this.tone = OrgBadgeTone.accent});

  final String label;
  final OrgBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final org = context.org;
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (tone) {
      OrgBadgeTone.accent => (org.accentSoft, org.accentText),
      OrgBadgeTone.secondary => (org.secondarySoft, org.ink),
      OrgBadgeTone.neutral => (org.surface, org.inkMuted),
      OrgBadgeTone.danger => (scheme.errorContainer, scheme.error),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(org.radiusSm),
        border: tone == OrgBadgeTone.neutral ? Border.all(color: org.line) : null,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg),
      ),
    );
  }
}

/// Cabeçalho de página: título em fonte de exibição, subtítulo apagado e
/// ações à direita. Use no topo de cada tela (no lugar de `AppBar`).
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.actions = const []});

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.headlineSmall),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// Rótulo de seção: pequeno, apagado, com espaçamento entre letras.
/// (O texto não é alterado para maiúsculas, para continuar localizável.)
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 28, 8, 8),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.9,
        ),
      ),
    );
  }
}

/// Texto discreto para listas vazias.
class EmptyHint extends StatelessWidget {
  const EmptyHint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}
