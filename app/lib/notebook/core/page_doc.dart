import 'ink_types.dart';

/// Documento imutável de uma página: traços, textos, imagens e tombstones.
///
/// Invariantes (garantidas pelo construtor e por todas as operações):
/// * as listas só têm itens **vivos**: nenhum id de [deleted] aparece nelas;
/// * ids não se repetem;
/// * as listas e o conjunto são imutáveis.
///
/// Mesclar duas versões é a união por id menos os tombstones ([merge]); o
/// resultado tem ordem canônica (ordenado por id; com [newInkId] isso é a
/// ordem de criação), então `a.merge(b) == b.merge(a)`.
class PageDoc {
  /// Normaliza: descarta itens tombstoned e duplicados e torna tudo imutável.
  factory PageDoc({
    Iterable<Stroke> strokes = const [],
    Iterable<TextBox> texts = const [],
    Iterable<ImageBox> images = const [],
    Iterable<String> deleted = const {},
  }) {
    final del = Set<String>.unmodifiable(deleted);
    return PageDoc._(
      List.unmodifiable(_dedupe<Stroke>(strokes, (s) => s.id, del, _cmpStroke)),
      List.unmodifiable(_dedupe<TextBox>(texts, (s) => s.id, del, _cmpText)),
      List.unmodifiable(_dedupe<ImageBox>(images, (s) => s.id, del, _cmpImage)),
      del,
    );
  }

  PageDoc._(this.strokes, this.texts, this.images, this.deleted);

  static final PageDoc empty = PageDoc._(
    const <Stroke>[],
    const <TextBox>[],
    const <ImageBox>[],
    const <String>{},
  );

  final List<Stroke> strokes;
  final List<TextBox> texts;
  final List<ImageBox> images;

  /// Ids apagados alguma vez (tombstones); propagam a exclusão no merge.
  final Set<String> deleted;

  /// Sem nenhum item vivo (pode ter tombstones).
  bool get isEmpty => strokes.isEmpty && texts.isEmpty && images.isEmpty;

  /// Total de itens vivos.
  int get itemCount => strokes.length + texts.length + images.length;

  late final Map<String, Stroke> _strokeIndex = {
    for (final s in strokes) s.id: s,
  };
  late final Map<String, TextBox> _textIndex = {for (final s in texts) s.id: s};
  late final Map<String, ImageBox> _imageIndex = {
    for (final s in images) s.id: s,
  };

  Stroke? strokeById(String id) => _strokeIndex[id];
  TextBox? textById(String id) => _textIndex[id];
  ImageBox? imageById(String id) => _imageIndex[id];

  /// O id existe vivo (traço, texto ou imagem).
  bool contains(String id) =>
      _strokeIndex.containsKey(id) ||
      _textIndex.containsKey(id) ||
      _imageIndex.containsKey(id);

  // ---- edição (sempre devolve novo documento) -----------------------------

  PageDoc withStroke(Stroke s) => withStrokes([s]);

  PageDoc withStrokes(Iterable<Stroke> add) {
    final fresh = _admit<Stroke>(
      add,
      _strokeIndex,
      (s) => s.id,
      (s) => s.quantized(),
      'traço',
    );
    if (fresh.isEmpty) return this;
    return PageDoc._(
      List.unmodifiable([...strokes, ...fresh]),
      texts,
      images,
      deleted,
    );
  }

  PageDoc withText(TextBox t) {
    final fresh = _admit<TextBox>(
      [t],
      _textIndex,
      (s) => s.id,
      (s) => s.quantized(),
      'texto',
    );
    if (fresh.isEmpty) return this;
    return PageDoc._(
      strokes,
      List.unmodifiable([...texts, ...fresh]),
      images,
      deleted,
    );
  }

  PageDoc withImage(ImageBox i) {
    final fresh = _admit<ImageBox>(
      [i],
      _imageIndex,
      (s) => s.id,
      (s) => s.quantized(),
      'imagem',
    );
    if (fresh.isEmpty) return this;
    return PageDoc._(
      strokes,
      texts,
      List.unmodifiable([...images, ...fresh]),
      deleted,
    );
  }

  /// Remove os itens com esses ids e registra os tombstones (inclusive de ids
  /// que não estão aqui, para que a exclusão se propague no merge).
  PageDoc without(Iterable<String> ids) {
    final set = ids is Set<String> ? ids : ids.toSet();
    if (set.isEmpty) return this;
    return PageDoc._(
      List.unmodifiable(strokes.where((s) => !set.contains(s.id))),
      List.unmodifiable(texts.where((s) => !set.contains(s.id))),
      List.unmodifiable(images.where((s) => !set.contains(s.id))),
      Set.unmodifiable({...deleted, ...set}),
    );
  }

