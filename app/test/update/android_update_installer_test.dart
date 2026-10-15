import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/update/android_update_installer.dart';
import 'package:organizacional/update/update_installer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.organizacional/update');
  late List<MethodCall> calls;
  Object? Function(MethodCall)? answer;

  setUp(() {
    calls = [];
    answer = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      final a = answer;
      if (a == null) return null;
      final v = a(call);
      if (v is PlatformException) throw v;
      return v;
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

  test('é a plataforma android e é suportado', () {
    final i = AndroidUpdateInstaller();
    expect(i.platform, 'android');
    expect(i.supported, isTrue);
  });

  test('downloadDir vem do canal (cache/updates do app)', () async {
    answer = (c) => c.method == 'updatesDir' ? '/data/user/0/app/cache/updates' : null;
    final dir = await AndroidUpdateInstaller().downloadDir();
    expect(dir.path, '/data/user/0/app/cache/updates');
  });

  test('install passa o caminho e a opção de abrir os ajustes; started vira InstallResult.started', () async {
    answer = (c) => 'started';
    final out = await AndroidUpdateInstaller().install(File('/x/updates/a.apk'));
    expect(out.result, InstallResult.started);
    expect(calls.single.method, 'install');
    expect(calls.single.arguments, {'path': '/x/updates/a.apk', 'promptForPermission': true});
  });

  test('promptForPermission false vai ao canal (retomada não reabre os ajustes)', () async {
    answer = (c) => 'needs_permission';
    final out = await AndroidUpdateInstaller().install(File('/x/a.apk'), promptForPermission: false);
    expect(out.result, InstallResult.needsPermission);
    expect((calls.single.arguments as Map)['promptForPermission'], false);
  });

  test('needs_permission explica o que fazer, em português', () async {
    answer = (c) => 'needs_permission';
    final out = await AndroidUpdateInstaller().install(File('/x/a.apk'));
    expect(out.result, InstallResult.needsPermission);
    expect(out.message, contains('Instalar apps desconhecidos'));
  });

  test('failed, erro de plataforma e canal ausente viram InstallResult.failed', () async {
    answer = (c) => 'failed';
    expect((await AndroidUpdateInstaller().install(File('/x/a.apk'))).result, InstallResult.failed);
    answer = (c) => PlatformException(code: 'x');
    expect((await AndroidUpdateInstaller().install(File('/x/a.apk'))).result, InstallResult.failed);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    expect((await AndroidUpdateInstaller().install(File('/x/a.apk'))).result, InstallResult.failed);
  });
}
