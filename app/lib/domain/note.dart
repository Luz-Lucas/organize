import 'json.dart';

/// Tipo da nota: texto (Markdown) ou caderno (páginas manuscritas).
enum NoteKind {
  text,
  notebook;

  static NoteKind parse(Object? v) => v == 'notebook' ? notebook : text;
}

class Note {
  const Note({
    required this.id,
    required this.title,
    this.body = '',
    this.spaceId,
    this.parentId,
    this.updatedAt,
    this.kind = NoteKind.text,
  });

  final String id;
  final String title;
  final String body;
  final String? spaceId;
  final String? parentId;
  final DateTime? updatedAt;
  final NoteKind kind;

  bool get isNotebook => kind == NoteKind.notebook;

  factory Note.fromMap(Map<String, dynamic> m) => Note(
        id: m['id'] as String,
        title: m['title'] as String,
        body: (m['body'] as String?) ?? '',
        spaceId: m['space_id'] as String?,
        parentId: m['parent_id'] as String?,
        updatedAt: parseDate(m['updated_at']),
        kind: NoteKind.parse(m['kind']),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'body': body,
        'space_id': spaceId,
        'parent_id': parentId,
        'kind': kind.name,
      };

  Note copyWith({String? title, String? body}) => Note(
        id: id,
        title: title ?? this.title,
        body: body ?? this.body,
        spaceId: spaceId,
        parentId: parentId,
        updatedAt: updatedAt,
        kind: kind,
      );

  /// Mesma nota em outro espaço (ou sem espaço, com `null`).
  Note withSpace(String? spaceId) => Note(
        id: id,
        title: title,
        body: body,
        spaceId: spaceId,
        parentId: parentId,
        updatedAt: updatedAt,
        kind: kind,
      );

  @override
  bool operator ==(Object other) =>
      other is Note &&
      other.id == id &&
      other.title == title &&
      other.body == body &&
      other.spaceId == spaceId &&
      other.parentId == parentId &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(id, title, body, spaceId, parentId, kind);
}
