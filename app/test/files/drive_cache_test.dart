import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/domain/drive.dart';
import 'package:organizacional/files/drive_cache.dart';

DriveFileMeta _meta(String id, {String name = 'Edital.pdf', String? md5 = 'aa', int size = 3, DateTime? at}) =>
    DriveFileMeta(id: id, name: name, mimeType: 'application/pdf', size: size, modifiedTime: at ?? DateTime.utc(2026, 10, 12), md5: md5);

void main() {
  late Directory tmp;
  late String root;
  var clock = DateTime.utc(2026, 10, 13, 8);

  DriveCache cache({int maxBytes = driveCacheMaxBytes}) => DriveCache.at(root, now: () => clock, maxBytes: maxBytes);

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('drive_cache_test');
    root = '${tmp.path}/drive_cache';
    clock = DateTime.utc(2026, 10, 13, 8);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('store grava em <raiz>/<id>/<nome seguro> e o índice guarda nome, tamanho, data, md5, caminho e último uso', () async {
    final c = cache();
    final f = await c.store(_meta('F1', name: 'Edital/final.pdf'), [1, 2, 3]);
    expect(f.path, '$root/F1/Edital_final.pdf');
    expect(File(f.path).readAsBytesSync(), [1, 2, 3]);
    final index = jsonDecode(File('$root/index.json').readAsStringSync()) as Map;
    final e = index['F1'] as Map;
    expect(e['name'], 'Edital/final.pdf');
    expect(e['size'], 3);
    expect(e['md5'], 'aa');
    expect(e['modifiedTime'], '2026-10-12T00:00:00.000Z');
    expect(e['path'], 'F1/Edital_final.pdf');
    expect(e['lastOpened'], '2026-10-13T08:00:00.000Z');
  });

  test('lookup devolve o que foi guardado, inclusive em outra instância (persistente)', () async {
    await cache().store(_meta('F1'), [1, 2, 3]);
    final again = await cache().lookup('F1');
    expect(again, isNotNull);
    expect(again!.size, 3);
    expect(again.md5, 'aa');
    expect(again.toMeta().sameContentAs(_meta('F1')), isTrue);
    expect(again.toMeta().sameContentAs(_meta('F1', md5: 'bb')), isFalse);
    expect(await cache().lookup('OUTRO'), isNull);
  });

  test('arquivo apagado por fora: lookup esquece a entrada', () async {
    final c = cache();
    final f = await c.store(_meta('F1'), [1, 2, 3]);
    File(f.path).deleteSync();
    expect(await c.lookup('F1'), isNull);
    final index = jsonDecode(File('$root/index.json').readAsStringSync()) as Map;
    expect(jsonEncode(index).contains('F1'), isFalse);
  });

  test('índice adulterado com caminho fora da raiz é ignorado', () async {
    File('${tmp.path}/segredo.txt').writeAsStringSync('x');
    Directory(root).createSync(recursive: true);
    File('$root/index.json').writeAsStringSync(jsonEncode({
      'F1': {'name': 'a.pdf', 'size': 1, 'path': '../segredo.txt', 'lastOpened': '2026-10-13T08:00:00Z'},
      'F2': {'name': 'a.pdf', 'size': 1, 'path': '/etc/passwd', 'lastOpened': '2026-10-13T08:00:00Z'},
    }));
    expect(await cache().lookup('F1'), isNull);
    expect(await cache().lookup('F2'), isNull);
  });

  test('link simbólico no lugar do arquivo (ou da pasta do id) não é seguido', () async {
    final c = cache();
    final f = await c.store(_meta('F1'), [1, 2, 3]);
    final outside = File('${tmp.path}/fora.txt')..writeAsStringSync('privado');
    File(f.path).deleteSync();
    try {
      Link(f.path).createSync(outside.path);
    } on FileSystemException {
      return; // sistema sem symlink
    }
    expect(await c.lookup('F1'), isNull);

    // pasta do id virando link para fora
    await c.store(_meta('F2'), [9]);
    final dir = Directory('$root/F2');
    final outDir = Directory('${tmp.path}/pasta_fora')..createSync();
    File('${outDir.path}/Edital.pdf').writeAsBytesSync([7]);
    dir.deleteSync(recursive: true);
    Link(dir.path).createSync(outDir.path);
    expect(await c.lookup('F2'), isNull);
  });

  test('id inválido: store recusa e lookup devolve null, sem tocar no disco', () async {
    final c = cache();
    for (final bad in ['../x', 'a/b', '', '.', '..', 'a b']) {
      await expectLater(c.store(_meta(bad), [1]), throwsArgumentError, reason: bad);
      expect(await c.lookup(bad), isNull, reason: bad);
    }
    expect(Directory(root).existsSync() ? Directory(root).listSync().where((e) => !e.path.endsWith('index.json')) : const [], isEmpty);
  });

  test('guardar de novo (arquivo mudou/renomeado) troca a cópia antiga', () async {
    final c = cache();
    final old = await c.store(_meta('F1', name: 'v1.pdf', md5: 'aa'), [1, 2, 3]);
    final nova = await c.store(_meta('F1', name: 'v2.pdf', md5: 'bb', size: 4), [1, 2, 3, 4]);
    expect(File(old.path).existsSync(), isFalse);
    expect(File(nova.path).readAsBytesSync(), [1, 2, 3, 4]);
    expect((await c.lookup('F1'))!.md5, 'bb');
    expect(await c.totalBytes(), 4);
  });

  test('markOpened atualiza o último uso', () async {
    final c = cache();
    await c.store(_meta('F1'), [1]);
    clock = DateTime.utc(2026, 10, 14, 9);
    await c.markOpened('F1');
    expect((await c.lookup('F1'))!.lastOpened, DateTime.utc(2026, 10, 14, 9));
    await c.markOpened('NADA'); // não falha
  });

  test('totalBytes soma os arquivos; clear apaga tudo e a cache continua utilizável', () async {
    final c = cache();
    await c.store(_meta('F1'), [1, 2, 3]);
    await c.store(_meta('F2', name: 'b.pdf'), [1, 2, 3, 4, 5]);
    expect(await c.totalBytes(), 8);
    await c.clear();
    expect(await c.totalBytes(), 0);
    expect(await c.lookup('F1'), isNull);
    expect(File('$root/F1/Edital.pdf').existsSync(), isFalse);
    final again = await c.store(_meta('F1'), [1]);
    expect(File(again.path).existsSync(), isTrue);
  });

  test('totalBytes de cache que nunca existiu é 0; índice corrompido vira cache vazia', () async {
    expect(await cache().totalBytes(), 0);
    Directory(root).createSync(recursive: true);
    File('$root/index.json').writeAsStringSync('{ isso não é json');
    final c = cache();
    expect(await c.lookup('F1'), isNull);
    await c.store(_meta('F1'), [1]);
    expect((await c.lookup('F1'))!.size, 1);
  });

  test('acima do limite remove os menos usados, nunca o que acabou de ser guardado', () async {
    final c = cache(maxBytes: 10);
    await c.store(_meta('A', name: 'a.pdf'), [0, 0, 0, 0]); // 08:00
    clock = clock.add(const Duration(hours: 1));
    await c.store(_meta('B', name: 'b.pdf'), [0, 0, 0, 0]); // 09:00
    clock = clock.add(const Duration(hours: 1));
    await c.markOpened('A'); // A passa a ser a mais recente; B vira a menos usada
    clock = clock.add(const Duration(hours: 1));
    await c.store(_meta('C', name: 'c.pdf'), [0, 0, 0, 0]); // 12 bytes > 10: sai B
    expect(await c.lookup('B'), isNull);
    expect(await c.lookup('A'), isNotNull);
    expect(await c.lookup('C'), isNotNull);
    expect(await c.totalBytes(), 8);
    expect(Directory('$root/B').existsSync(), isFalse);
  });

  test('um arquivo maior que o limite sozinho continua guardado (só ele)', () async {
    final c = cache(maxBytes: 2);
    await c.store(_meta('A', name: 'a.pdf'), [1]);
    await c.store(_meta('B', name: 'b.pdf'), [1, 2, 3, 4]);
    expect(await c.lookup('A'), isNull);
    expect(await c.lookup('B'), isNotNull);
  });

  test('o limite padrão é 1 GB', () {
    expect(driveCacheMaxBytes, 1024 * 1024 * 1024);
  });

  test('gravações em paralelo não perdem entradas do índice', () async {
    final c = cache();
    await Future.wait([
      for (var i = 0; i < 8; i++) c.store(_meta('F$i', name: 'f$i.pdf'), [i]),
    ]);
    for (var i = 0; i < 8; i++) {
      expect(await c.lookup('F$i'), isNotNull, reason: 'F$i');
    }
  });

  test('sem pasta raiz disponível (resolver devolve null): lookup vazio e store falha com DriveCacheUnavailable', () async {
    final c = DriveCache.lazy(() async => null);
    expect(await c.lookup('F1'), isNull);
    expect(await c.totalBytes(), 0);
    await expectLater(c.store(_meta('F1'), [1]), throwsA(isA<DriveCacheUnavailable>()));
    await c.clear(); // não falha
  });
}
