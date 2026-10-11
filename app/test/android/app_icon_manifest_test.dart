import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/domain/user_settings.dart';

String _cap(String s) => s[0].toUpperCase() + s.substring(1);

void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
  final aliases = RegExp(r'<activity-alias\b[\s\S]*?</activity-alias>')
      .allMatches(manifest)
      .map((m) => m.group(0)!)
      .toList();

  String attr(String block, String name) =>
      RegExp('android:$name="([^"]*)"').firstMatch(block)?.group(1) ?? '';

  test('há exatamente um activity-alias por tema', () {
    final names = aliases.map((a) => attr(a, 'name')).toList();
    expect(names,
        unorderedEquals([for (final id in themeIds) 'dev.organizacional.organizacional.Icon${_cap(id)}']));
  });

  test('só o violeta vem habilitado; todos exportados e apontando a MainActivity', () {
    for (final a in aliases) {
      final name = attr(a, 'name');
      final isViolet = name.endsWith('.IconVioleta');
      expect(attr(a, 'enabled'), isViolet ? 'true' : 'false', reason: name);
      expect(attr(a, 'exported'), 'true', reason: name);
      expect(attr(a, 'targetActivity'), '.MainActivity', reason: name);
      expect(a, contains('android.intent.action.MAIN'), reason: name);
      expect(a, contains('android.intent.category.LAUNCHER'), reason: name);
    }
  });

  test('cada alias usa o ícone adaptativo do seu tema', () {
    for (final id in themeIds) {
      final a = aliases.firstWhere((x) => attr(x, 'name').endsWith('.Icon${_cap(id)}'));
      expect(attr(a, 'icon'), '@mipmap/ic_launcher_$id');
      expect(attr(a, 'roundIcon'), '@mipmap/ic_launcher_$id');
    }
  });

  test('a MainActivity não tem categoria LAUNCHER', () {
    final main = RegExp(r'<activity\b[\s\S]*?</activity>').firstMatch(manifest)!.group(0)!;
    expect(attr(main, 'name'), '.MainActivity');
    expect(main, isNot(contains('category.LAUNCHER')));
  });

  test('existe mipmap-anydpi-v26/ic_launcher_<id>.xml adaptativo para cada tema', () {
    for (final id in themeIds) {
      final f = File('android/app/src/main/res/mipmap-anydpi-v26/ic_launcher_$id.xml');
      expect(f.existsSync(), isTrue, reason: id);
      final xml = f.readAsStringSync();
      expect(xml, contains('<adaptive-icon'));
      expect(xml, contains('<background'));
      expect(xml, contains('<foreground'));
      expect(xml, contains('<monochrome'));
    }
  });

  test('minSdk do app é pelo menos 26', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('maxOf(flutter.minSdkVersion, 26)'));
  });
}
