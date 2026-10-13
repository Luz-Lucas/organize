import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/app/app.dart';
import 'package:organizacional/app/back_navigation.dart';
import 'package:organizacional/app/providers.dart';
import 'package:organizacional/app/router.dart';
import 'package:organizacional/data/alexa_repository.dart';
import 'package:organizacional/data/drive_repository.dart';
import 'package:organizacional/data/email_repository.dart';
import 'package:organizacional/data/directory_picker_service.dart';
import 'package:organizacional/data/file_picker_service.dart';
import 'package:organizacional/data/imported_files_repository.dart';
import 'package:organizacional/data/memory_imported_files_repository.dart';
import 'package:organizacional/data/memory_drive_repository.dart';
import 'package:organizacional/data/github_repository.dart';
import 'package:organizacional/data/memory_github_repository.dart';
import 'package:organizacional/data/memory_email_repository.dart';
import 'package:organizacional/data/location_repository.dart';
import 'package:organizacional/data/memory_location_repository.dart';
import 'package:organizacional/location/location_service.dart';
import 'package:organizacional/data/memory_alexa_repository.dart';
import 'package:organizacional/data/memory_news_repository.dart';
import 'package:organizacional/data/news_repository.dart';
import 'package:organizacional/data/memory_settings_repository.dart';
import 'package:organizacional/data/repository.dart';
import 'package:organizacional/data/settings_repository.dart';
import 'package:organizacional/features/samsung_notes/folder_sync.dart';
import 'package:organizacional/features/samsung_notes/samsung_platform.dart';
import 'package:organizacional/features/samsung_notes/samsung_sync_controller.dart';
import 'package:organizacional/features/samsung_notes/samsung_sync_settings.dart';
import 'package:organizacional/notebook/data/memory_notebook_repository.dart';
import 'package:organizacional/notebook/data/notebook_repository.dart';
import 'package:organizacional/notebook/state/notebook_providers.dart';
import 'package:organizacional/notebook/ui/notebook_session.dart' show NotebookImageStore;

import 'notebook/data/fake_image_store.dart';

final defaultNow = DateTime(2026, 9, 28, 10); // segunda-feira

Future<void> pumpApp(
  WidgetTester tester,
  Repository repo, {
  String location = '/',
  DateTime? now,
  Size size = const Size(1000, 800),
  NewsRepository? news,
  Future<bool> Function(Uri)? openLink,
  AlexaRepository? alexa,
  SettingsRepository? settings,
  LocationRepository? locationRepo,
  EmailRepository? emailRepo,
  DriveRepository? driveRepo,
  FilePickerService? filePicker,
  GithubRepository? githubRepo,
  LocationService? locationService,
  ImportedFilesRepository? importedRepo,
  SamsungNotesPlatform? samsungPlatform,
  SamsungSyncPrefs? samsungPrefs,
  FolderFileSystem? samsungFs,
  SamsungBackgroundScheduler? samsungScheduler,
  DirectoryPickerService? directoryPicker,
  NotebookRepository? notebookRepo,
  NotebookImageStore Function(String noteId)? notebookImages,
  void Function()? exitApp,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      repositoryProvider.overrideWithValue(repo),
      clockProvider.overrideWithValue(() => now ?? defaultNow),
      newsRepositoryProvider.overrideWithValue(news ?? MemoryNewsRepository()),
      linkOpenerProvider.overrideWithValue(openLink ?? (_) async => true),
      alexaRepositoryProvider.overrideWithValue(alexa ?? MemoryAlexaRepository()),
      settingsRepositoryProvider.overrideWithValue(settings ?? MemorySettingsRepository()),
      locationRepositoryProvider.overrideWithValue(locationRepo ?? MemoryLocationRepository()),
      emailRepositoryProvider.overrideWithValue(emailRepo ?? MemoryEmailRepository()),
      driveRepositoryProvider.overrideWithValue(driveRepo ?? MemoryDriveRepository()),
      if (filePicker != null) filePickerProvider.overrideWithValue(filePicker),
      githubRepositoryProvider.overrideWithValue(githubRepo ?? MemoryGithubRepository()),
      importedFilesRepositoryProvider.overrideWithValue(importedRepo ?? MemoryImportedFilesRepository()),
      if (samsungPlatform != null) samsungNotesPlatformProvider.overrideWithValue(samsungPlatform),
      if (samsungPrefs != null) samsungSyncPrefsProvider.overrideWithValue(samsungPrefs),
      if (samsungFs != null) samsungFolderFsProvider.overrideWithValue(samsungFs),
      if (samsungScheduler != null) samsungBackgroundSchedulerProvider.overrideWithValue(samsungScheduler),
      if (directoryPicker != null) directoryPickerProvider.overrideWithValue(directoryPicker),
      if (locationService != null) locationServiceProvider.overrideWithValue(locationService),
      notebookRepositoryProvider.overrideWithValue(notebookRepo ?? MemoryNotebookRepository()),
      notebookImageStoreFactoryProvider.overrideWithValue(notebookImages ?? (_) => FakeNotebookImageStore()),
      googleFontsEnabledProvider.overrideWithValue(false),
      if (exitApp != null) exitAppProvider.overrideWithValue(exitApp),
      ...overrides,
    ],
    child: OrganizacionalApp(
      router: buildRouter(initialLocation: location, isSignedIn: () => true),
    ),
  ));
  await tester.pumpAndSettle();
}
