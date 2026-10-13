import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/features/samsung_notes/device_file_system.dart';
import 'package:organizacional/features/samsung_notes/folder_sync.dart';
import 'package:organizacional/features/samsung_notes/samsung_folder.dart';
import 'package:organizacional/features/samsung_notes/samsung_platform.dart';

class FakePlatform implements SamsungNotesPlatform {
  List<SyncEntry> tree = [];
  Map<String, String> cache = {};
  bool throwMissing = false;
  final listed = <String>[];
  final copied = <String>[];

  @override
  Future<bool> isInstalled() async => true;
  @override
  Future<bool> open() async => true;
  @override
  Future<bool> hasAllFilesAccess() async => true;
  @override
  Future<bool> requestAllFilesAccess() async => true;
  @override
  Future<List<String>> findFolders() async => [];
  @override
  Future<SamsungFolder?> pickFolder() async => null;
  @override
  Future<String?> deviceName() async => 'Teste';
  @override
  Future<String?> openDir() async => null;
  @override
  Future<bool> openFile(String path) async => false;

  @override
  Future<List<SyncEntry>> listTree(String uri) async {
    if (throwMissing) throw const FolderAccessException('Abra o app para sincronizar esta pasta.');
    listed.add(uri);
    return tree;
  }

  @override
  Future<String?> copyToCache(String uri) async {
    copied.add(uri);
    return cache[uri];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('uriToPath', () {
    test('armazenamento interno (primary) vira /storage/emulated/0/...', () {
      expect(
        uriToPath('content://com.android.externalstorage.documents/tree/primary%3ADocuments%2FSamsung%20Notes'),
        '/storage/emulated/0/Documents/Samsung Notes',
      );
      expect(uriToPath('content://com.android.externalstorage.documents/tree/primary%3A'), '/storage/emulated/0');
    });

    test('cartão SD (volume com id) vira /storage/<id>/...', () {
      expect(uriToPath('content://com.android.externalstorage.documents/tree/1A2B-3C4D%3ANotas'), '/storage/1A2B-3C4D/Notas');
    });

    test('outros provedores (Drive, Downloads...) e lixo não têm caminho', () {
      expect(uriToPath('content://com.android.providers.downloads.documents/tree/downloads'), isNull);
      expect(uriToPath('content://com.google.android.apps.docs.storage/tree/x'), isNull);
      expect(uriToPath('não é uri'), isNull);
      expect(uriToPath('/sdcard/Documents'), isNull);
    });

    test('".." no caminho é recusado', () {
      expect(uriToPath('content://com.android.externalstorage.documents/tree/primary%3A..%2F..%2Fdata'), isNull);
    });
  });

  test('"Download" é uma pasta geral: precisa de confirmação; "Samsung Notes" não', () {
    expect(folderNeedsConfirmation('/storage/emulated/0/Download'), isTrue);
    expect(folderNeedsConfirmation('/storage/emulated/0/download/'), isTrue);
    expect(folderNeedsConfirmation('/storage/emulated/0/Documents/Samsung Notes'), isFalse);
    expect(folderNeedsConfirmation('/storage/emulated/0/Download/Samsung Notes'), isFalse);
    expect(folderNeedsConfirmation('/storage/emulated/0/Documents/Samsung'), isFalse);
  });

  group('MethodChannelSamsungNotesPlatform', () {
    const channel = MethodChannel('dev.organizacional/samsung_notes');
    final calls = <MethodCall>[];

    setUp(() => calls.clear());
    tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

    void mock(Future<Object?> Function(MethodCall) handler) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (c) {
        calls.add(c);
        return handler(c);
      });
    }

    test('chama os métodos do contrato e converte os resultados', () async {
      mock((c) async => switch (c.method) {
            'isInstalled' || 'open' || 'hasAllFilesAccess' || 'requestAllFilesAccess' => true,
            'findFolders' => ['/a/Samsung Notes', '/a/Download'],
            'pickFolder' => {'uri': 'content://tree/1', 'label': 'Notas'},
            'listTree' => [
                {'id': 'content://doc/1', 'name': 'a.pdf', 'size': 10, 'modified': 1760000000000},
              ],
            'copyToCache' => '/cache/a.pdf',
            'deviceName' => 'samsung SM-X200',
            _ => throw MissingPluginException(),
          });
      final p = MethodChannelSamsungNotesPlatform();
      expect(await p.isInstalled(), isTrue);
      expect(await p.open(), isTrue);
      expect(await p.hasAllFilesAccess(), isTrue);
      expect(await p.requestAllFilesAccess(), isTrue);
      expect(await p.findFolders(), ['/a/Samsung Notes', '/a/Download']);
      expect(await p.pickFolder(), const SamsungFolder(uri: 'content://tree/1', label: 'Notas'));
      final tree = await p.listTree('content://tree/1');
      expect(tree.single.name, 'a.pdf');
      expect(tree.single.size, 10);
      expect(tree.single.modified, DateTime.fromMillisecondsSinceEpoch(1760000000000));
      expect(await p.copyToCache('content://doc/1'), '/cache/a.pdf');
      expect(await p.deviceName(), 'samsung SM-X200');
      expect(calls.map((c) => c.method), containsAll(['isInstalled', 'findFolders', 'pickFolder', 'listTree', 'copyToCache']));
      expect(calls.firstWhere((c) => c.method == 'listTree').arguments, {'uri': 'content://tree/1'});
    });

    test('falha do canal (plugin ausente, erro nativo) vira valor neutro', () async {
      mock((c) async => throw PlatformException(code: 'x'));
      final p = MethodChannelSamsungNotesPlatform();
      expect(await p.isInstalled(), isFalse);
      expect(await p.open(), isFalse);
      expect(await p.hasAllFilesAccess(), isFalse);
      expect(await p.findFolders(), isEmpty);
      expect(await p.pickFolder(), isNull);
      expect(await p.deviceName(), isNull);
      await expectLater(p.listTree('content://x'), throwsA(isA<FolderAccessException>()));
    });

    test('openDir e openFile: contrato do canal (openFile manda {path}) e valores neutros em falha', () async {
      mock((c) async => switch (c.method) {
            'openDir' => '/data/cache/samsung_open',
            'openFile' => true,
            _ => throw MissingPluginException(),
          });
      final p = MethodChannelSamsungNotesPlatform();
      expect(await p.openDir(), '/data/cache/samsung_open');
      expect(await p.openFile('/data/cache/samsung_open/Aula.sdocx'), isTrue);
      expect(calls.firstWhere((c) => c.method == 'openFile').arguments, {'path': '/data/cache/samsung_open/Aula.sdocx'});

      mock((c) async => throw PlatformException(code: 'x'));
      expect(await p.openDir(), isNull);
      expect(await p.openFile('/x'), isFalse);
      mock((c) async => null);
      expect(await p.openFile('/x'), isFalse);
    });

    test('pickFolder cancelado (null) devolve null', () async {
      mock((c) async => null);
      expect(await MethodChannelSamsungNotesPlatform().pickFolder(), isNull);
    });
  });

  group('DeviceFolderFileSystem', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('samsung_fs_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('lista só arquivos do primeiro nível, com tamanho e data', () async {
      File('${dir.path}/a.pdf').writeAsBytesSync([1, 2, 3]);
      Directory('${dir.path}/sub').createSync();
      File('${dir.path}/sub/b.pdf').writeAsBytesSync([1]);
      final fs = DeviceFolderFileSystem();
      final entries = await fs.list(SamsungFolder(path: dir.path));
      expect(entries.map((e) => e.name), ['a.pdf']);
      expect(entries.single.size, 3);
      expect(entries.single.id, '${dir.path}/a.pdf');
      expect(DateTime.now().difference(entries.single.modified).inMinutes, lessThan(2));
    });

    test('open lê o conteúdo; close não apaga o arquivo do usuário', () async {
      final f = File('${dir.path}/a.pdf')..writeAsBytesSync([1, 2, 3]);
      final fs = DeviceFolderFileSystem();
      final entry = (await fs.list(SamsungFolder(path: dir.path))).single;
      final src = await fs.open(SamsungFolder(path: dir.path), entry);
      expect(src.size, 3);
      final bytes = <int>[];
      await for (final c in src.read()) {
        bytes.addAll(c);
      }
      expect(bytes, [1, 2, 3]);
      await src.close();
      expect(f.existsSync(), isTrue);
    });

    test('pasta que não existe vira FolderAccessException com mensagem para o usuário', () async {
      final fs = DeviceFolderFileSystem();
      await expectLater(
        fs.list(SamsungFolder(path: '${dir.path}/nao-existe')),
        throwsA(isA<FolderAccessException>().having((e) => e.message, 'message', contains('pasta'))),
      );
    });

    test('pasta por URI usa o seletor do Android (SAF) e a cópia temporária é apagada ao fechar', () async {
      final platform = FakePlatform();
      final tmp = File('${dir.path}/copia.pdf')..writeAsBytesSync([7, 8, 9]);
      platform.tree = [SyncEntry(id: 'content://doc/1', name: 'a.pdf', size: 3, modified: DateTime(2026))];
      platform.cache = {'content://doc/1': tmp.path};
      final fs = DeviceFolderFileSystem(platform: platform);
      const folder = SamsungFolder(uri: 'content://com.android.externalstorage.documents/tree/primary%3ANotas');
      final entries = await fs.list(folder);
      expect(platform.listed, [folder.uri]);
      final src = await fs.open(folder, entries.single);
      expect(src.size, 3);
      expect(await src.read().expand((c) => c).toList(), [7, 8, 9]);
      await src.close();
      expect(tmp.existsSync(), isFalse);
    });

    test('URI sem o canal (segundo plano) cai no caminho equivalente quando existe', () async {
      final platform = FakePlatform()..throwMissing = true;
      // O "armazenamento" fica no diretório temporário: simulamos um uri cujo caminho aponta para ele.
      File('${dir.path}/a.pdf').writeAsBytesSync([1]);
      final fs = DeviceFolderFileSystem(platform: platform, uriToPathOverride: (_) => dir.path);
      final entries = await fs.list(const SamsungFolder(uri: 'content://x/tree/y'));
      expect(entries.single.name, 'a.pdf');
    });

    test('URI sem o canal e sem caminho equivalente: erro orientando abrir o app', () async {
      final platform = FakePlatform()..throwMissing = true;
      final fs = DeviceFolderFileSystem(platform: platform);
      await expectLater(
        fs.list(const SamsungFolder(uri: 'content://com.google.android.apps.docs.storage/tree/x')),
        throwsA(isA<FolderAccessException>()),
      );
    });
  });
}
