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
import 'package:organizacional/data/file_picker_service.dart';
import 'package:organizacional/data/fitness_repository.dart';
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
import 'package:organizacional/data/shopping_repository.dart';
import 'package:organizacional/features/fitness/fitness_providers.dart';
import 'package:organizacional/features/shopping/shopping_providers.dart';
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
  FitnessRepository? fitnessRepo,
  ShoppingRepository? shoppingRepo,
  LocationService? locationService,
  NotebookRepository? notebookRepo,
  NotebookImageStore Function(String noteId)? notebookImages,
  void Function()? exitApp,

  /// Troca de uma vez os repositórios principal, Academia, Compras, ajustes e Alexa (ex.: os local-primeiro).
  /// Quando informado, [repo], [fitnessRepo], [shoppingRepo], [settings] e [alexa] não valem.
  List<Override>? repositoryOverrides,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      if (repositoryOverrides == null) ...[
        repositoryProvider.overrideWithValue(repo),
        alexaRepositoryProvider.overrideWithValue(alexa ?? MemoryAlexaRepository()),
        settingsRepositoryProvider.overrideWithValue(settings ?? MemorySettingsRepository()),
        fitnessRepositoryProvider.overrideWithValue(fitnessRepo ?? MemoryFitnessRepository()),
        shoppingRepositoryProvider.overrideWithValue(shoppingRepo ?? MemoryShoppingRepository()),
      ] else
        ...repositoryOverrides,
      clockProvider.overrideWithValue(() => now ?? defaultNow),
      newsRepositoryProvider.overrideWithValue(news ?? MemoryNewsRepository()),
      linkOpenerProvider.overrideWithValue(openLink ?? (_) async => true),
      locationRepositoryProvider.overrideWithValue(locationRepo ?? MemoryLocationRepository()),
      emailRepositoryProvider.overrideWithValue(emailRepo ?? MemoryEmailRepository()),
      driveRepositoryProvider.overrideWithValue(driveRepo ?? MemoryDriveRepository()),
      if (filePicker != null) filePickerProvider.overrideWithValue(filePicker),
      githubRepositoryProvider.overrideWithValue(githubRepo ?? MemoryGithubRepository()),
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
