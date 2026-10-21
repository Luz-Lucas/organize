import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

  group('lembretes do celular', () {
    test('permissões de notificação, alarme exato e reinício', () {
      for (final p in ['POST_NOTIFICATIONS', 'SCHEDULE_EXACT_ALARM', 'USE_EXACT_ALARM', 'RECEIVE_BOOT_COMPLETED']) {
        expect(manifest, contains('android.permission.$p'), reason: p);
      }
      // SCHEDULE_EXACT_ALARM só até o Android 12L: do 13 em diante vale a USE_EXACT_ALARM.
      expect(manifest, matches(RegExp(r'SCHEDULE_EXACT_ALARM"\s+android:maxSdkVersion="32"')));
    });

    test('receivers do plugin, todos não exportados', () {
      for (final r in ['ScheduledNotificationReceiver', 'ScheduledNotificationBootReceiver', 'ActionBroadcastReceiver']) {
        final m = RegExp('<receiver[^>]*flutterlocalnotifications\\.$r"[^>]*>').firstMatch(manifest);
        expect(m, isNotNull, reason: r);
        expect(m!.group(0), contains('android:exported="false"'), reason: r);
      }
    });

    test('o boot reagenda também depois de atualizar o app', () {
      final boot = RegExp(r'ScheduledNotificationBootReceiver[\s\S]*?</receiver>').firstMatch(manifest)!.group(0)!;
      expect(boot, contains('android.intent.action.BOOT_COMPLETED'));
      expect(boot, contains('android.intent.action.MY_PACKAGE_REPLACED'));
    });

    test('o ícone pequeno da notificação existe e é protegido do encolhimento de recursos', () {
      expect(File('android/app/src/main/res/drawable/ic_launcher_mono.xml').existsSync(), isTrue);
      expect(File('android/app/src/main/res/raw/keep.xml').readAsStringSync(), contains('@drawable/ic_launcher_mono'));
    });
  });
}
