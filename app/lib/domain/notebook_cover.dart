import 'dart:convert';

import 'note.dart';

/// O `body` de um caderno como mapa: os cadernos não guardam texto ali, e sim um
/// JSON com os dados do caderno (`cover`, `pdf`…). Vazio se não for esse JSON.
Map<String, dynamic> notebookBodyMap(String body) {
  final b = body.trim();
  if (!b.startsWith('{')) return {};
  try {
    final decoded = jsonDecode(b);
    return decoded is Map<String, dynamic> ? decoded : {};
  } on FormatException {
    return {};
  }
}

/// [body] com a chave [key] trocada por [value] (`null` tira a chave); as outras
/// chaves ficam. Sem chave nenhuma, o `body` volta a ser vazio.
String notebookBodyWith(String body, String key, Object? value) {
  final map = notebookBodyMap(body);
  if (value == null) {
    map.remove(key);
  } else {
    map[key] = value;
  }
  return map.isEmpty ? '' : jsonEncode(map);
}

/// Tipo de capa de um caderno.
enum CoverKind { text, emoji, image }

/// Como a imagem ocupa a capa: [fill] cobre tudo (corta o que sobra);
/// [fit] mostra a imagem inteira, com a cor da capa nas sobras.
enum CoverFit { fill, fit }

/// Cores prontas para a capa (ARGB).
const List<int> kCoverColors = [
  0xFF1E293B, // grafite
  0xFF7C3AED, // violeta
  0xFF2563EB, // azul
  0xFF0891B2, // ciano
  0xFF059669, // verde
  0xFF65A30D, // oliva
  0xFFF59E0B, // âmbar
  0xFFEA580C, // laranja
  0xFFDC2626, // vermelho
  0xFFDB2777, // rosa
  0xFFF5F5F4, // papel
];

/// A capa de um caderno: um texto, um emoji ou uma imagem (do Storage do caderno).
///
/// Fica no `body` da nota do caderno (que não guarda texto), como
/// `{"cover":{…}}` (ver [notebookBodyMap]): viaja com a nota entre aparelhos e some
/// quando o caderno é excluído, sem coluna nova no banco.
class NotebookCover {
  const NotebookCover({
    required this.kind,
    this.text = '',
    this.emoji = '',
    this.color = 0xFF2563EB,
    this.imagePath,
    this.fit = CoverFit.fill,
  });

  final CoverKind kind;
  final String text;
  final String emoji;

  /// Fundo da capa (ARGB). Na imagem, aparece nas sobras com [CoverFit.fit].
  final int color;

  /// Caminho no Storage do caderno, para [CoverKind.image].
  final String? imagePath;
  final CoverFit fit;

  /// Tem o que mostrar? (texto vazio, emoji vazio ou imagem sem caminho não contam)
  bool get isValid => switch (kind) {
    CoverKind.text => text.trim().isNotEmpty,
    CoverKind.emoji => emoji.trim().isNotEmpty,
    CoverKind.image => (imagePath ?? '').isNotEmpty,
  };

  NotebookCover copyWith({
    CoverKind? kind,
    String? text,
    String? emoji,
    int? color,
    String? imagePath,
    CoverFit? fit,
  }) => NotebookCover(
    kind: kind ?? this.kind,
    text: text ?? this.text,
    emoji: emoji ?? this.emoji,
    color: color ?? this.color,
    imagePath: imagePath ?? this.imagePath,
    fit: fit ?? this.fit,
  );

  Map<String, dynamic> toMap() => {
    'v': 1,
    'kind': kind.name,
    if (text.isNotEmpty) 'text': text,
    if (emoji.isNotEmpty) 'emoji': emoji,
    'color': color,
    if (imagePath != null) 'image': imagePath,
    'fit': fit.name,
  };

  static NotebookCover? fromMap(Object? m) {
    if (m is! Map) return null;
    final kind = CoverKind.values.where((k) => k.name == m['kind']).firstOrNull;
    if (kind == null) return null;
    final color = m['color'];
    final cover = NotebookCover(
      kind: kind,
      text: m['text'] is String ? m['text'] as String : '',
      emoji: m['emoji'] is String ? m['emoji'] as String : '',
      color: color is int ? color : 0xFF2563EB,
      imagePath: m['image'] is String ? m['image'] as String : null,
      fit: m['fit'] == CoverFit.fit.name ? CoverFit.fit : CoverFit.fill,
    );
    return cover.isValid ? cover : null;
  }

  /// O `body` de um caderno só com esta capa.
  String toBody() => notebookBodyWith('', 'cover', toMap());

  /// A capa guardada em [body], ou `null` (sem capa, ou um `body` que não é capa).
  static NotebookCover? fromBody(String body) => fromMap(notebookBodyMap(body)['cover']);

  @override
  bool operator ==(Object other) =>
      other is NotebookCover &&
      other.kind == kind &&
      other.text == text &&
      other.emoji == emoji &&
      other.color == color &&
      other.imagePath == imagePath &&
      other.fit == fit;

  @override
  int get hashCode => Object.hash(kind, text, emoji, color, imagePath, fit);
}

extension NotebookCoverNote on Note {
  /// A capa do caderno, se houver.
  NotebookCover? get cover => isNotebook ? NotebookCover.fromBody(body) : null;

  /// O caderno com a capa [cover] (`null` tira a capa). O resto do `body` (o PDF) fica.
  Note withCover(NotebookCover? cover) => copyWith(body: notebookBodyWith(body, 'cover', cover?.toMap()));

  /// Texto da capa para a busca (o `body` do caderno é a capa em JSON).
  String get coverSearchText {
    final c = cover;
    if (c == null) return '';
    return c.kind == CoverKind.text ? c.text : '';
  }
}
