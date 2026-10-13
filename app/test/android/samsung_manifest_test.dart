import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

  test('pede "Acesso a todos os arquivos" (MANAGE_EXTERNAL_STORAGE) para ler a pasta do Samsung Notes', () {
    expect(manifest, contains('<uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"/>'));
  });

  test('READ_EXTERNAL_STORAGE só até o Android 12L (maxSdkVersion 32)', () {
    final m = RegExp(r'<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"[^>]*/>').firstMatch(manifest);
    expect(m, isNotNull);
    expect(m!.group(0), contains('android:maxSdkVersion="32"'));
  });

  test('<queries> enxerga o pacote do Samsung Notes (sem isso o Android 11+ esconde o app)', () {
    final queries = RegExp(r'<queries>[\s\S]*?</queries>').firstMatch(manifest)!.group(0)!;
    expect(queries, contains('<package android:name="com.samsung.android.app.notes"/>'));
    // O <queries> que já existia (PROCESS_TEXT do Flutter) continua lá.
    expect(queries, contains('android.intent.action.PROCESS_TEXT'));
  });

  test('só existe um bloco <queries>', () {
    expect(RegExp(r'<queries>').allMatches(manifest), hasLength(1));
  });
}
