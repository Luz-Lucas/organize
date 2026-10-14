import 'dart:ui' hide TextBox;

import 'package:flutter/foundation.dart';

import '../core/notebook_core.dart';
import 'stroke_grid.dart';
import 'tool_settings.dart';

/// Um gesto de borracha, processado **em lotes** (um por quadro) e sem mexer no
/// [PageDoc] até o fim:
///
/// * os eventos do ponteiro só entram na fila ([add]); a S Pen manda ~240/s e a
///   tela só desenha 60/s, então o trabalho é feito uma vez por quadro
///   ([flush]) com o caminho acumulado;
/// * só os traços da vizinhança do caminho são testados (grade espacial);
/// * traços apagados ficam em [removed] e os pedaços da borracha parcial em
///   [created]; quem desenha esconde `removed` e acrescenta `created` sem
///   recalcular contornos;
/// * [result] monta o documento final uma única vez, com tombstones.
class EraseSession {
  EraseSession({
    required this.base,
    required this.mode,
    StrokeGrid? index,
    this.radius = kEraserRadius,
    String Function()? newId,
  }) : _index = index ?? StrokeGrid.build(base.strokes),
       _newId = newId ?? newInkId;

  final PageDoc base;
  final EraserMode mode;
  final double radius;
  final StrokeGrid _index;
  final StrokeGrid _extraIndex = StrokeGrid.empty();
  final String Function() _newId;

  final List<Offset> _queue = [];
  Offset? _last;
  final Set<String> _removed = {};
  final Map<String, Stroke> _created = {};
  List<Stroke> _createdView = const [];

  /// Sobe a cada [flush] que mudou o que se vê (para o cache do Picture).
  int revision = 0;

  /// Quantos traços foram testados contra a borracha (diagnóstico/testes).
  int candidatesTested = 0;

  /// Ids escondidos (traços do documento e pedaços já apagados). O conjunto é
  /// compartilhado e mutável: use [revision] para saber se mudou.
  Set<String> get removed => _removed;

  /// Pedaços vivos criados pela borracha parcial, na ordem de criação.
  List<Stroke> get created => _createdView;

  bool get changed => _removed.isNotEmpty;
  bool get hasPending => _queue.isNotEmpty;

  void add(Offset p) => _queue.add(p);
  void addAll(Iterable<Offset> ps) => _queue.addAll(ps);

  /// Processa o que está na fila como um lote. Devolve `true` se algo mudou.
  bool flush() {
    if (_queue.isEmpty) return false;
    final path = <Offset>[?_last, ..._queue];
    _last = _queue.last;
    _queue.clear();

    var zone = Rect.fromPoints(path.first, path.first);
    for (final p in path) {
      zone = zone.expandToInclude(Rect.fromPoints(p, p));
    }
    zone = zone.inflate(radius + 1);
    final candidates = <Stroke>[
      for (final s in _index.query(zone))
        if (!_removed.contains(s.id)) s,
      for (final s in _extraIndex.query(zone))
        if (!_removed.contains(s.id)) s,
    ];
    if (candidates.isEmpty) return false;
    candidatesTested += candidates.length;
    final cand = PageDoc(strokes: candidates);

    var changed = false;
    if (mode == EraserMode.partial) {
      final res = erasePartial(cand, path, radius, _newId);
      if (!identical(res, cand)) {
        changed = true;
        for (final id in res.deleted) {
          _removed.add(id);
          _created.remove(id);
        }
        for (final s in res.strokes) {
          if (!cand.contains(s.id)) {
            _created[s.id] = s;
            _extraIndex.add(s);
          }
        }
      }
    } else {
      final hits = <String>{};
      if (path.length == 1) {
        hits.addAll(hitStrokes(cand, path.first, radius));
      } else {
        for (var i = 0; i + 1 < path.length; i++) {
          hits.addAll(hitStrokes(cand, path[i + 1], radius, from: path[i]));
        }
      }
      for (final id in hits) {
        if (_removed.add(id)) {
          changed = true;
          _created.remove(id);
        }
      }
    }
    if (changed) {
      _createdView = List.unmodifiable(_created.values);
      revision++;
    }
    return changed;
  }

  /// Documento final do gesto (o próprio [base] se nada foi apagado).
  PageDoc result() {
    if (_removed.isEmpty) return base;
    final d = base.without(_removed);
    return _created.isEmpty ? d : d.withStrokes(_created.values);
  }
}

/// Estado da borracha em andamento para o painter dos traços prontos: ele
/// repinta (sem reconstruir a árvore de widgets) quando o preview muda.
class ErasePreview extends ChangeNotifier {
  bool active = false;
  Set<String> hidden = const {};
  List<Stroke> extra = const [];
  int revision = 0;

  void show(EraseSession s) {
    active = true;
    hidden = s.removed;
    extra = s.created;
    revision = s.revision;
    notifyListeners();
  }

  void clear() {
    if (!active) return;
    active = false;
    hidden = const {};
    extra = const [];
    revision = 0;
    notifyListeners();
  }
}
