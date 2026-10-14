/// Edições da Onda 2 do Caderno que juntam geometria e reconhecimento:
/// converter escrita em texto, trocar uma palavra pela correção do corretor,
/// aplicar um gesto no fim do traço e achar as palavras com erro de ortografia.
///
/// Tudo é Dart puro sobre o [PageDoc] (a tela só chama e grava o resultado).
library;

import 'dart:math' as math;
import 'dart:ui' hide TextBox;

import '../core/notebook_core.dart';
import 'gestures.dart';
import 'ink_types.dart';
import 'recognizer.dart';
import 'segmentation.dart';
import 'spell_checker.dart';
import 'transcript.dart';

/// Resultado de [convertInkToText].
class InkToTextResult {
  const InkToTextResult(this.doc, this.textIds, {this.converted = 0, this.failed = 0});

  /// O documento com as linhas convertidas (igual ao de entrada se nada mudou).
  final PageDoc doc;

  /// Ids das caixas de texto criadas (para selecioná-las).
  final Set<String> textIds;

  /// Linhas trocadas por texto.
  final int converted;

  /// Linhas que o reconhecedor não conseguiu ler (a escrita fica como estava).
  final int failed;
}

/// Converte a escrita de [ids] em caixas de texto, uma por linha, no lugar da
/// linha, com a cor e o tamanho aproximado da letra. Só traços de caneta entram
/// (marca-texto, textos e imagens ficam). Uma linha só é trocada se **todas** as
/// palavras dela foram reconhecidas: assim nunca some escrita sem texto no lugar.
Future<InkToTextResult> convertInkToText(
  PageDoc doc,
  Set<String> ids,
  InkRecognizer recognizer, {
  String Function() newId = newInkId,
}) async {
  final sub = PageDoc(strokes: [
    for (final s in doc.strokes)
      if (ids.contains(s.id) && s.tool != PenTool.highlighter) s,
  ]);
  if (sub.strokes.isEmpty) return InkToTextResult(doc, const {});
  final t = await transcribe(sub, recognizer);
  var out = doc;
  final created = <String>{};
  var converted = 0, failed = 0;
  for (final line in segmentLines(sub)) {
    final words = <String>[];
    for (final w in line.words) {
      final text = t.wordText[w.key];
      if (text == null || text.isEmpty) break;
      words.add(text);
    }
    if (line.words.isEmpty || words.length != line.words.length) {
      failed++;
      continue;
    }
    final box = _boxFor(
      doc,
      line.strokeIds,
      line.bounds,
      words.join(' '),
      size: _fontSize(lineXHeight(sub, line), handwriting: false),
      newId: newId,
    );
    out = out.without(line.strokeIds).withText(box);
    created.add(box.id);
    converted++;
  }
  return InkToTextResult(out, created, converted: converted, failed: failed);
}

/// Troca os traços de [word] (da linha [line]) por [text] em fonte manuscrita,
/// na mesma cor e altura da letra. Devolve o documento e o id da caixa criada.
({PageDoc doc, String textId}) replaceWordWithText(
  PageDoc doc,
  InkLine line,
  InkWord word,
  String text, {
  String Function() newId = newInkId,
}) {
  final box = _boxFor(
    doc,
    word.strokeIds,
    Rect.fromLTRB(word.bounds.left, line.bounds.top, word.bounds.right, line.bounds.bottom),
    text,
    size: _fontSize(lineXHeight(doc, line), handwriting: true),
    font: kHandwritingFont,
    newId: newId,
  );
  return (doc: doc.without(word.strokeIds).withText(box), textId: box.id);
}

/// Tamanho da fonte para a altura-x [xh] da escrita (a altura-x da fonte padrão
/// é ~0,5 do tamanho; a da Caveat, ~0,4).
double _fontSize(double xh, {required bool handwriting}) =>
    (xh / (handwriting ? 0.4 : 0.5)).clamp(10.0, 120.0).toDouble();

