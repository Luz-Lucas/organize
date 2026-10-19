import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/app/providers.dart';
import 'package:organizacional/data/fitness_repository.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/features/fitness/fitness_providers.dart';
import 'package:organizacional/ui/org_theme.dart';

final fitnessNow = DateTime(2026, 9, 28, 10); // segunda-feira

/// Monta [home] com os repositórios em memória (sem passar por `pumpApp`/rotas do app).
Future<void> pumpFitness(
  WidgetTester tester,
  Widget home, {
  required MemoryFitnessRepository fit,
  MemoryRepository? repo,
  Size size = const Size(800, 1400),
  double textScale = 1.0,
  DateTime? now,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      repositoryProvider.overrideWithValue(repo ?? MemoryRepository()),
      fitnessRepositoryProvider.overrideWithValue(fit),
      clockProvider.overrideWithValue(() => now ?? fitnessNow),
    ],
    child: MaterialApp(
      theme: buildOrgTheme(orgThemes.first, googleFonts: false),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: home,
    ),
  ));
  await tester.pumpAndSettle();
}

/// Toca no widget com [key], rolando até ele se preciso.
Future<void> tapKey(WidgetTester tester, String key, {bool settle = true}) async {
  final f = find.byKey(Key(key));
  expect(f, findsOneWidget, reason: key);
  await tester.ensureVisible(f);
  await tester.tap(f);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}
