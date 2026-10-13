import 'package:flutter/foundation.dart' show immutable;

import 'ids.dart';
import 'ink_types.dart';
import 'page_doc.dart';

/// Mudança entre dois estados: itens que apareceram e itens que sumiram.
@immutable
class _Delta {
  const _Delta(this.added, this.removed);
  final List<Object> added;
  final List<Object> removed;
}

String _idOf(Object item) => switch (item) {
  Stroke s => s.id,
  TextBox t => t.id,
  ImageBox i => i.id,
  _ => throw ArgumentError.value(item, 'item'),
};

PageDoc _withItem(PageDoc doc, Object item, String id) => switch (item) {
  Stroke s => doc.withStroke(s.copyWith(id: id)),
  TextBox t => doc.withText(t.copyWith(id: id)),
  ImageBox i => doc.withImage(i.copyWith(id: id)),
  _ => throw ArgumentError.value(item, 'item'),
};

/// Resultado de [History.undo]/[History.redo].
class HistoryStep {
  const HistoryStep(this.history, this.doc, this.idMap);

  /// Novo histórico.
  final History history;

  /// Novo documento da página.
  final PageDoc doc;

  /// Itens trazidos de volta: id que tinham antes -> id novo que receberam.
  final Map<String, String> idMap;
}

/// Desfazer/refazer **imutável** de uma página.
///
/// Guarda só as diferenças (itens que entraram e que saíram) de cada edição,
/// não cópias da página. Desfazer/refazer é feito como uma **nova edição**
/// sobre o documento atual, o que o mantém correto com a sincronização:
/// * itens que o passo apagou voltam como **cópias com id novo** (o id antigo
///   continua tombstoned e o merge com o servidor não o apaga de novo);
/// * itens que o passo criou são apagados (tombstone);
/// * traços que chegaram de outro aparelho nunca são mexidos.
///
/// Passos que já não têm efeito (outro aparelho apagou o item) são pulados.
@immutable
class History {
  const History({this.limit = 100}) : _undo = const [], _redo = const [];

  const History._(this.limit, this._undo, this._redo);

  /// Máximo de passos guardados (os mais antigos caem).
  final int limit;
  final List<_Delta> _undo;
  final List<_Delta> _redo;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  int get undoCount => _undo.length;
  int get redoCount => _redo.length;

  /// Registra a edição `before → after` (limpa o "refazer"). Sem diferença,
  /// devolve este mesmo histórico.
  History record(PageDoc before, PageDoc after) {
    final added = <Object>[
      for (final s in after.strokes)
        if (!before.contains(s.id)) s,
      for (final t in after.texts)
        if (!before.contains(t.id)) t,
      for (final i in after.images)
        if (!before.contains(i.id)) i,
    ];
    final removed = <Object>[
      for (final s in before.strokes)
        if (!after.contains(s.id)) s,
      for (final t in before.texts)
        if (!after.contains(t.id)) t,
      for (final i in before.images)
        if (!after.contains(i.id)) i,
    ];
    if (added.isEmpty && removed.isEmpty) return this;
    return History._(limit, _push(_undo, _Delta(added, removed)), const []);
  }

  /// Desfaz a última edição sobre [current]. `null` se não houver o que
  /// desfazer. [newId] gera os ids das cópias revividas (padrão [newInkId]).
  HistoryStep? undo(PageDoc current, {String Function()? newId}) {
    final r = _apply(_undo, current, newId ?? newInkId);
    if (r == null) return null;
    return HistoryStep(
      History._(limit, r.rest, _push(_redo, r.done)),
      r.doc,
      r.idMap,
    );
  }

  /// Refaz a última edição desfeita sobre [current].
  HistoryStep? redo(PageDoc current, {String Function()? newId}) {
    final r = _apply(_redo, current, newId ?? newInkId);
    if (r == null) return null;
    return HistoryStep(
      History._(limit, _push(_undo, r.done), r.rest),
      r.doc,
      r.idMap,
    );
  }

  List<_Delta> _push(List<_Delta> stack, _Delta d) {
    final out = [...stack, d];
    if (out.length > limit) out.removeRange(0, out.length - limit);
    return List.unmodifiable(out);
  }

  /// Desfaz o topo de [stack] (pulando os que não têm mais efeito).
  ({List<_Delta> rest, _Delta done, PageDoc doc, Map<String, String> idMap})?
  _apply(List<_Delta> stack, PageDoc current, String Function() newId) {
    for (var k = stack.length - 1; k >= 0; k--) {
      final d = stack[k];
      final gone = <Object>[]; // itens vivos que este passo vai apagar
      for (final it in d.added) {
        final live = switch (it) {
          Stroke s => current.strokeById(s.id),
          TextBox t => current.textById(t.id),
          ImageBox i => current.imageById(i.id),
          _ => null,
        };
        if (live != null) gone.add(live);
      }
      final revive = [
        for (final it in d.removed)
          if (!current.contains(_idOf(it))) it,
      ];
      if (gone.isEmpty && revive.isEmpty) continue;

      var doc = current.without(d.added.map(_idOf));
      final idMap = <String, String>{};
      final born = <Object>[];
      for (final it in revive) {
        final nid = newId();
        idMap[_idOf(it)] = nid;
        doc = _withItem(doc, it, nid);
        born.add(switch (it) {
          Stroke() => doc.strokeById(nid)!,
          TextBox() => doc.textById(nid)!,
          ImageBox() => doc.imageById(nid)!,
          _ => it,
        });
      }
      return (
        rest: List.unmodifiable(stack.sublist(0, k)),
        done: _Delta(born, gone),
        doc: doc,
        idMap: Map.unmodifiable(idMap),
      );
    }
    return null;
  }
}
