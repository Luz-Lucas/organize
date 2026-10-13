import '../../domain/json.dart';
import '../core/notebook_core.dart';

PageBackground parsePageBackground(Object? v) =>
    PageBackground.values.firstWhere((b) => b.name == v, orElse: () => PageBackground.lined);

/// Uma linha de `note_pages`. [data] é o documento codificado (JSON v1 → gzip →
/// base64, ver `encodePage`); [version] é a versão otimista conhecida pelo cliente.
class NotebookPage {
  const NotebookPage({
    required this.id,
    required this.noteId,
    required this.idx,
    this.background = PageBackground.lined,
    this.data = '',
    this.recognizedText = '',
    this.version = 0,
    this.updatedAt,
  });

  final String id;
  final String noteId;
  final int idx;
  final PageBackground background;
  final String data;
  final String recognizedText;
  final int version;
  final DateTime? updatedAt;

  factory NotebookPage.fromMap(Map<String, dynamic> m) => NotebookPage(
        id: m['id'] as String,
        noteId: m['note_id'] as String,
        idx: (m['idx'] as num).toInt(),
        background: parsePageBackground(m['background']),
        data: (m['data'] as String?) ?? '',
        recognizedText: (m['recognized_text'] as String?) ?? '',
        version: ((m['version'] as num?) ?? 0).toInt(),
        updatedAt: parseDate(m['updated_at']),
      );

  /// Colunas graváveis num insert. `version` e `updated_at` ficam por conta do banco/repositório.
  Map<String, dynamic> toInsertMap() => {
        'id': id,
        'note_id': noteId,
        'idx': idx,
        'background': background.name,
        'data': data,
        'recognized_text': recognizedText,
        'version': version,
      };

  NotebookPage copyWith({
    int? idx,
    PageBackground? background,
    String? data,
    String? recognizedText,
    int? version,
    DateTime? updatedAt,
    String? id,
  }) =>
      NotebookPage(
        id: id ?? this.id,
        noteId: noteId,
        idx: idx ?? this.idx,
        background: background ?? this.background,
        data: data ?? this.data,
        recognizedText: recognizedText ?? this.recognizedText,
        version: version ?? this.version,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  bool operator ==(Object other) =>
      other is NotebookPage &&
      other.id == id &&
      other.noteId == noteId &&
      other.idx == idx &&
      other.background == background &&
      other.data == data &&
      other.recognizedText == recognizedText &&
      other.version == version;

  @override
  int get hashCode => Object.hash(id, noteId, idx, background, data, recognizedText, version);
}
