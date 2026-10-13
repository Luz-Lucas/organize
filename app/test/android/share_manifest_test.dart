import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
  final mainActivity = RegExp(r'<activity\b[\s\S]*?</activity>').firstMatch(manifest)!.group(0)!;
  final filters = RegExp(r'<intent-filter>[\s\S]*?</intent-filter>').allMatches(mainActivity).map((m) => m.group(0)!).toList();

  List<String> mimes(String f) => RegExp(r'android:mimeType="([^"]*)"').allMatches(f).map((m) => m.group(1)!).toList();

  for (final action in ['SEND', 'SEND_MULTIPLE']) {
    test('a MainActivity recebe ACTION_$action de texto, PDF, imagem e Word', () {
      final f = filters.singleWhere((x) => x.contains('android.intent.action.$action"'));
      expect(f, contains('android.intent.category.DEFAULT'));
      expect(
        mimes(f),
        containsAll([
          'text/*',
          'application/pdf',
          'image/*',
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
          'application/msword',
        ]),
      );
    });
  }

  test('os filtros de compartilhar ficam na MainActivity (não nos aliases de ícone)', () {
    final aliasBlocks = RegExp(r'<activity-alias\b[\s\S]*?</activity-alias>').allMatches(manifest).map((m) => m.group(0)!);
    for (final a in aliasBlocks) {
      expect(a, isNot(contains('android.intent.action.SEND')));
    }
  });

  test('a MainActivity tem o rótulo que aparece na folha de compartilhar', () {
    expect(mainActivity, contains('android:label="Organizacional"'));
  });
}
