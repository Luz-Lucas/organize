import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/files/drive_cache.dart';
import 'package:organizacional/files/files_platform.dart';

void main() {
  group('WindowsFilesPlatform', () {
    test('cache em %LOCALAPPDATA%\\Organize\\drive_cache', () async {
      final p = WindowsFilesPlatform(env: {'LOCALAPPDATA': r'C:\Users\Lucas\AppData\Local'}, run: (_, _) async => 0);
      expect(await p.cacheRoot(), r'C:\Users\Lucas\AppData\Local\Organize\drive_cache');
    });

    test('sem LOCALAPPDATA usa APPDATA; sem nenhum (ou relativo) não tem cache', () async {
      expect(await WindowsFilesPlatform(env: {'APPDATA': r'D:\AD'}, run: (_, _) async => 0).cacheRoot(),
          r'D:\AD\Organize\drive_cache');
      expect(await WindowsFilesPlatform(env: const {}, run: (_, _) async => 0).cacheRoot(), isNull);
      expect(await WindowsFilesPlatform(env: {'LOCALAPPDATA': 'relativo'}, run: (_, _) async => 0).cacheRoot(), isNull);
    });

    test('abre caminho absoluto pelo url.dll', () async {
      final calls = <List<String>>[];
      final p = WindowsFilesPlatform(env: const {}, run: (exe, args) async {
        calls.add([exe, ...args]);
        return 0;
      });
      expect(await p.openFile(r'C:\cache\abc\aula.pdf', 'application/pdf'), isTrue);
      expect(calls.single, ['rundll32', 'url.dll,FileProtocolHandler', r'C:\cache\abc\aula.pdf']);
    });

    test('recusa caminho relativo, URL ou opção; falha do processo vira false', () async {
      var ran = false;
      final p = WindowsFilesPlatform(env: const {}, run: (_, _) async {
        ran = true;
        return 0;
      });
      for (final bad in ['aula.pdf', '-x', 'https://exemplo.com/a.pdf', r'\\servidor\a.pdf']) {
        expect(await p.openFile(bad, 'application/pdf'), isFalse, reason: bad);
      }
      expect(ran, isFalse);
      expect(await WindowsFilesPlatform(env: const {}, run: (_, _) async => 1).openFile(r'C:\a.pdf', 'x'), isFalse);
      expect(await WindowsFilesPlatform(env: const {}, run: (_, _) async => throw Exception('x')).openFile(r'C:\a.pdf', 'x'),
          isFalse);
    });
  });

  group('samePath', () {
    test('Linux/Android: exato', () {
      expect(samePath('/a/b', '/a/b', windows: false), isTrue);
      expect(samePath('/a/B', '/a/b', windows: false), isFalse);
    });
    test('Windows: barras e maiúsculas não importam', () {
      expect(samePath(r'C:\Users\X\drive_cache\id\a.pdf', 'C:/users/x/drive_cache/id/a.pdf', windows: true), isTrue);
      expect(samePath(r'C:\a\b.pdf', r'C:\a\c.pdf', windows: true), isFalse);
    });
  });
}
