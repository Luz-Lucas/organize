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
      if (locationService != null) locationServiceProvider.overrideWithValue(locationService),
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
