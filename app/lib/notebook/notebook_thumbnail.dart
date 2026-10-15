import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide TextBox;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/notebook_core.dart';
import 'data/notebook_page.dart';
import 'state/notebook_providers.dart';

// ---------------------------------------------------------------------------
// Dados leves da miniatura (o que atravessa o isolate e fica em cache)
// ---------------------------------------------------------------------------

const int _maxPointsPerStroke = 48;

/// Um traço reduzido (≤ 48 pontos, `x0,y0,x1,y1…` em unidades de página).
class ThumbStroke {
  const ThumbStroke(this.argb, this.width, this.xy);
  final int argb;
  final double width;
  final Float32List xy;
}

class ThumbData {
  const ThumbData(this.strokes, {this.background});
  final List<ThumbStroke> strokes;

  /// A página de PDF de fundo (caminho no Storage e onde fica, em unidades de página).
  final ({String path, Rect rect})? background;
}

/// Descompacta e reduz a página para a miniatura. Função de nível superior e
/// sem estado: roda em outro isolate. Devolve `null` para página vazia/inválida.
ThumbData? decodeThumb(String data) {
  if (data.isEmpty) return null;
  final PageDoc doc;
  try {
    doc = decodePage(data);
  } on PageDecodeException {
    return null;
  }
  if (doc.isEmpty) return null;
  final out = <ThumbStroke>[];
  for (final s in doc.strokes) {
    final pts = s.points;
    final step = (pts.length / _maxPointsPerStroke).ceil().clamp(1, 1 << 20);
    final xy = <double>[pts.first.x, pts.first.y];
    for (var i = step; i < pts.length; i += step) {
      xy
        ..add(pts[i].x)
        ..add(pts[i].y);
    }
    xy
      ..add(pts.last.x)
      ..add(pts.last.y);
    out.add(ThumbStroke(s.argb, s.width, Float32List.fromList(xy)));
  }
  final bg = doc.images.where((i) => i.background).firstOrNull;
  return ThumbData(out, background: bg == null ? null : (path: bg.path, rect: bg.bounds));
}

/// Páginas com texto codificado até este tamanho são decodificadas na hora (o
/// custo é menor que subir um isolate); as maiores vão para fora da UI.
const int kThumbInlineMaxChars = 8000;

/// Como decodificar páginas grandes (trocável nos testes).
@visibleForTesting
Future<ThumbData?> Function(String data) thumbnailDecoder = (data) => compute(decodeThumb, data);

// ---------------------------------------------------------------------------
// Cache e política de releitura
// ---------------------------------------------------------------------------

/// Guarda as miniaturas já decodificadas por nota + conteúdo (hash do `data`) e
/// limita a releitura da 1ª página: `updated_at` muda a cada save, mas a lista
/// só busca de novo no máximo a cada [minRefetch] por caderno.
class ThumbnailCache {
  ThumbnailCache({
    Duration Function()? now,
    this.minRefetch = const Duration(seconds: 30),
    this.maxEntries = 64,
  }) : _now = now ?? _wall;

  static final Stopwatch _sw = Stopwatch()..start();
  static Duration _wall() => _sw.elapsed;

  final Duration Function() _now;
  final Duration minRefetch;
  final int maxEntries;

  final Map<String, (int stamp, Duration at)> _fetch = {};
  final LinkedHashMap<String, ThumbData?> _decoded = LinkedHashMap();

  /// A chave de leitura a usar agora para [noteId]: a atual do widget, ou a
  /// anterior se a última leitura foi há menos de [minRefetch].
  int stampFor(String noteId, int widgetStamp) {
    final now = _now();
    final e = _fetch[noteId];
    if (e == null || e.$1 == widgetStamp || now - e.$2 >= minRefetch) {
      if (e == null || e.$1 != widgetStamp) _fetch[noteId] = (widgetStamp, now);
      return widgetStamp;
    }
    return e.$1;
  }

  /// Quanto falta para poder reler [noteId] (zero se já pode).
  Duration untilRefetch(String noteId) {
    final e = _fetch[noteId];
    if (e == null) return Duration.zero;
    final left = minRefetch - (_now() - e.$2);
    return left.isNegative ? Duration.zero : left;
  }

  static String keyOf(String noteId, String data) => '$noteId|${data.length}|${data.hashCode}';

  (bool, ThumbData?) lookup(String noteId, String data) {
    final k = keyOf(noteId, data);
    if (!_decoded.containsKey(k)) return (false, null);
    final v = _decoded.remove(k);
    _decoded[k] = v; // mais recente
    return (true, v);
  }

  void store(String noteId, String data, ThumbData? value) {
    _decoded[keyOf(noteId, data)] = value;
    while (_decoded.length > maxEntries) {
      _decoded.remove(_decoded.keys.first);
    }
  }

  void clear() {
    _fetch.clear();
    _decoded.clear();
  }
}

/// Cache do app todo (os testes trocam por um com relógio próprio).
@visibleForTesting
ThumbnailCache thumbnailCache = ThumbnailCache();

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

/// Miniatura da 1ª página de um caderno (papel branco com os traços reduzidos).
/// Não ocupa espaço (e não pinta nada) enquanto carrega ou se a página está vazia.
///
/// A leitura da página só se repete a cada 30 s por caderno (e quando a lista
/// constrói o item, ou seja, quando ele fica visível); a decodificação de
/// páginas grandes roda fora da thread da interface e fica em cache.
class NotebookThumbnail extends ConsumerStatefulWidget {
  const NotebookThumbnail({super.key, required this.noteId, required this.stamp, this.width = 24});

