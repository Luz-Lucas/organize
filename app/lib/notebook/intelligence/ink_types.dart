import 'dart:ui' hide TextBox;

/// Uma palavra segmentada da tinta de uma página (resultado de `segmentLines`).
///
/// [strokeIds] está em ordem de documento (a ordem de `PageDoc.strokes`).
/// [text] e [candidates] são preenchidos depois pelo reconhecimento; ficam
/// mutáveis de propósito, para o reconhecedor anotar a palavra sem recriá-la.
class InkWord {
  InkWord({
    required this.strokeIds,
    required this.bounds,
    this.text,
    List<String>? candidates,
  }) : candidates = candidates ?? <String>[];

  final List<String> strokeIds;
  final Rect bounds;
  String? text;
  List<String> candidates;

  /// Chave canônica da palavra (a mesma usada em `PageTranscript.wordText`):
  /// os ids dos traços ordenados e unidos por ','.
  String get key => wordKey(strokeIds);

  @override
  String toString() => 'InkWord(${strokeIds.length} traços, $bounds, $text)';
}

/// Uma linha de escrita: traços agrupados por baseline, com suas palavras.
///
/// [baselineY] é o y da baseline no início da linha (x = `bounds.left`);
/// [angle] é a inclinação da baseline em radianos (positivo = desce para a
/// direita, y cresce para baixo), de modo que a baseline em x é
/// `baselineY + tan(angle) * (x - bounds.left)`.
class InkLine {
  InkLine({
    required this.strokeIds,
    required this.bounds,
    required this.baselineY,
    required this.angle,
    required this.words,
  });

  final List<String> strokeIds;
  final Rect bounds;
  final double baselineY;
  final double angle;
  final List<InkWord> words;

  @override
  String toString() =>
      'InkLine(${strokeIds.length} traços, ${words.length} palavras, $bounds)';
}

/// Ids ordenados e unidos por ',' (chave de uma palavra).
String wordKey(Iterable<String> strokeIds) =>
    (strokeIds.toList()..sort()).join(',');