TextBox _boxFor(
  PageDoc doc,
  Iterable<String> strokeIds,
  Rect area,
  String text, {
  required double size,
  required String Function() newId,
  String? font,
}) {
  // Cor: a mais usada nos traços (sempre opaca; marca-texto não entra aqui).
  final count = <int, int>{};
  for (final id in strokeIds) {
    final s = doc.strokeById(id);
    if (s != null) count[s.argb | 0xFF000000] = (count[s.argb | 0xFF000000] ?? 0) + 1;
  }
  final argb = count.isEmpty
      ? 0xFF000000
      : count.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  // A caixa de texto quebra linha pela largura: precisa caber o texto todo.
  final need = text.length * size * 0.55 + size;
  final x = area.left.clamp(0.0, pageWidth - 40).toDouble();
  final y = area.top.clamp(0.0, pageHeight - size).toDouble();
  final w = math.max(area.width, need).clamp(40.0, pageWidth - x).toDouble();
  return TextBox(id: newId(), x: x, y: y, w: w, text: text, size: size, argb: argb, font: font);
}

/// Se [stroke] (o traço que acabou de ser feito sobre [before]) é um gesto de
/// edição, devolve o gesto e o documento com ele aplicado (o traço do gesto não
/// entra). Senão `null`: o traço vira tinta normal.
///
/// Só a escrita perto do traço é segmentada (a faixa da página na altura dele),
/// para o custo não crescer com a página.
({InkGesture gesture, PageDoc doc})? gestureEdit(
  PageDoc before,
  Stroke stroke, {
  String Function() newId = newInkId,
}) {
  if (stroke.tool == PenTool.highlighter || stroke.points.length < 3) return null;
  final b = stroke.bounds;
  final reach = math.max(b.height, 24.0) * 3;
  final band = Rect.fromLTRB(0, b.top - reach, pageWidth, b.bottom + reach);
  final near = {
    for (final s in before.strokes)
      if (s.bounds.overlaps(band)) s.id,
  };
  if (near.isEmpty) return null;
  final lines = segmentLines(before, only: near);
  if (lines.isEmpty) return null;
  final g = detectGesture(stroke, before, lines);
  if (g == null) return null;
  final after = applyGesture(before, g, newId);
  if (identical(after, before)) return null;
  return (gesture: g, doc: after);
}

/// Palavra reconhecida que o corretor marcou.
class SpellMark {
  const SpellMark({
    required this.line,
    required this.word,
    required this.text,
    required this.suggestions,
  });

  final InkLine line;
  final InkWord word;

  /// O texto reconhecido da palavra (com a pontuação que veio junto).
  final String text;

  /// Sugestões do corretor, já com a pontuação de [text] em volta.
  final List<String> suggestions;

  Rect get bounds => word.bounds;
}

final _edges = RegExp(r'^([^\p{L}]*)(.*?)([^\p{L}]*)$', unicode: true);
final _plainWord = RegExp(r"^\p{L}+(?:[-'’]\p{L}+)*$", unicode: true);

/// As palavras de [doc] cujo texto (de [transcript]) o corretor diz estar errado.
/// Palavras em [ignored] (minúsculas, sem pontuação), com número, de uma letra só
/// ou que já não existem no documento ficam de fora. Erro do corretor = sem marca.
Future<List<SpellMark>> findSpellMarks(
  PageDoc doc,
  PageTranscript transcript,
  SpellChecker checker, {
  Set<String> ignored = const {},
}) async {
  if (transcript.wordText.isEmpty) return const [];
  final marks = <SpellMark>[];
  for (final line in segmentLines(doc)) {
    for (final word in line.words) {
      final text = transcript.wordText[word.key];
      if (text == null) continue;
      final m = _edges.firstMatch(text.trim())!;
      final core = m.group(2)!;
      if (core.length < 2 || !_plainWord.hasMatch(core) || ignored.contains(core.toLowerCase())) continue;
      List<String>? sug;
      try {
        sug = await checker.suggestions(core);
      } catch (_) {
        sug = null;
      }
      if (sug == null) continue;
      final pre = m.group(1)!, post = m.group(3)!;
      marks.add(SpellMark(
        line: line,
        word: word,
        text: text.trim(),
        suggestions: [for (final s in sug) if (s.trim().isNotEmpty) '$pre${s.trim()}$post'],
      ));
    }
  }
  return marks;
}

/// Chave do dicionário pessoal para [text] ("Ignorar"): minúsculas, sem pontuação.
String ignoreKey(String text) => _edges.firstMatch(text.trim())!.group(2)!.toLowerCase();
