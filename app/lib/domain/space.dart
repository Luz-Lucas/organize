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
  });

  final String id;
  final String name;
  final SpaceKind kind;
  final int position;

  factory Space.fromMap(Map<String, dynamic> m) => Space(
        id: m['id'] as String,
        name: m['name'] as String,
        kind: SpaceKind.values.byName(m['kind'] as String),
        position: (m['position'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'position': position,
      };

  Space copyWith({String? name, SpaceKind? kind, int? position}) => Space(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        position: position ?? this.position,
      );

  @override
  bool operator ==(Object other) =>
      other is Space &&
      other.id == id &&
      other.name == name &&
      other.kind == kind &&
      other.position == position;

  @override
  int get hashCode => Object.hash(id, name, kind, position);
}