  final String noteId;

  /// Muda quando o caderno é salvo (ex.: `updatedAt` da nota); a releitura é
  /// limitada por [ThumbnailCache.minRefetch].
  final int stamp;
  final double width;

  @override
  ConsumerState<NotebookThumbnail> createState() => _NotebookThumbnailState();
}

class _NotebookThumbnailState extends ConsumerState<NotebookThumbnail> {
  Timer? _timer;
  ThumbData? _thumb;
  String? _shownKey;
  String? _pendingKey;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _scheduleRefetch(int effective) {
    if (effective == widget.stamp || _timer != null) return;
    _timer = Timer(thumbnailCache.untilRefetch(widget.noteId) + const Duration(milliseconds: 50), () {
      _timer = null;
      if (mounted) setState(() {});
    });
  }

  /// Coloca em [_thumb] a miniatura de [page] (do cache, na hora ou fora da UI).
  void _resolve(NotebookPage page) {
    final data = page.data;
    final key = ThumbnailCache.keyOf(widget.noteId, data);
    if (key == _shownKey || key == _pendingKey) return;
    final hit = thumbnailCache.lookup(widget.noteId, data);
    if (hit.$1) {
      _thumb = hit.$2;
      _shownKey = key;
      return;
    }
    if (data.length <= kThumbInlineMaxChars) {
      final t = decodeThumb(data);
      thumbnailCache.store(widget.noteId, data, t);
      _thumb = t;
      _shownKey = key;
      return;
    }
    _pendingKey = key;
    final noteId = widget.noteId;
    thumbnailDecoder(data).then((t) {
      thumbnailCache.store(noteId, data, t);
      if (!mounted || _pendingKey != key) return;
      setState(() {
        _thumb = t;
        _shownKey = key;
        _pendingKey = null;
      });
    }, onError: (_) {
      if (!mounted || _pendingKey != key) return;
      setState(() {
        _thumb = null;
        _shownKey = key;
        _pendingKey = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final stamp = thumbnailCache.stampFor(widget.noteId, widget.stamp);
    _scheduleRefetch(stamp);
    final page = ref.watch(notebookFirstPageProvider((noteId: widget.noteId, stamp: stamp))).value;
    if (page == null || page.data.isEmpty) return const SizedBox.shrink();
    _resolve(page);
    final thumb = _thumb;
    if (thumb == null) return const SizedBox.shrink();
    final line = Theme.of(context).dividerColor;
    return Container(
      key: ValueKey('notebook-thumb-${widget.noteId}'),
      width: widget.width,
      height: widget.width * pageHeight / pageWidth,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: line, width: 0.5),
        borderRadius: BorderRadius.circular(2),
      ),
      clipBehavior: Clip.antiAlias,
      child: thumb.background == null
          ? CustomPaint(painter: _ThumbPainter(thumb))
          : Stack(
              fit: StackFit.expand,
              children: [
                _ThumbBackground(noteId: widget.noteId, bg: thumb.background!, scale: widget.width / pageWidth),
                CustomPaint(painter: _ThumbPainter(thumb)),
              ],
            ),
    );
  }
}

/// A página de PDF de fundo na miniatura (carregada pelo store de imagens do caderno).
class _ThumbBackground extends ConsumerStatefulWidget {
  const _ThumbBackground({required this.noteId, required this.bg, required this.scale});

  final String noteId;
  final ({String path, Rect rect}) bg;
  final double scale;

  @override
  ConsumerState<_ThumbBackground> createState() => _ThumbBackgroundState();
}

class _ThumbBackgroundState extends ConsumerState<_ThumbBackground> {
  static final _cache = <String, Future<ImageProvider>>{};
  Future<ImageProvider>? _image;

  @override
  void initState() {
    super.initState();
    try {
      final store = ref.read(notebookImageStoreFactoryProvider)(widget.noteId);
      final path = widget.bg.path;
      _image = _cache.putIfAbsent(path, () {
        final f = store.load(path);
        f.then((_) {}, onError: (Object _) {
          _cache.remove(path); // falhou: tenta de novo depois
        });
        return f;
      });
    } catch (_) {
      _image = null; // sem store (testes): só os traços
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.bg.rect;
    final s = widget.scale;
    return Stack(
      children: [
        Positioned(
          left: r.left * s,
          top: r.top * s,
          width: r.width * s,
          height: r.height * s,
          child: FutureBuilder<ImageProvider>(
            future: _image,
            builder: (context, snap) => snap.hasData
                ? Image(image: snap.data!, fit: BoxFit.fill, filterQuality: FilterQuality.medium)
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}

class _ThumbPainter extends CustomPainter {
  _ThumbPainter(this.thumb);

  final ThumbData thumb;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / pageWidth;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final s in thumb.strokes) {
      final xy = s.xy;
      final path = Path()..moveTo(xy[0] * k, xy[1] * k);
      for (var i = 2; i + 1 < xy.length; i += 2) {
        path.lineTo(xy[i] * k, xy[i + 1] * k);
      }
      paint
        ..color = Color(s.argb)
        ..strokeWidth = (s.width * k).clamp(0.6, 6.0);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_ThumbPainter old) => !identical(old.thumb, thumb);
}
