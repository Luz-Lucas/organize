import '../features/notes/search_fold.dart';
import 'json.dart';

/// Seção do mercado. A ordem do enum é a ordem padrão; `name` é o valor gravado no banco.
enum ShopSection {
  hortifruti('Hortifrúti'),
  padaria('Padaria'),
  acougue('Açougue'),
  frios('Frios e laticínios'),
  mercearia('Mercearia'),
  bebidas('Bebidas'),
  limpeza('Limpeza'),
  higiene('Higiene'),
  congelados('Congelados'),
  outros('Outros');

  const ShopSection(this.label);

  final String label;

  /// Nome desconhecido ou nulo cai em [outros].
  static ShopSection fromName(Object? name) {
    for (final s in values) {
      if (s.name == name) return s;
    }
    return outros;
  }
}

/// Minúsculo, sem acento e com espaços normalizados (mesma chave que o banco usa em `name_key`).
String foldName(String s) => foldSearch(s);

class ShoppingList {
  const ShoppingList({required this.id, required this.name, this.position = 0, this.sectionOrder});

  final String id;
  final String name;
  final int position;

  /// Ordem das seções desta lista; `null` = ordem padrão.
  final List<ShopSection>? sectionOrder;

  factory ShoppingList.fromMap(Map<String, dynamic> m) => ShoppingList(
        id: m['id'] as String,
        name: m['name'] as String,
        position: (m['position'] as num?)?.toInt() ?? 0,
        sectionOrder: (m['section_order'] as List<dynamic>?)
            ?.map(ShopSection.fromName)
            .toList(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'position': position,
        'section_order': sectionOrder?.map((s) => s.name).toList(),
      };

  ShoppingList copyWith({String? name, int? position, List<ShopSection>? sectionOrder}) => ShoppingList(
        id: id,
        name: name ?? this.name,
        position: position ?? this.position,
        sectionOrder: sectionOrder ?? this.sectionOrder,
      );
}

class ShoppingItem {
  const ShoppingItem({
    required this.id,
    required this.listId,
    required this.name,
    this.quantity = '',
    this.section = ShopSection.outros,
    this.checked = false,
    this.position = 0,
    required this.createdAt,
  });

  final String id;
  final String listId;
  final String name;
  final String quantity;
  final ShopSection section;
  final bool checked;
  final int position;
  final DateTime createdAt;

  factory ShoppingItem.fromMap(Map<String, dynamic> m) => ShoppingItem(
        id: m['id'] as String,
        listId: m['list_id'] as String,
        name: m['name'] as String,
        quantity: (m['quantity'] as String?) ?? '',
        section: ShopSection.fromName(m['section']),
        checked: (m['checked'] as bool?) ?? false,
        position: (m['position'] as num?)?.toInt() ?? 0,
        createdAt: parseDate(m['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      );

  /// Só as colunas graváveis (`created_at` e `user_id` o banco preenche).
  Map<String, dynamic> toMap() => {
        'id': id,
        'list_id': listId,
        'name': name,
        'quantity': quantity,
        'section': section.name,
        'checked': checked,
        'position': position,
      };

  ShoppingItem copyWith({String? name, String? quantity, ShopSection? section, bool? checked, int? position}) =>
      ShoppingItem(
        id: id,
        listId: listId,
        name: name ?? this.name,
        quantity: quantity ?? this.quantity,
        section: section ?? this.section,
        checked: checked ?? this.checked,
        position: position ?? this.position,
        createdAt: createdAt,
      );
}

class FrequentItem {
  const FrequentItem({
    required this.name,
    required this.section,
    required this.times,
    required this.lastAddedAt,
  });

  final String name;
  final ShopSection section;
  final int times;
  final DateTime lastAddedAt;

  factory FrequentItem.fromMap(Map<String, dynamic> m) => FrequentItem(
        name: m['name'] as String,
        section: ShopSection.fromName(m['section']),
        times: (m['times'] as num?)?.toInt() ?? 1,
        lastAddedAt: parseDate(m['last_added_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// Item não marcado da mesma lista com o mesmo nome (sem acento/caixa), se houver.
ShoppingItem? findDuplicate(String name, String listId, Iterable<ShoppingItem> items) {
  final key = foldName(name);
  for (final i in items) {
    if (i.listId == listId && !i.checked && foldName(i.name) == key) return i;
  }
  return null;
}

int _byPosition(ShoppingItem a, ShoppingItem b) {
  final p = a.position.compareTo(b.position);
  return p != 0 ? p : a.createdAt.compareTo(b.createdAt);
}

/// Agrupa os itens não marcados por seção, na ordem da lista (as seções que faltam em [order]
/// vêm no fim, na ordem padrão). Só devolve seções com itens.
List<(ShopSection, List<ShoppingItem>)> groupBySection(
  List<ShoppingItem> unchecked,
  List<ShopSection>? order,
) {
  final sequence = <ShopSection>[
    ...?order,
    for (final s in ShopSection.values)
      if (!(order?.contains(s) ?? false)) s,
  ];
  return [
    for (final s in sequence)
      if (unchecked.any((i) => i.section == s))
        (s, unchecked.where((i) => i.section == s).toList()..sort(_byPosition)),
  ];
}

int _byUse(FrequentItem a, FrequentItem b) {
  final t = b.times.compareTo(a.times);
  return t != 0 ? t : b.lastAddedAt.compareTo(a.lastAddedAt);
}

/// Frequentes que não estão (não marcados) na lista: mais usados primeiro, depois os mais recentes.
List<FrequentItem> buyAgain(List<FrequentItem> frequent, List<ShoppingItem> inList, {int max = 12}) {
  final present = {for (final i in inList) if (!i.checked) foldName(i.name)};
  final out = frequent.where((f) => !present.contains(foldName(f.name))).toList()..sort(_byUse);
  return out.take(max).toList();
}

/// Sugestões ao digitar: nomes que começam com o texto vêm antes dos que apenas o contêm.
List<FrequentItem> suggest(String typed, List<FrequentItem> frequent, {int max = 6}) {
  final key = foldName(typed);
  if (key.isEmpty) return const [];
  final starts = <FrequentItem>[];
  final contains = <FrequentItem>[];
  for (final f in frequent) {
    final n = foldName(f.name);
    if (n.startsWith(key)) {
      starts.add(f);
    } else if (n.contains(key)) {
      contains.add(f);
    }
  }
  return [...(starts..sort(_byUse)), ...(contains..sort(_byUse))].take(max).toList();
}
