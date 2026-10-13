import 'json.dart';
import 'recurrence.dart';

class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.title,
    required this.startsAt,
    required this.endsAt,
    this.allDay = false,
    this.location,
    this.spaceId,
    this.source = 'manual',
    this.externalId,
    this.seriesId,
    this.recurrence,
  });

  final String id;
  final String title;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool allDay;
  final String? location;
  final String? spaceId;
  final String source;
  final String? externalId;

  /// Ocorrências da mesma série compartilham o `seriesId`.
  final String? seriesId;

  /// Regra que gerou a série (informativa).
  final Recurrence? recurrence;

  CalendarEvent copyWith({
    String? id,
    String? title,
    DateTime? startsAt,
    DateTime? endsAt,
    bool? allDay,
    String? location,
    String? spaceId,
    String? seriesId,
    Recurrence? recurrence,
    bool clearLocation = false,
    bool clearSpace = false,
    bool clearSeries = false,
  }) =>
      CalendarEvent(
        id: id ?? this.id,
        title: title ?? this.title,
        startsAt: startsAt ?? this.startsAt,
        endsAt: endsAt ?? this.endsAt,
        allDay: allDay ?? this.allDay,
        location: clearLocation ? null : (location ?? this.location),
        spaceId: clearSpace ? null : (spaceId ?? this.spaceId),
        source: source,
        externalId: externalId,
        seriesId: clearSeries ? null : (seriesId ?? this.seriesId),
        recurrence: clearSeries ? null : (recurrence ?? this.recurrence),
      );

  CalendarEvent withoutSpace() => CalendarEvent(
        id: id,
        title: title,
        startsAt: startsAt,
        endsAt: endsAt,
        allDay: allDay,
        location: location,
        source: source,
        externalId: externalId,
        seriesId: seriesId,
        recurrence: recurrence,
      );

  factory CalendarEvent.fromMap(Map<String, dynamic> m) => CalendarEvent(
        id: m['id'] as String,
        title: m['title'] as String,
        startsAt: parseDate(m['starts_at'])!,
        endsAt: parseDate(m['ends_at'])!,
        allDay: (m['all_day'] as bool?) ?? false,
        location: m['location'] as String?,
        spaceId: m['space_id'] as String?,
        source: (m['source'] as String?) ?? 'manual',
        externalId: m['external_id'] as String?,
        seriesId: m['series_id'] as String?,
        recurrence: m['recurrence'] is Map
            ? Recurrence.fromMap(Map<String, dynamic>.from(m['recurrence'] as Map))
            : null,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'starts_at': encodeDate(startsAt),
        'ends_at': encodeDate(endsAt),
        'all_day': allDay,
        'location': location,
        'space_id': spaceId,
        'source': source,
        'external_id': externalId,
        'series_id': seriesId,
        'recurrence': recurrence?.toMap(),
      };

  @override
  bool operator ==(Object other) =>
      other is CalendarEvent &&
      other.id == id &&
      other.title == title &&
      other.startsAt == startsAt &&
      other.endsAt == endsAt &&
      other.allDay == allDay &&
      other.location == location &&
      other.spaceId == spaceId &&
      other.source == source &&
      other.externalId == externalId &&
      other.seriesId == seriesId &&
      other.recurrence == recurrence;

  @override
  int get hashCode => Object.hash(id, title, startsAt, endsAt, allDay,
      location, spaceId, source, externalId, seriesId, recurrence);
}