  /// União por id menos tombstones; comutativa, associativa e idempotente.
  /// Itens ficam em ordem canônica (por id).
  PageDoc merge(PageDoc other) {
    final del = Set<String>.unmodifiable({...deleted, ...other.deleted});
    return PageDoc._(
      List.unmodifiable(
        _union<Stroke>(strokes, other.strokes, (s) => s.id, del, _cmpStroke),
      ),
      List.unmodifiable(
        _union<TextBox>(texts, other.texts, (s) => s.id, del, _cmpText),
      ),
      List.unmodifiable(
        _union<ImageBox>(images, other.images, (s) => s.id, del, _cmpImage),
      ),
      del,
    );
  }

  List<T> _admit<T>(
    Iterable<T> add,
    Map<String, T> index,
    String Function(T) idOf,
    T Function(T) quantize,
    String kind,
  ) {
    final fresh = <T>[];
    final seen = <String>{};
    for (final raw in add) {
      final item = quantize(raw);
      final id = idOf(item);
      if (deleted.contains(id)) {
        throw ArgumentError.value(
          id,
          'id',
          '$kind com id já apagado (tombstone); crie com um id novo (newInkId)',
        );
      }
      final existing = index[id];
      if (existing != null) {
        if (existing == item) continue;
        throw ArgumentError.value(
          id,
          'id',
          '$kind já existe com conteúdo diferente (itens são imutáveis; apague e crie outro id)',
        );
      }
      if (!seen.add(id)) {
        throw ArgumentError.value(id, 'id', '$kind repetido na mesma operação');
      }
      fresh.add(item);
    }
    return fresh;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PageDoc &&
          _listEq(other.strokes, strokes) &&
          _listEq(other.texts, texts) &&
          _listEq(other.images, images) &&
          other.deleted.length == deleted.length &&
          other.deleted.containsAll(deleted);

  @override
  int get hashCode =>
      Object.hash(strokes.length, texts.length, images.length, deleted.length);

  @override
  String toString() =>
      'PageDoc(${strokes.length} traços, ${texts.length} textos, '
      '${images.length} imagens, ${deleted.length} apagados)';
}

bool _listEq<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

List<T> _dedupe<T>(
  Iterable<T> items,
  String Function(T) idOf,
  Set<String> deleted,
  int Function(T, T) cmp,
) {
  final out = <String, T>{};
  for (final it in items) {
    final id = idOf(it);
    if (deleted.contains(id)) continue;
    final prev = out[id];
    out[id] = prev == null ? it : _pick(prev, it, cmp);
  }
  return out.values.toList();
}

List<T> _union<T>(
  List<T> a,
  List<T> b,
  String Function(T) idOf,
  Set<String> deleted,
  int Function(T, T) cmp,
) {
  final out = <String, T>{};
  for (final list in [a, b]) {
    for (final it in list) {
      final id = idOf(it);
      if (deleted.contains(id)) continue;
      final prev = out[id];
      out[id] = prev == null ? it : _pick(prev, it, cmp);
    }
  }
  final ids = out.keys.toList()..sort();
  return [for (final id in ids) out[id] as T];
}

/// Mesmo id com conteúdo diferente não deveria acontecer (itens imutáveis);
/// se acontecer, escolhe sempre o mesmo vencedor, qualquer que seja a ordem.
T _pick<T>(T a, T b, int Function(T, T) cmp) =>
    identical(a, b) || a == b ? a : (cmp(a, b) <= 0 ? a : b);

int _cmpNum(num a, num b) => a.compareTo(b);

int _cmpStroke(Stroke a, Stroke b) {
  var c = _cmpNum(a.tool.index, b.tool.index);
  if (c != 0) return c;
  c = _cmpNum(a.argb, b.argb);
  if (c != 0) return c;
  c = _cmpNum(a.width, b.width);
  if (c != 0) return c;
  c = _cmpNum(a.points.length, b.points.length);
  if (c != 0) return c;
  for (var i = 0; i < a.points.length; i++) {
    final p = a.points[i], q = b.points[i];
    c = _cmpNum(p.x, q.x);
    if (c != 0) return c;
    c = _cmpNum(p.y, q.y);
    if (c != 0) return c;
    c = _cmpNum(p.p, q.p);
    if (c != 0) return c;
  }
  return 0;
}

int _cmpText(TextBox a, TextBox b) {
  for (final c in [
    _cmpNum(a.x, b.x),
    _cmpNum(a.y, b.y),
    _cmpNum(a.w, b.w),
    a.text.compareTo(b.text),
    _cmpNum(a.size, b.size),
    _cmpNum(a.argb, b.argb),
  ]) {
    if (c != 0) return c;
  }
  return 0;
}

int _cmpImage(ImageBox a, ImageBox b) {
  for (final c in [
    _cmpNum(a.x, b.x),
    _cmpNum(a.y, b.y),
    _cmpNum(a.w, b.w),
    _cmpNum(a.h, b.h),
    a.path.compareTo(b.path),
  ]) {
    if (c != 0) return c;
  }
  return 0;
}
