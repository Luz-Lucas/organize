import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/repository.dart';
import '../../ui/common.dart';
import '../../ui/org_theme.dart';
import '../../ui/org_widgets.dart';
import 'about_card.dart';
import 'downloaded_files_card.dart';
import 'drive_card.dart';
import 'gmail_card.dart';
import 'handwriting_card.dart';
import 'home_location_card.dart';
import 'reminders_card.dart';
import 'widgets_card.dart';

/// Ajustes: escolha do tema (10 sistemas de design) e conta.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _pick(BuildContext context, WidgetRef ref, String id) async {
    try {
      await ref.read(settingsRepositoryProvider).setTheme(id);
    } on RepositoryException {
      if (context.mounted) showError(context, 'Não foi possível salvar o tema.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = orgThemeById(ref.watch(settingsProvider).value?.theme ?? 'violeta').id;
    final email = ref.watch(currentEmailProvider);
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            const PageHeader(title: 'Ajustes', subtitle: 'Aparência e conta'),
            const SectionHeader('Tema'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: LayoutBuilder(
                builder: (context, c) {
                  // Celular: duas colunas que preenchem a largura; computador: 212 fixos.
                  final mobile = MediaQuery.sizeOf(context).width < 720;
                  final cardWidth = mobile ? (c.maxWidth - 12) / 2 : 212.0;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final t in orgThemes)
                        _ThemeCard(
                          spec: t,
                          width: cardWidth,
                          selected: t.id == selected,
                          onTap: () => _pick(context, ref, t.id),
                        ),
                    ],
                  );
                },
              ),
            ),
            if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Text(
                  'O ícone do app muda junto com o tema. Se o atalho da tela inicial '
                  'sumir, arraste o ícone novo da lista de apps.',
                  key: const Key('app-icon-note'),
                  style: theme.textTheme.bodySmall?.copyWith(color: context.org.inkMuted),
                ),
              ),
            const SectionHeader('Minha casa'),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: HomeLocationCard(),
            ),
            const SectionHeader('Lembretes'),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: RemindersCard(),
            ),
            const SectionHeader('E-mail'),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: GmailCard(),
            ),
            const SectionHeader('Documentos'),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: DriveCard(),
            ),
            const DownloadedFilesCard(),
            if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) ...const [
              SectionHeader('Widgets'),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: WidgetsCard(),
              ),
            ],
            const SectionHeader('Escrita à mão'),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: HandwritingCard(),
            ),
            const SectionHeader('Sobre'),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: AboutCard(),
            ),
            const SectionHeader('Conta'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: OrgCard(
                child: Row(
                  children: [
                    Icon(Icons.person_outline, color: context.org.inkMuted),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(email ?? 'Conta conectada', style: theme.textTheme.bodyLarge),
                    ),
                    OutlinedButton.icon(
                      key: const Key('sign-out'),
                      onPressed: () => ref.read(signOutProvider)(),
                      icon: const Icon(Icons.logout, size: 18),
                      label: const Text('Sair'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Amostra de um tema, pintada com as cores do próprio tema.
class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.spec,
    required this.width,
    required this.selected,
    required this.onTap,
  });

  final OrgThemeSpec spec;
  final double width;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = spec;
    final tagline = s.tagline.split('—').first.trim();
    final textTheme = Theme.of(context).textTheme;
    return SizedBox(
      width: width,
      child: Material(
        key: ValueKey('theme-${s.id}'),
        color: s.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(s.radiusMd),
          side: selected ? BorderSide(color: s.accentText, width: 2) : BorderSide(color: s.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: s.accentSoft,
                        borderRadius: BorderRadius.circular(s.radiusSm),
                      ),
                      child: Text(s.glyph, style: TextStyle(color: s.accentText, fontSize: 14)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        s.name,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleMedium?.copyWith(color: s.ink),
                      ),
                    ),
                    if (selected) Icon(Icons.check, size: 18, color: s.accentText),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  tagline,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(color: s.inkMuted),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (final c in [s.accent, s.secondary, s.surfaceRaised, s.line])
                      Container(
                        width: 18,
                        height: 18,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(color: s.line),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
