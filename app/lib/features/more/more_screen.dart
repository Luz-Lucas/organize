import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../ui/org_theme.dart';
import '../../ui/org_widgets.dart';

/// Destinos que não cabem na barra inferior do celular.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  static const _items = [
    (path: '/noticias', icon: Icons.newspaper_outlined, label: 'Notícias'),
    (path: '/casa', icon: Icons.cottage_outlined, label: 'Casa'),
    (path: '/ajustes', icon: Icons.settings_outlined, label: 'Ajustes'),
  ];

  @override
  Widget build(BuildContext context) {
    final org = context.org;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const PageHeader(title: 'Mais'),
            for (final item in _items)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: OrgCard(
                  key: ValueKey('more-${item.path}'),
                  onTap: () => context.go(item.path),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Icon(item.icon, color: org.accentText),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(item.label, style: Theme.of(context).textTheme.titleMedium),
                      ),
                      Icon(Icons.chevron_right, color: org.inkMuted),
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
