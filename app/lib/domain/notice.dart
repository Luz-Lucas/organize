import 'json.dart';

enum NoticePriority { normal, alta }

class Notice {
  const Notice({
    required this.id,
    required this.title,
    this.body = '',
    this.priority = NoticePriority.normal,
    this.pinned = false,
    this.expiresAt,
    this.archivedAt,
    this.createdAt,
  });

  final String id;
  final String title;
  final String body;
  final NoticePriority priority;
  final bool pinned;
  final DateTime? expiresAt;
  final DateTime? archivedAt;
  final DateTime? createdAt;

  factory Notice.fromMap(Map<String, dynamic> m) => Notice(
        id: m['id'] as String,
        title: m['title'] as String,
        body: (m['body'] as String?) ?? '',
        priority: m['priority'] == 'alta' ? NoticePriority.alta : NoticePriority.normal,
        pinned: (m['pinned'] as bool?) ?? false,
        expiresAt: parseDate(m['expires_at']),
        archivedAt: parseDate(m['archived_at']),
        createdAt: parseDate(m['created_at']),
      );

  /// Não inclui `created_at`: é definido pelo banco.
  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'body': body,
        'priority': priority.name,
        'pinned': pinned,
        'expires_at': encodeDate(expiresAt),
        'archived_at': encodeDate(archivedAt),
      };

  Notice copyWith({
    String? title,
    String? body,
    NoticePriority? priority,
    bool? pinned,
    DateTime? expiresAt,
    bool clearExpires = false,
    DateTime? archivedAt,
  }) =>
      Notice(
        id: id,
        title: title ?? this.title,
        body: body ?? this.body,
        priority: priority ?? this.priority,
        pinned: pinned ?? this.pinned,
        expiresAt: clearExpires ? null : (expiresAt ?? this.expiresAt),
        archivedAt: archivedAt ?? this.archivedAt,
        createdAt: createdAt,
      );
}

/// Avisos visíveis: sem arquivados nem expirados; fixado > prioridade alta > mais recente.
List<Notice> activeNotices(Iterable<Notice> notices, DateTime now) {
  final list = notices
      .where((n) => n.archivedAt == null && (n.expiresAt == null || n.expiresAt!.isAfter(now)))
      .toList();
  final epoch = DateTime(0);
  list.sort((a, b) {
    if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
    if (a.priority != b.priority) return a.priority == NoticePriority.alta ? -1 : 1;
    return (b.createdAt ?? epoch).compareTo(a.createdAt ?? epoch);
  });
  return list;
}
