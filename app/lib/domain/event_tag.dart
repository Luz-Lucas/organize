/// Peso visual da etiqueta no calendário (e chave da classificação automática no banco).
enum EventTagRole {
  main('Principal'),
  secondary('Secundária'),
  seasonal('Sazonal'),
  meeting('Reunião'),
  normal('Comum');

  const EventTagRole(this.label);

  final String label;

  static EventTagRole fromName(Object? name) =>
      EventTagRole.values.firstWhere((r) => r.name == name, orElse: () => normal);
}

/// Etiqueta colorida de evento (ex.: Aula, Academia). A cor é `#RRGGBB`.
class EventTag {
  const EventTag({
    required this.id,
    required this.name,
    required this.color,
    this.role = EventTagRole.normal,
    this.position = 0,
  });

  final String id;
  final String name;
  final String color;
  final EventTagRole role;
  final int position;

  factory EventTag.fromMap(Map<String, dynamic> m) => EventTag(
        id: m['id'] as String,
        name: m['name'] as String,
        color: m['color'] as String,
        role: EventTagRole.fromName(m['role']),
        position: (m['position'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'color': color,
        'role': role.name,
        'position': position,
      };

  EventTag copyWith({String? id, String? name, String? color, EventTagRole? role, int? position}) => EventTag(
        id: id ?? this.id,
        name: name ?? this.name,
        color: color ?? this.color,
        role: role ?? this.role,
        position: position ?? this.position,
      );

  @override
  bool operator ==(Object other) =>
      other is EventTag &&
      other.id == id &&
      other.name == name &&
      other.color == color &&
      other.role == role &&
      other.position == position;

  @override
  int get hashCode => Object.hash(id, name, color, role, position);
}
