import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/update/app_release.dart';

void main() {
  test('AppRelease.fromJson lê a linha de app_releases', () {
    final r = AppRelease.fromJson({
      'id': 'r1',
      'platform': 'android',
      'version': '1.2.0',
      'build': 7,
      'storage_path': 'android/7/organizacional-1.2.0+7.apk',
      'sha256': 'a' * 64,
      'size_bytes': 12345,
      'notes': 'Caderno novo',
      'created_at': '2026-10-27T12:00:00Z',
    });
    expect(r.version, '1.2.0');
    expect(r.build, 7);
    expect(r.sizeBytes, 12345);
    expect(r.notes, 'Caderno novo');
    expect(r.fileName, 'organizacional-1.2.0+7.apk');
  });

  test('notes nulo vira texto vazio e size_bytes aceita número como double/string', () {
    final r = AppRelease.fromJson({
      'id': 'r1', 'platform': 'linux', 'version': '1.0.0', 'build': 1,
      'storage_path': 'linux/1/x.tar.gz', 'sha256': 'b' * 64, 'size_bytes': '99', 'notes': null,
    });
    expect(r.notes, '');
    expect(r.sizeBytes, 99);
  });

  test('InstalledVersion guarda rótulo e build', () {
    final v = InstalledVersion('1.4.2', 12);
    expect(v.label, '1.4.2');
    expect(v.build, 12);
  });
}
