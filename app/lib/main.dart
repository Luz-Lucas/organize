import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'app/router.dart';
import 'app_icon/app_icon.dart';
import 'data/github_repository.dart';
import 'features/agenda/agenda_filter.dart';
import 'features/notes/notebooks/notebooks_prefs.dart';
import 'files/files_platform.dart';
import 'data/supabase_alexa_repository.dart';
import 'data/supabase_github_repository.dart';
import 'data/drive_repository.dart';
import 'data/email_repository.dart';
import 'data/location_repository.dart';
import 'data/share_intent_service.dart';
import 'data/supabase_drive_repository.dart';
import 'data/supabase_email_repository.dart';
import 'data/supabase_location_repository.dart';
import 'data/supabase_news_repository.dart';
import 'data/supabase_repository.dart';
import 'data/supabase_settings_repository.dart';
import 'features/import/share_listener.dart';
import 'location/geolocator_location_service.dart';
import 'location/location_report_sync.dart';
import 'notebook/data/supabase_notebook_image_store.dart';
import 'notebook/data/supabase_notebook_repository.dart';
import 'notebook/state/notebook_pending_store.dart';
import 'notebook/state/notebook_providers.dart';
import 'location/location_service.dart';
import 'widgets/widget_background.dart';
import 'widgets/widget_links.dart';
import 'widgets/widget_sink.dart';
import 'widgets/widget_sync.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR');
  if (_supabaseUrl.isEmpty || _supabaseKey.isEmpty) {
    runApp(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text('Configure SUPABASE_URL e SUPABASE_ANON_KEY (veja app/env.example.json).'),
        ),
      ),
    ));
    return;
  }
  await Supabase.initialize(url: _supabaseUrl, publishableKey: _supabaseKey);
  final client = Supabase.instance.client;
  final router = buildRouter(
    isSignedIn: () => client.auth.currentSession != null,
    refresh: StreamListenable(client.auth.onAuthStateChange),
  );
  final isAndroid = !kIsWeb && Platform.isAndroid;
  if (isAndroid) {
    void handle(Uri? uri) {
      final route = uri == null ? null : routeForWidgetUri(uri);
      if (route != null) router.go(route);
    }

    HomeWidget.initiallyLaunchedFromHomeWidget().then(handle).catchError((_) {});
    HomeWidget.widgetClicked.listen(handle, onError: (_) {});
    registerWidgetBackgroundRefresh().catchError((_) {});
    registerLocationBackgroundReport().catchError((_) {});
  }
  runApp(ProviderScope(
    overrides: [
      repositoryProvider.overrideWithValue(SupabaseRepository(client)),
      newsRepositoryProvider.overrideWithValue(SupabaseNewsRepository(client)),
      alexaRepositoryProvider.overrideWithValue(SupabaseAlexaRepository(client)),
      settingsRepositoryProvider.overrideWithValue(SupabaseSettingsRepository(client)),
      locationRepositoryProvider.overrideWithValue(SupabaseLocationRepository(client)),
      emailRepositoryProvider.overrideWithValue(SupabaseEmailRepository(client)),
      driveRepositoryProvider.overrideWithValue(SupabaseDriveRepository(client)),
      if (isAndroid) shareIntentServiceProvider.overrideWithValue(MethodChannelShareIntentService()),
      githubRepositoryProvider.overrideWithValue(SupabaseGithubRepository(client)),
      notebookRepositoryProvider.overrideWithValue(SupabaseNotebookRepository(client)),
      notebookPendingStoreProvider.overrideWithValue(const SharedPreferencesNotebookPendingStore()),
      notesTabPrefsProvider.overrideWithValue(const SharedPreferencesNotesTabPrefs()),
      agendaFilterPrefsProvider.overrideWithValue(const SharedPreferencesAgendaFilterPrefs()),
      notebookImageStoreFactoryProvider
          .overrideWithValue((noteId) => SupabaseNotebookImageStore(client, noteId: noteId)),
      filesPlatformProvider.overrideWithValue(
          isAndroid
              ? MethodChannelFilesPlatform()
              : (!kIsWeb && Platform.isLinux
                  ? LinuxFilesPlatform()
                  : (!kIsWeb && Platform.isWindows ? WindowsFilesPlatform() : const NoopFilesPlatform()))),
      signOutProvider.overrideWithValue(() => client.auth.signOut()),
      if (isAndroid) widgetSinkProvider.overrideWithValue(const HomeWidgetSink()),
      if (isAndroid) locationServiceProvider.overrideWithValue(const GeolocatorLocationService()),
      locationSignedInProvider.overrideWithValue(() => client.auth.currentSession != null),
      if (isAndroid) appIconServiceProvider.overrideWithValue(const MethodChannelAppIconService()),
      currentEmailProvider.overrideWithValue(client.auth.currentUser?.email),
    ],
    child: ShareIntentListener(
      router: router,
      isSignedIn: () => client.auth.currentSession != null,
      child: OrganizacionalApp(router: router),
    ),
  ));
}
