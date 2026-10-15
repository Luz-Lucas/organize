@TestOn('linux')
library;

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/update/linux_update_installer.dart';
import 'package:organizacional/update/update_installer.dart';

void main() {
  late Directory root;
  late Directory app; // <root>/opt/organizacional
  late Directory scripts;
  late List<(String, List<String>)> started;

  setUp(() {
    root = Directory.systemTemp.createTempSync('upd-linux-');
    app = Directory('${root.path}/opt/organizacional')..createSync(recursive: true);
    File('${app.path}/organizacional').writeAsStringSync('#!/bin/sh\necho velho > "\$(dirname "\$0")/quem"\n');
    File('${app.path}/velho.txt').writeAsStringSync('velho');
    scripts = Directory('${root.path}/tmp')..createSync();
    started = [];
  });
  tearDown(() => root.deleteSync(recursive: true));

  LinuxUpdateInstaller installer({int pid = 2147480000}) => LinuxUpdateInstaller(
        executable: '${app.path}/organizacional',
        pid: pid,
        scriptRoot: scripts,
        updatesDir: Directory('${root.path}/updates'),
        start: (exe, args) async => started.add((exe, args)),
      );

  /// Empacota com o `tar` do sistema, como o release.sh faz.
  File realTarball() {
    final src = Directory('${root.path}/src')..createSync();
    File('${src.path}/organizacional').writeAsStringSync('#!/bin/sh\necho novo > "\$(dirname "\$0")/quem"\n');
    Process.runSync('chmod', ['755', '${src.path}/organizacional']);
    Directory('${src.path}/data').createSync();
    File('${src.path}/data/versao.txt').writeAsStringSync('novo');
    final out = File('${root.path}/pacote.tar.gz');
    final r = Process.runSync('tar', ['-czf', out.path, '-C', src.path, '.']);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    return out;
  }

  File craftedTarball(List<ArchiveFile> files) {
    final archive = Archive();
    for (final f in files) {
      archive.add(f);
    }
    final bytes = GZipEncoder().encode(TarEncoder().encodeBytes(archive));
    return File('${root.path}/ruim.tar.gz')..writeAsBytesSync(bytes);
  }

  test('é a plataforma linux; a pasta de download fica no cache do usuário', () async {
    final i = LinuxUpdateInstaller(executable: '/x/organizacional', env: {'HOME': '/home/u'});
    expect(i.platform, 'linux');
    expect(i.supported, isTrue);
    expect((await i.downloadDir()).path, '/home/u/.cache/organizacional/updates');
    final j = LinuxUpdateInstaller(executable: '/x/organizacional', env: {'HOME': '/home/u', 'XDG_CACHE_HOME': '/c'});
    expect((await j.downloadDir()).path, '/c/organizacional/updates');
  });

  test('extrai na pasta irmã .new, escreve o script com 700 e o dispara com os argumentos certos', () async {
    final out = await installer(pid: 4242).install(realTarball());
    expect(out.result, InstallResult.restarting);

    final staging = Directory('${app.path}.new');
    expect(File('${staging.path}/data/versao.txt').readAsStringSync(), 'novo');
    expect(File('${staging.path}/organizacional').existsSync(), isTrue);
    // A pasta atual segue intacta até o app sair.
    expect(File('${app.path}/velho.txt').existsSync(), isTrue);

    expect(started, hasLength(1));
    final (exe, args) = started.single;
    expect(exe, '/bin/sh');
    final script = File(args.first);
    expect(script.path.startsWith(scripts.path), isTrue);
    expect(script.statSync().mode & 511, 448, reason: 'permissão 700');
    expect(script.parent.statSync().mode & 511, 448, reason: 'pasta do script também 700');
    expect(args.sublist(1), ['4242', app.path, '${app.path}.new', 'organizacional', script.parent.path]);
    final text = script.readAsStringSync();
    expect(text, contains('kill -0'));
    expect(text, contains('.old'));
  });

  test('o script espera o PID sair, troca as pastas, apaga a .old e relança o app novo', () async {
    // PID inexistente: o script segue direto para a troca.
    await installer().install(realTarball());
    final (exe, args) = started.single;
    final r = await Process.run(exe, args);
    expect(r.exitCode, 0, reason: '${r.stderr}');

    // O relançamento é em segundo plano: espera o novo executável gravar `quem`.
    final quem = File('${app.path}/quem');
    for (var i = 0; i < 50 && !quem.existsSync(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(quem.readAsStringSync().trim(), 'novo');
    expect(File('${app.path}/data/versao.txt').readAsStringSync(), 'novo');
    expect(File('${app.path}/velho.txt').existsSync(), isFalse);
    expect(Directory('${app.path}.old').existsSync(), isFalse);
    expect(Directory('${app.path}.new').existsSync(), isFalse);
    expect(Directory(args.last).existsSync(), isFalse, reason: 'o script se apaga');
  });

  test('o script espera o app sair de verdade antes de trocar', () async {
    final sleeper = await Process.start('sleep', ['30']);
    addTearDown(sleeper.kill);
    await installer(pid: sleeper.pid).install(realTarball());
    final (exe, args) = started.single;
    final run = Process.start(exe, args);
    final proc = await run;
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    expect(File('${app.path}/velho.txt').existsSync(), isTrue, reason: 'ainda não trocou');
    sleeper.kill();
    await sleeper.exitCode; // colhido: um zumbi ainda responderia ao kill -0
    expect(await proc.exitCode.timeout(const Duration(seconds: 30)), 0);
    expect(File('${app.path}/velho.txt').existsSync(), isFalse);
  });

  for (final c in {
    'caminho absoluto': () => craftedTarball([ArchiveFile.bytes('/tmp/organize-evil', [1])]),
    'com ..': () => craftedTarball([ArchiveFile.bytes('../evil', [1])]),
    'com .. no meio': () => craftedTarball([ArchiveFile.bytes('data/../../evil', [1])]),
    'link simbólico': () => craftedTarball([ArchiveFile.symlink('organizacional', '/etc/passwd')]),
  }.entries) {
    test('recusa pacote com entrada insegura (${c.key}) sem tocar em nada', () async {
      final out = await installer().install(c.value());
      expect(out.result, InstallResult.failed);
      expect(out.message, contains('inseguro'));
      expect(Directory('${app.path}.new').existsSync(), isFalse);
      expect(started, isEmpty);
      expect(File('${app.path}/velho.txt').existsSync(), isTrue);
      expect(File('${root.path}/opt/evil').existsSync(), isFalse);
      expect(File('${root.path}/evil').existsSync(), isFalse);
    });
  }

  test('pacote sem o executável do app é recusado e a pasta .new é limpa', () async {
    final out = await installer().install(craftedTarball([ArchiveFile.bytes('data/x.txt', [1, 2])]));
    expect(out.result, InstallResult.failed);
    expect(Directory('${app.path}.new').existsSync(), isFalse);
    expect(started, isEmpty);
  });

  test('arquivo que não é tar.gz vira falha com mensagem', () async {
    final f = File('${root.path}/lixo.tar.gz')..writeAsStringSync('isto não é um tar');
    final out = await installer().install(f);
    expect(out.result, InstallResult.failed);
    expect(started, isEmpty);
  });

  test('sobra de uma tentativa anterior (.new) é substituída', () async {
    Directory('${app.path}.new').createSync();
    File('${app.path}.new/lixo').writeAsStringSync('x');
    final out = await installer().install(realTarball());
    expect(out.result, InstallResult.restarting);
    expect(File('${app.path}.new/lixo').existsSync(), isFalse);
  });
}
