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

  group('FileProvider para "Editar no Samsung Notes"', () {
    final provider = RegExp(r'<provider\b[\s\S]*?</provider>').allMatches(manifest).map((m) => m.group(0)!).singleWhere(
          (p) => p.contains('android:name=".SamsungFileProvider"'),
          orElse: () => '',
        );

    test('o <provider> existe, não é exportado e concede permissão de URI por intent', () {
      expect(provider, isNotEmpty);
      expect(provider, contains('android:authorities="${r'${applicationId}'}.samsung_files"'));
      expect(provider, contains('android:exported="false"'));
      expect(provider, contains('android:grantUriPermissions="true"'));
      expect(provider, contains('android:resource="@xml/file_paths"'));
    });

    test('o provider fica dentro de <application>', () {
      final app = RegExp(r'<application\b[\s\S]*?</application>').firstMatch(manifest)!.group(0)!;
      expect(app, contains('android:name=".SamsungFileProvider"'));
    });

    test('file_paths.xml expõe só cache/samsung_open/', () {
      final xml = File('android/app/src/main/res/xml/file_paths.xml').readAsStringSync();
      final paths = RegExp(r'<(files-path|cache-path|external-path|external-files-path|external-cache-path|external-media-path|root-path)\b[^>]*/>')
          .allMatches(xml)
          .map((m) => m.group(0)!)
          .toList();
      expect(paths, hasLength(1));
      expect(paths.single, contains('<cache-path'));
      expect(paths.single, contains('path="samsung_open/"'));
    });
  });
}
