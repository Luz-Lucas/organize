import 'dart:ui' show Size;

import 'package:flutter/foundation.dart' show debugPrint;

import '../core/notebook_core.dart';
import 'ink_types.dart';
import 'recognizer.dart';
import 'segmentation.dart';

/// O texto reconhecido de uma página.
class PageTranscript {
  const PageTranscript({this.wordText = const {}, this.text = '', this.lineCount = 0});

  /// Texto de cada palavra: a chave é [InkWord.key] (ids dos traços ordenados e
  /// unidos por ',').
  final Map<String, String> wordText;

  /// A página toda: linhas separadas por `\n`.
  final String text;

  /// Quantas linhas de escrita a segmentação achou (inclusive as que o reconhecedor
  /// não conseguiu ler). `text` vazio com `lineCount > 0` é falha de reconhecimento,
  /// não uma página sem escrita.
  final int lineCount;

  bool get isEmpty => text.isEmpty && wordText.isEmpty;

  static const empty = PageTranscript();
}

/// Divide a tinta de [doc] em linhas (ver `segmentLines`).
typedef LineSegmenter = List<InkLine> Function(PageDoc doc);

final _spaces = RegExp(r'\s+');

/// Reconhece a página linha a linha (a linha anterior vai como `preContext`).
///
/// Cada linha é reconhecida **de uma vez** (mais preciso e uma só chamada); se o
/// número de palavras do texto bate com o de palavras segmentadas, o texto é
/// repartido entre elas. Se não bate, cada palavra é reconhecida sozinha (o que
/// também dá candidatos para o corretor). Linha sem reconhecimento ou com erro fica
/// de fora; nada disso derruba a página. [segment] troca a segmentação (testes);
/// [isCancelled] é consultado entre as chamadas e interrompe o trabalho.
///
/// Anota também cada [InkWord] (`text` e `candidates`) das linhas segmentadas.
Future<PageTranscript> transcribe(
  PageDoc doc,
  InkRecognizer r, {
  LineSegmenter? segment,
  bool Function()? isCancelled,
}) async {
  final lines = (segment ?? segmentLines)(doc);
  final byId = {for (final s in doc.strokes) s.id: s};
  final wordText = <String, String>{};
  final texts = <String>[];
  var previous = '';

  List<Stroke> strokesOf(Iterable<String> ids) => [
        for (final id in ids)
          if (byId[id] != null) byId[id]!,
      ];

  Future<List<String>> ask(List<Stroke> strokes, Size? area, String preContext) async {
    try {
      return [for (final c in await r.recognize(strokes, writingArea: area, preContext: preContext)) _clean(c)]
          .where((c) => c.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('Caderno: falha ao reconhecer: $e');
      return const [];
    }
  }

  for (final line in lines) {
    if (isCancelled?.call() ?? false) break;
    final strokes = strokesOf(line.strokeIds);
    if (strokes.isEmpty) continue;
    final words = [
      for (final w in line.words)
        if (strokesOf(w.strokeIds).isNotEmpty) w,
    ];
    final whole = await ask(strokes, line.bounds.size, previous);
    if (whole.isEmpty) continue;
    var lineText = whole.first;
    final tokens = lineText.split(_spaces);
    if (words.isNotEmpty && tokens.length == words.length) {
      for (var i = 0; i < words.length; i++) {
        words[i]
          ..text = tokens[i]
          ..candidates = [tokens[i]];
        wordText[words[i].key] = tokens[i];
      }
    } else if (words.isNotEmpty) {
      final parts = <String>[];
      for (final w in words) {
        if (isCancelled?.call() ?? false) break;
        final c = await ask(strokesOf(w.strokeIds), w.bounds.size, [previous, ...parts].where((e) => e.isNotEmpty).join(' '));
        if (c.isEmpty) continue;
        w
          ..text = c.first
          ..candidates = c;
        wordText[w.key] = c.first;
        parts.add(c.first);
      }
      if (parts.isNotEmpty) lineText = parts.join(' ');
    }
    texts.add(lineText);
    previous = lineText;
  }
  return PageTranscript(wordText: wordText, text: texts.join('\n'), lineCount: lines.length);
}

String _clean(String s) => s.trim().replaceAll(_spaces, ' ');
