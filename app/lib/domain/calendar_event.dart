import 'json.dart';

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

  CalendarEvent withoutSpace() => CalendarEvent(
        id: id,
        title: title,
        startsAt: startsAt,
        endsAt: endsAt,
        allDay: allDay,
        location: location,
        source: source,
        externalId: externalId,
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
      other.externalId == externalId;

  @override
  int get hashCode => Object.hash(id, title, startsAt, endsAt, allDay,
      location, spaceId, source, externalId);
}
