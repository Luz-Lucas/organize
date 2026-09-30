import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/app/app.dart';
import 'package:organizacional/app/providers.dart';
import 'package:organizacional/app/router.dart';
import 'package:organizacional/data/alexa_repository.dart';
import 'package:organizacional/data/memory_alexa_repository.dart';
import 'package:organizacional/data/memory_news_repository.dart';
import 'package:organizacional/data/news_repository.dart';
import 'package:organizacional/data/repository.dart';

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
    ],
    child: OrganizacionalApp(
      router: buildRouter(initialLocation: location, isSignedIn: () => true),
    ),
  ));
  await tester.pumpAndSettle();
}
