import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app_icon/app_icon.dart';
import '../location/location_report_sync.dart';
import '../ui/org_theme.dart';
import '../widgets/widget_sync.dart';
import 'providers.dart';

/// Raiz do app. O tema vem de uma única fonte: `settingsProvider`
/// (id desconhecido ou ainda carregando → Violeta).
class OrganizacionalApp extends ConsumerWidget {
  const OrganizacionalApp({super.key, required this.router});

  final GoRouter router;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(widgetSyncProvider);
    ref.watch(appIconSyncProvider);
    ref.watch(locationReportSyncProvider);
    final id = ref.watch(settingsProvider).value?.theme ?? 'violeta';
    final theme = buildOrgTheme(
      orgThemeById(id),
      googleFonts: ref.watch(googleFontsEnabledProvider),
    );
    return MaterialApp.router(
      title: 'Organizacional',
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: theme,
      themeMode: ThemeMode.dark,
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: router,
    );
  }
}
