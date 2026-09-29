import 'json.dart';

class Note {
  const Note({
    required this.id,
    required this.title,
    this.body = '',
    this.spaceId,
    this.parentId,
    this.updatedAt,
  });

  final String id;
  final String title;
  final String body;
  final String? spaceId;
  final String? parentId;
  final DateTime? updatedAt;

  factory Note.fromMap(Map<String, dynamic> m) => Note(
        id: m['id'] as String,
        title: m['title'] as String,
        body: (m['body'] as String?) ?? '',
        spaceId: m['space_id'] as String?,
        parentId: m['parent_id'] as String?,
        updatedAt: parseDate(m['updated_at']),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'body': body,
        'space_id': spaceId,
        'parent_id': parentId,
      };

  Note copyWith({String? title, String? body}) => Note(
        id: id,
        title: title ?? this.title,
        body: body ?? this.body,
        spaceId: spaceId,
        parentId: parentId,
        updatedAt: updatedAt,
      );

  @override
  bool operator ==(Object other) =>
      other is Note &&
      other.id == id &&
      other.title == title &&
      other.body == body &&
      other.spaceId == spaceId &&
      other.parentId == parentId;

  @override
  int get hashCode => Object.hash(id, title, body, spaceId, parentId);
}
