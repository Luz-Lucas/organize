import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/update/app_release.dart';

void main() {
  group('InstalledVersion.fromPackageInfo', () {
    test('Android com APK por ABI: tira o deslocamento de 1000 * ABI que o Flutter soma ao versionCode', () {
      // Flutter: versionCode = abi * 1000 + build (armeabi-v7a=1, arm64-v8a=2, x86_64=4).
      expect(InstalledVersion.fromPackageInfo('1.0.0', '2001', android: true).build, 1);
      expect(InstalledVersion.fromPackageInfo('1.0.3', '2007', android: true).build, 7);
      expect(InstalledVersion.fromPackageInfo('1.0.3', '1007', android: true).build, 7);
      expect(InstalledVersion.fromPackageInfo('1.0.3', '4007', android: true).build, 7);
    });

    test('Android com APK universal (debug) já traz o build puro', () {
      expect(InstalledVersion.fromPackageInfo('1.0.3', '7', android: true).build, 7);
    });

    test('Linux e Windows usam o número de build como está', () {
      expect(InstalledVersion.fromPackageInfo('1.0.3', '7', android: false).build, 7);
      expect(InstalledVersion.fromPackageInfo('1.0.3', '2001', android: false).build, 2001);
    });

    test('build ilegível vira 0 (qualquer release publicada é mais nova)', () {
      expect(InstalledVersion.fromPackageInfo('1.0.0', '', android: false).build, 0);
      expect(InstalledVersion.fromPackageInfo('1.0.0', 'x', android: true).build, 0);
    });

    test('o rótulo é a versão X.Y.Z', () {
      expect(InstalledVersion.fromPackageInfo('1.2.3', '5', android: false).label, '1.2.3');
    });
  });
}
