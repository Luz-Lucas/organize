import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/files/files_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MethodChannelFilesPlatform', () {
    const channel = MethodChannel('dev.organizacional/files');
    final calls = <MethodCall>[];

    void mock(Future<Object?> Function(MethodCall) handler) {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (c) {
        calls.add(c);
        return handler(c);
      });
    }

    tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

    test('cacheRoot e openFile: contrato do canal dev.organizacional/files', () async {
      mock((c) async => switch (c.method) {
            'cacheRoot' => '/data/user/0/dev.organizacional.organizacional/files/drive_cache',
            'openFile' => true,
            _ => throw MissingPluginException(),
          });
      final p = MethodChannelFilesPlatform();
      expect(p.supported, isTrue);
      expect(await p.cacheRoot(), '/data/user/0/dev.organizacional.organizacional/files/drive_cache');
      expect(await p.openFile('/x/drive_cache/F1/a.pdf', 'application/pdf'), isTrue);
      expect(calls.last.arguments, {'path': '/x/drive_cache/F1/a.pdf', 'mime': 'application/pdf'});
    });

    test('falha do canal vira valor neutro', () async {
      mock((c) async => throw PlatformException(code: 'x'));
      final p = MethodChannelFilesPlatform();
      expect(await p.cacheRoot(), isNull);
      expect(await p.openFile('/x', 'a/b'), isFalse);
      mock((c) async => throw MissingPluginException());
      expect(await p.cacheRoot(), isNull);
      expect(await p.openFile('/x', 'a/b'), isFalse);
      mock((c) async => null);
      expect(await p.openFile('/x', 'a/b'), isFalse);
    });
  });

  group('LinuxFilesPlatform', () {
    test('a pasta fica em ~/.local/share/dev.organizacional.organizacional/drive_cache (ou XDG_DATA_HOME)', () async {
      expect(await LinuxFilesPlatform(env: {'HOME': '/home/u'}).cacheRoot(), '/home/u/.local/share/dev.organizacional.organizacional/drive_cache');
      expect(
        await LinuxFilesPlatform(env: {'HOME': '/home/u', 'XDG_DATA_HOME': '/dados'}).cacheRoot(),
        '/dados/dev.organizacional.organizacional/drive_cache',
      );
      expect(await LinuxFilesPlatform(env: {'HOME': '/home/u', 'XDG_DATA_HOME': ''}).cacheRoot(), contains('/home/u/.local/share/'));
      expect(await LinuxFilesPlatform(env: const {}).cacheRoot(), isNull);
      // XDG_DATA_HOME relativo não vale (a especificação manda ignorar)
      expect(await LinuxFilesPlatform(env: {'HOME': '/home/u', 'XDG_DATA_HOME': 'rel'}).cacheRoot(), contains('/home/u/.local/share/'));
    });

    test('openFile chama xdg-open com o caminho; sucesso = código 0', () async {
      final runs = <List<String>>[];
      final p = LinuxFilesPlatform(env: const {'HOME': '/h'}, run: (exe, args) async {
        runs.add([exe, ...args]);
        return 0;
      });
      expect(p.supported, isTrue);
      expect(await p.openFile('/h/a.pdf', 'application/pdf'), isTrue);
      expect(runs, [
        ['xdg-open', '/h/a.pdf']
      ]);
      final fail = LinuxFilesPlatform(env: const {}, run: (e, a) async => 3);
      expect(await fail.openFile('/h/a.pdf', 'application/pdf'), isFalse);
      final missing = LinuxFilesPlatform(env: const {}, run: (e, a) async => throw Exception('sem xdg-open'));
      expect(await missing.openFile('/h/a.pdf', 'application/pdf'), isFalse);
    });

    test('nome que parece opção não vira argumento de xdg-open', () async {
      final runs = <List<String>>[];
      final p = LinuxFilesPlatform(env: const {}, run: (exe, args) async {
        runs.add(args);
        return 0;
      });
      expect(await p.openFile('-malicioso.pdf', 'application/pdf'), isFalse);
      expect(runs, isEmpty);
    });
  });

  test('NoopFilesPlatform: sem suporte, sem pasta, nada abre', () async {
    const p = NoopFilesPlatform();
    expect(p.supported, isFalse);
    expect(await p.cacheRoot(), isNull);
    expect(await p.openFile('/x', 'a/b'), isFalse);
  });
}
