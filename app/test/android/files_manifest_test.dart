import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

  group('permissões e visibilidade de pacotes', () {
    test('não pede acesso a todos os arquivos nem leitura do armazenamento externo', () {
      expect(manifest, isNot(contains('MANAGE_EXTERNAL_STORAGE')));
      expect(manifest, isNot(contains('READ_EXTERNAL_STORAGE')));
    });

    test('nada do Samsung Notes no manifesto', () {
      expect(manifest.toLowerCase(), isNot(contains('samsung')));
    });

    test('só existe um bloco <queries>, e o PROCESS_TEXT do Flutter continua lá', () {
      expect(RegExp(r'<queries>').allMatches(manifest), hasLength(1));
      final queries = RegExp(r'<queries>[\s\S]*?</queries>').firstMatch(manifest)!.group(0)!;
      expect(queries, contains('android.intent.action.PROCESS_TEXT'));
      expect(queries, isNot(contains('<package')));
    });
  });

  group('FileProvider dos arquivos baixados do Drive', () {
    final provider = RegExp(r'<provider\b[\s\S]*?</provider>').allMatches(manifest).map((m) => m.group(0)!).singleWhere(
          (p) => p.contains('android:name=".DriveFileProvider"'),
          orElse: () => '',
        );

    test('o <provider> existe, não é exportado e concede permissão de URI por intent', () {
      expect(provider, isNotEmpty);
      expect(provider, contains('android:authorities="${r'${applicationId}'}.drive_files"'));
      expect(provider, contains('android:exported="false"'));
      expect(provider, contains('android:grantUriPermissions="true"'));
      expect(provider, contains('android:resource="@xml/file_paths"'));
    });

    test('o provider fica dentro de <application>', () {
      final app = RegExp(r'<application\b[\s\S]*?</application>').firstMatch(manifest)!.group(0)!;
      expect(app, contains('android:name=".DriveFileProvider"'));
    });

    test('file_paths.xml expõe só files/drive_cache/', () {
      final xml = File('android/app/src/main/res/xml/file_paths.xml').readAsStringSync();
      final paths = RegExp(r'<(files-path|cache-path|external-path|external-files-path|external-cache-path|external-media-path|root-path)\b[^>]*/>')
          .allMatches(xml)
          .map((m) => m.group(0)!)
          .toList();
      expect(paths, hasLength(1));
      expect(paths.single, contains('<files-path'));
      expect(paths.single, contains('path="drive_cache/"'));
    });
  });

  test('nenhum código Kotlin do Samsung Notes sobrou no projeto Android', () {
    final dir = Directory('android/app/src/main/kotlin/dev/organizacional/organizacional');
    final names = dir.listSync().map((e) => e.uri.pathSegments.last.toLowerCase()).toList();
    expect(names.where((n) => n.contains('samsung')), isEmpty);
  });
}
