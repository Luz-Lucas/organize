/// "Endireitar": por linha, gira a baseline para a horizontal, normaliza a
/// altura-x das palavras e iguala o espaçamento entre elas.
library;

import 'dart:math' as math;
import 'dart:ui' hide TextBox;

import '../core/notebook_core.dart';
import 'ink_edit.dart';
import 'ink_types.dart';
import 'segmentation.dart';

/// Abaixo disto (≈ 0,2°) a linha já é considerada reta.
const double _minAngle = 0.0035;

/// Limite da escala aplicada a uma palavra.
const double kMinWordScale = 0.75;
const double kMaxWordScale = 1.25;

/// Variação de altura-x menor que isto é ruído de escrita: não reescala.
const double _scaleDeadband = 0.03;

/// Lacunas que já diferem da mediana menos que isto (unidades) ficam como estão.
const double _gapDeadband = 0.75;

/// Endireita as linhas de escrita dentro de [ids].
///
/// Por linha (veja `segmentLines`):
///  1. gira em torno do início da linha para a baseline ficar horizontal;
///  2. escala cada palavra (ancorada na esquerda e na baseline) para que a
///     altura-x dela seja a mediana das palavras da linha — escala limitada a
///     ±25 %, e palavra sem letras de altura-x (só 'l', 't'...) não é mexida;
///  3. reposiciona as palavras para que todas as lacunas sejam a mediana (a
///     primeira palavra fica onde está; se a linha passaria da borda direita
///     da página, as lacunas só encolhem).
///
/// Não mexe em textos, imagens, marca-texto nem em traços fora das linhas. Cada
/// traço trocado vira outro com id de [newId] e o antigo recebe tombstone.
/// Se nada precisa mudar devolve o próprio [doc].
PageDoc straighten(PageDoc doc, Set<String> ids, String Function() newId) {
  if (ids.isEmpty || doc.strokes.isEmpty) return doc;
  final lines = segmentLines(doc, only: ids);
  if (lines.isEmpty) return doc;
  final transforms = <String, Matrix2x3>{};
  for (final line in lines) {
    _straightenLine(doc, line, transforms);
  }
  return remapStrokes(doc, transforms, newId);
}

double _median(List<double> v) {
  final s = [...v]..sort();
  return s[s.length ~/ 2];
}

void _straightenLine(PageDoc doc, InkLine line, Map<String, Matrix2x3> out) {
  final xhLine = lineXHeight(doc, line);
  final anchor = Offset(line.bounds.left, line.baselineY);
  final rot = line.angle.abs() >= _minAngle
      ? Matrix2x3.rotation(-line.angle, anchor: anchor)
      : Matrix2x3.identity;

  // Por palavra: traços, caixa depois de girar, altura-x depois de girar.
  final n = line.words.length;
  final strokes = <List<Stroke>>[];
  final left = <double>[], right = <double>[];
  final xhWord = <double?>[];
  for (final w in line.words) {
    final ss = [for (final id in w.strokeIds) doc.strokeById(id)!];
    strokes.add(ss);
    var l = double.infinity, r = -double.infinity;
    final hs = <double>[];
    for (final s in ss) {
      final b = transformedPointBox(s, rot);
      l = math.min(l, b.left - s.width / 2);
      r = math.max(r, b.right + s.width / 2);
      if (b.height >= 0.4 * xhLine && b.height <= 1.6 * xhLine) hs.add(b.height);
    }
    left.add(l);
    right.add(r);
    xhWord.add(hs.length >= 2 ? _median(hs) : null);
  }

  // Escalas: altura-x de cada palavra → mediana das palavras com altura-x.
  final valid = [for (final h in xhWord) ?h];
  final scale = List<double>.filled(n, 1.0);
  if (valid.length >= 2) {
    final target = _median(valid);
    for (var i = 0; i < n; i++) {
      final h = xhWord[i];
      if (h == null) continue;
      final s = (target / h).clamp(kMinWordScale, kMaxWordScale);
      if ((s - 1).abs() >= _scaleDeadband) scale[i] = s;
    }
  }
  // (ancorada na esquerda da palavra e na baseline: a esquerda não se move)
  final scaledRight = [for (var i = 0; i < n; i++) left[i] + (right[i] - left[i]) * scale[i]];

  // Lacunas → mediana das lacunas originais (a escala cresce a palavra para a
  // direita e comeria a lacuna; as posições novas partem das larguras já
  // reescaladas).
  final shift = List<double>.filled(n, 0.0);
  if (n >= 2) {
    final gaps = [for (var i = 1; i < n; i++) left[i] - right[i - 1]];
    final target = _median(gaps);
    List<double> place(List<double> gapFor) {
      var cursor = scaledRight[0];
      final want = <double>[0.0];
      for (var i = 1; i < n; i++) {
        final newLeft = cursor + gapFor[i - 1];
        want.add(newLeft - left[i]);
        cursor = newLeft + (scaledRight[i] - left[i]);
      }
      return want..add(cursor);
    }

    var want = place(List<double>.filled(n - 1, target));
    if (want.last > pageWidth - 4) {
      // não cabe: só encolhe lacunas (nunca aumenta)
      want = place([for (final g in gaps) math.min(g, target)]);
    }
    if (want.last <= pageWidth - 4 || want.last <= right.last + 0.5) {
      for (var i = 1; i < n; i++) {
        shift[i] = want[i];
      }
      // deslocamentos pequenos demais para mudar alguma lacuna são ruído
      if (shift.every((d) => d.abs() < _gapDeadband)) shift.fillRange(0, n, 0.0);
    }
  }

  for (var i = 0; i < n; i++) {
    var m = rot;
    if (scale[i] != 1.0) {
      m = Matrix2x3.scaling(scale[i], anchor: Offset(left[i], line.baselineY)) * m;
    }
    if (shift[i] != 0.0) m = thenShift(m, Offset(shift[i], 0));
    for (final s in strokes[i]) {
      out[s.id] = m;
    }
  }
}
