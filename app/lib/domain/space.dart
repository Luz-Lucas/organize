enum SpaceKind {
  materia('Matéria', 'Matérias'),
  trabalho('Trabalho', 'Trabalhos'),
  hobby('Hobby', 'Hobbies'),
  geral('Geral', 'Geral');

  const SpaceKind(this.singular, this.plural);

  final String singular;
  final String plural;
}

class Space {
  const Space({
    required this.id,
    required this.name,
    this.kind = SpaceKind.geral,
    this.position = 0,
    this.color,
  });

  final String id;
  final String name;
  final SpaceKind kind;
  final int position;

  /// Cor da pasta em hex `#RRGGBB` (coluna `spaces.color`); `null` usa a cor do tema.
  final String? color;

  factory Space.fromMap(Map<String, dynamic> m) => Space(
        id: m['id'] as String,
        name: m['name'] as String,
        kind: SpaceKind.values.byName(m['kind'] as String),
        position: (m['position'] as num?)?.toInt() ?? 0,
        color: m['color'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'position': position,
        'color': color,
      };

  Space copyWith({String? name, SpaceKind? kind, int? position, String? color}) => Space(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        position: position ?? this.position,
        color: color ?? this.color,
      );

  @override
  bool operator ==(Object other) =>
      other is Space &&
      other.id == id &&
      other.name == name &&
      other.kind == kind &&
      other.position == position &&
      other.color == color;

  @override
  int get hashCode => Object.hash(id, name, kind, position, color);
}
