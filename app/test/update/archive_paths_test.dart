import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/update/archive_paths.dart';

void main() {
  group('isSafeArchivePath', () {
    test('aceita caminhos relativos comuns, com ./ na frente e pastas', () {
      for (final ok in ['organizacional', './organizacional', 'data/flutter_assets/a.json', './lib/libapp.so', 'lib/']) {
        expect(isSafeArchivePath(ok), isTrue, reason: ok);
      }
    });

    test('recusa caminho absoluto (Linux e Windows)', () {
      for (final bad in ['/etc/passwd', r'\Windows\x.dll', r'C:\Windows\x.dll', 'C:/x.dll', 'c:x.dll']) {
        expect(isSafeArchivePath(bad), isFalse, reason: bad);
      }
    });

    test('recusa .. em qualquer posição e em qualquer separador', () {
      for (final bad in ['../x', 'a/../../x', 'a/..', r'a\..\x', '..', './../x', 'a/b/../../../c']) {
        expect(isSafeArchivePath(bad), isFalse, reason: bad);
      }
    });

    test('aceita nomes que só contêm pontos dentro do nome (não é componente ..)', () {
      expect(isSafeArchivePath('a/b..c/d'), isTrue);
      expect(isSafeArchivePath('..hidden/x'), isTrue);
    });

    test('recusa vazio, byte nulo e fluxo alternativo de dados do NTFS', () {
      for (final bad in ['', '\u0000', 'a\u0000b', 'a.txt:stream', '//server/share']) {
        expect(isSafeArchivePath(bad), isFalse, reason: bad);
      }
    });
  });

  test('validateArchiveEntries devolve a primeira entrada insegura', () {
    expect(validateArchiveEntries(['a', './b/c', 'd/']), isNull);
    expect(validateArchiveEntries(['a', '../b', '/c']), '../b');
  });
}
