import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/features/samsung_notes/sync_lock.dart';

void main() {
  test('MemorySyncLock: uma execução por vez', () async {
    final lock = MemorySyncLock();
    expect(await lock.tryAcquire(), isTrue);
    expect(await lock.tryAcquire(), isFalse);
    await lock.release();
    expect(await lock.tryAcquire(), isTrue);
  });

  group('FileSyncLock', () {
    late Directory dir;
    late File file;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('sync_lock_test');
      file = File('${dir.path}/samsung.lock');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('duas instâncias (dois isolates) não adquirem ao mesmo tempo', () async {
      final a = FileSyncLock(file);
      final b = FileSyncLock(file);
      expect(await a.tryAcquire(), isTrue);
      expect(await b.tryAcquire(), isFalse);
      await a.release();
      expect(await b.tryAcquire(), isTrue);
      await b.release();
      expect(file.existsSync(), isFalse);
    });

    test('trava antiga (processo morto) é retomada depois do prazo', () async {
      final now = DateTime(2026, 10, 13, 10);
      final old = FileSyncLock(file, now: () => now, staleAfter: const Duration(minutes: 10));
      expect(await old.tryAcquire(), isTrue);
      // 11 minutos depois, outro processo acha a trava velha e a assume.
      final later = FileSyncLock(file, now: () => now.add(const Duration(minutes: 11)), staleAfter: const Duration(minutes: 10));
      expect(await later.tryAcquire(), isTrue);
      // ...mas dentro do prazo não.
      final soon = FileSyncLock(file, now: () => now.add(const Duration(minutes: 12)), staleAfter: const Duration(minutes: 10));
      expect(await soon.tryAcquire(), isFalse);
    });

    test('release sem ter adquirido não apaga a trava de outro', () async {
      final a = FileSyncLock(file);
      final b = FileSyncLock(file);
      expect(await a.tryAcquire(), isTrue);
      await b.release();
      expect(file.existsSync(), isTrue);
    });
  });
}
