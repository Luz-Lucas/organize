import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/update/update_installer.dart';
import 'package:organizacional/update/windows_update_installer.dart';

void main() {
  late Directory root;
  late Directory app;
  late Directory temp;
  late List<(String, List<String>)> started;

  setUp(() {
    root = Directory.systemTemp.createTempSync('upd-win-');
    app = Directory('${root.path}/Organize')..createSync();
    File('${app.path}/organizacional.exe').writeAsStringSync('velho');
    temp = Directory('${root.path}/Temp')..createSync();
    started = [];
  });
  tearDown(() => root.deleteSync(recursive: true));

  WindowsUpdateInstaller installer({int pid = 4321}) => WindowsUpdateInstaller(
        executable: '${app.path}/organizacional.exe',
        pid: pid,
        scriptRoot: temp,
        updatesDir: Directory('${root.path}/updates'),
        start: (exe, args) async => started.add((exe, args)),
      );

  File zip(List<ArchiveFile> files) {
    final a = Archive();
    for (final f in files) {
      a.add(f);
    }
    return File('${root.path}/pacote.zip')..writeAsBytesSync(ZipEncoder().encode(a));
  }

  List<ArchiveFile> good() => [
        ArchiveFile.bytes('organizacional.exe', [1, 2, 3]),
        ArchiveFile.bytes('data/flutter_assets/a.json', [123, 125]),
        ArchiveFile.bytes('plugins/x.dll', [9]),
      ];

  test('é a plataforma windows; a pasta de download fica em %LOCALAPPDATA%', () async {
    final i = WindowsUpdateInstaller(executable: r'C:\a\organizacional.exe', env: {'LOCALAPPDATA': r'C:\Users\u\AppData\Local'});
    expect(i.platform, 'windows');
    expect(i.supported, isTrue);
    expect((await i.downloadDir()).path, r'C:\Users\u\AppData\Local\Organize\updates');
  });

  test('extrai na pasta irmã .new e gera o .cmd que espera o PID, troca com move e relança o exe', () async {
    final out = await installer().install(zip(good()));
    expect(out.result, InstallResult.restarting);

    final staging = '${app.path}.new';
    expect(File('$staging/organizacional.exe').readAsBytesSync(), [1, 2, 3]);
    expect(File('$staging/data/flutter_assets/a.json').readAsBytesSync(), [123, 125]);
    expect(File('${app.path}/organizacional.exe').readAsStringSync(), 'velho', reason: 'pasta atual intacta');

    final (exe, args) = started.single;
    expect(exe.toLowerCase(), contains('cmd'));
    final script = File(args.last);
    expect(script.path.endsWith('.cmd'), isTrue);
    expect(script.path.startsWith(temp.path), isTrue);
    final text = script.readAsStringSync();
    expect(text, contains('tasklist'));
    expect(text, contains('timeout'));
    expect(text, contains('move'));
    expect(text, contains('4321'));
    expect(text, contains('organizacional.exe'));
    expect(text, contains(r'.old'));
    expect(text, contains('start ""'));
    expect(text, contains(app.path.replaceAll('/', r'\')));
    expect(text, contains(staging.replaceAll('/', r'\')));
  });

  test('o script protege contra % nos caminhos (%% em .cmd)', () async {
    final weird = Directory('${root.path}/100%Org')..createSync();
    File('${weird.path}/organizacional.exe').writeAsStringSync('v');
    final i = WindowsUpdateInstaller(
      executable: '${weird.path}/organizacional.exe',
      pid: 1,
      scriptRoot: temp,
      updatesDir: Directory('${root.path}/updates'),
      start: (e, a) async => started.add((e, a)),
    );
    expect((await i.install(zip(good()))).result, InstallResult.restarting);
    final text = File(started.single.$2.last).readAsStringSync();
    expect(text, contains('100%%Org'));
  });

  for (final c in {
    'caminho absoluto': () => zip([ArchiveFile.bytes(r'C:\Windows\evil.dll', [1])]),
    'barra absoluta': () => zip([ArchiveFile.bytes('/evil', [1])]),
    'com ..': () => zip([ArchiveFile.bytes('../evil.exe', [1])]),
    'com .. e barra invertida': () => zip([ArchiveFile.bytes(r'a\..\..\evil.exe', [1])]),
    'link simbólico': () => zip([ArchiveFile.bytes('link', '/etc'.codeUnits)..mode = 0xA1FF]),
  }.entries) {
    test('recusa pacote com entrada insegura (${c.key}) sem tocar em nada', () async {
      final out = await installer().install(c.value());
      expect(out.result, InstallResult.failed);
      expect(out.message, contains('inseguro'));
      expect(Directory('${app.path}.new').existsSync(), isFalse);
      expect(started, isEmpty);
      expect(File('${root.path}/evil.exe').existsSync(), isFalse);
      expect(File('${root.path}/evil').existsSync(), isFalse);
    });
  }

  test('pacote sem o .exe do app é recusado e a pasta .new é limpa', () async {
    final out = await installer().install(zip([ArchiveFile.bytes('data/x', [1])]));
    expect(out.result, InstallResult.failed);
    expect(Directory('${app.path}.new').existsSync(), isFalse);
    expect(started, isEmpty);
  });

  test('arquivo que não é zip vira falha com mensagem', () async {
    final f = File('${root.path}/lixo.zip')..writeAsStringSync('isto não é um zip');
    final out = await installer().install(f);
    expect(out.result, InstallResult.failed);
    expect(started, isEmpty);
  });
}
