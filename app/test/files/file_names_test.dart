import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/files/file_names.dart';

void main() {
  group('safeFileName', () {
    test('mantém nomes comuns e troca separadores e caracteres de controle', () {
      expect(safeFileName('Aula (2026-10-13).sdocx'), 'Aula (2026-10-13).sdocx');
      expect(safeFileName('a/b\\c.pdf'), 'a_b_c.pdf');
      expect(safeFileName('x\u0000y\n.pdf'), 'x_y_.pdf');
      expect(safeFileName('Relatório: final?.docx'), 'Relatório_ final_.docx');
    });

    test('sem pontos iniciais nem ".." (não escapa da pasta, não vira arquivo oculto)', () {
      expect(safeFileName('.oculto.pdf'), 'oculto.pdf');
      expect(safeFileName('../../etc/passwd'), '_._etc_passwd');
      expect(safeFileName('...'), 'arquivo');
      expect(safeFileName('..'), 'arquivo');
      expect(safeFileName(''), 'arquivo');
      expect(safeFileName('   '), 'arquivo');
    });

    test('nunca contém separador de caminho nem ".."', () {
      for (final n in ['../../x', r'..\..\x', 'a/../b', '/abs/olute', 'C:\\x']) {
        final s = safeFileName(n);
        expect(s.contains('/'), isFalse, reason: n);
        expect(s.contains('\\'), isFalse, reason: n);
        expect(s.contains('..'), isFalse, reason: n);
        expect(s.startsWith('.'), isFalse, reason: n);
      }
    });

    test('limita o tamanho preservando a extensão', () {
      final long = safeFileName('${'x' * 300}.pdf');
      expect(long.length, 120);
      expect(long.endsWith('.pdf'), isTrue);
      final noExt = safeFileName('y' * 300);
      expect(noExt.length, 120);
    });
  });

  group('mimeForFile', () {
    test('usa o tipo do Drive quando é específico', () {
      expect(mimeForFile('a.bin', 'application/pdf'), 'application/pdf');
      expect(mimeForFile('a.pdf', 'Application/PDF'), 'application/pdf');
    });

    test('tipo genérico ou vazio: decide pela extensão', () {
      expect(mimeForFile('Aula.PDF', 'application/octet-stream'), 'application/pdf');
      expect(mimeForFile('trab.docx', ''), 'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
      expect(mimeForFile('foto.jpeg', null), 'image/jpeg');
      expect(mimeForFile('foto.png', null), 'image/png');
      expect(mimeForFile('notas.txt', null), 'text/plain');
      expect(mimeForFile('dados.xlsx', null), 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    });

    test('extensão desconhecida (inclusive .sdocx): binário opaco; nunca curinga nem tipo malformado', () {
      expect(mimeForFile('Aula.sdocx', null), 'application/octet-stream');
      expect(mimeForFile('arquivo.xyz', null), 'application/octet-stream');
      expect(mimeForFile('sem-extensao', null), 'application/octet-stream');
      expect(mimeForFile('a.pdf', '*/*'), 'application/pdf');
      expect(mimeForFile('a.bin', 'texto solto'), 'application/octet-stream');
      expect(mimeForFile('a.bin', 'text/*'), 'application/octet-stream');
    });
  });
}
