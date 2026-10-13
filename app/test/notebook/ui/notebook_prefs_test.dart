import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/core/notebook_core.dart';
import 'package:organizacional/notebook/ui/notebook_prefs.dart';
import 'package:organizacional/notebook/ui/tool_settings.dart';
import 'package:organizacional/ui/org_theme.dart';

void main() {
  final org = orgThemes.first;

  group('padrão', () {
    test('3 canetas (preta média, azul média, marca-texto amarelo) e modo compacto', () {
      final p = NotebookPrefs.fromMap(const {});
      expect(p.compact, isTrue);
      expect(p.pens.map((e) => e.tool), [PenTool.pen, PenTool.pen, PenTool.highlighter]);
      expect(p.pens[0].argb, isNull); // preta = cor de tinta do tema
      expect(p.pens[1].argb, 0xFF60A5FA);
      expect(p.pens[2].argb, 0xFFFBBF24);
      expect(p.pens.every((e) => e.widthIndex == 1), isTrue);
    });

    test('5 cores favoritas vêm do tema enquanto não houver personalização', () {
      final p = NotebookPrefs.fromMap(const {});
      expect(p.colorsFor(org), notebookPalette(org).take(5).map((c) => c.toARGB32()).toList());
    });
  });

  group('JSON', () {
    test('ida e volta preserva canetas, cores e modo', () {
      final p = NotebookPrefs.fromMap(const {})
          .addPen(const FavoritePen(tool: PenTool.pencil, argb: 0xFFF2726B, widthIndex: 3))
          .addColor(0xFF123456, org)
          .withCompact(false);
      final m = p.toMap();
      expect(m['v'], 1);
      expect(m['compact'], false);
      expect((m['pens'] as List).last, {'tool': 'pencil', 'argb': 0xFFF2726B, 'width': kPenWidths[3]});
      final back = NotebookPrefs.fromMap(m);
      expect(back.pens, p.pens);
      expect(back.colorsFor(org), p.colorsFor(org));
      expect(back.compact, isFalse);
    });

    test('lixo é ignorado: ferramenta desconhecida, tipos errados, excesso além de 8', () {
      final p = NotebookPrefs.fromMap({
        'v': 1,
        'pens': [
          {'tool': 'giz', 'argb': 1, 'width': 3.0},
          'oi',
          {'tool': 'pen', 'argb': 'x', 'width': 'y'},
          for (var i = 0; i < 12; i++) {'tool': 'pen', 'argb': 0xFF000000 + i, 'width': 5.0},
        ],
        'colors': [for (var i = 0; i < 12; i++) 0xFF000000 + i, 'z'],
        'compact': 'sim',
      });
      expect(p.pens, hasLength(8));
      expect(p.pens.first.argb, isNull); // argb inválido vira "cor do tema"
      expect(p.pens.first.widthIndex, 1); // largura inválida vira a média
      expect(p.colorsFor(org), hasLength(8));
      expect(p.compact, isTrue);
    });

    test('largura é mapeada para a espessura mais próxima', () {
      final p = NotebookPrefs.fromMap({
        'pens': [
          {'tool': 'pen', 'width': 14.0},
          {'tool': 'pen', 'width': 1.4},
        ],
      });
      expect(p.pens.map((e) => e.widthIndex), [4, 0]);
    });

    test('lista de canetas vazia gravada pelo usuário continua vazia', () {
      final p = NotebookPrefs.fromMap({'v': 1, 'pens': <Object>[], 'colors': <Object>[]});
      expect(p.pens, isEmpty);
      expect(p.colorsFor(org), isEmpty);
    });
  });

  group('edição', () {
    const pen = FavoritePen(tool: PenTool.fountain, argb: 0xFF010203, widthIndex: 2);

    test('adicionar respeita o limite de 8 e não duplica', () {
      var p = NotebookPrefs.fromMap(const {});
      expect(p.addPen(p.pens.first).pens, hasLength(3)); // duplicada: ignora
      for (var i = 0; i < 10; i++) {
        p = p.addPen(FavoritePen(tool: PenTool.pen, argb: 0xFF000100 + i, widthIndex: 0));
      }
      expect(p.pens, hasLength(kMaxFavoritePens));
      expect(p.canAddPen, isFalse);
      expect(p.addPen(pen).pens, hasLength(kMaxFavoritePens));
    });

    test('cores: limite de 8, sem duplicar, remoção a partir do padrão do tema', () {
      var p = NotebookPrefs.fromMap(const {});
      final first = p.colorsFor(org).first;
      expect(p.addColor(first, org).colorsFor(org), hasLength(5));
      p = p.removeColorAt(0, org);
      expect(p.colorsFor(org), hasLength(4));
      for (var i = 0; i < 10; i++) {
        p = p.addColor(0xFF000100 + i, org);
      }
      expect(p.colorsFor(org), hasLength(kMaxFavoriteColors));
      expect(p.canAddColor(org), isFalse);
    });

    test('remover, trocar e reordenar canetas', () {
      var p = NotebookPrefs.fromMap(const {});
      final a = p.pens[0], b = p.pens[1], c = p.pens[2];
      expect(p.removePenAt(1).pens, [a, c]);
      expect(p.replacePenAt(1, pen).pens, [a, pen, c]);
      // [to] é a posição final (convenção do ReorderableListView.onReorderItem)
      expect(p.movePen(0, 2).pens, [b, c, a]);
      expect(p.movePen(2, 0).pens, [c, a, b]);
      expect(p.movePen(1, 1).pens, [a, b, c]);
      expect(p.movePen(0, 9).pens, [b, c, a]); // fora do intervalo: vai para o fim
    });
  });
}
