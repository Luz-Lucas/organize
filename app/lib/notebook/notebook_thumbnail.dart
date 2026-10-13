import 'package:flutter/material.dart' hide TextBox;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/notebook_core.dart';
import 'state/notebook_providers.dart';

/// Miniatura da 1ª página de um caderno (papel branco com os traços reduzidos).
/// Não ocupa espaço (e não pinta nada) enquanto carrega ou se a página está vazia.
class NotebookThumbnail extends ConsumerWidget {
  const NotebookThumbnail({super.key, required this.noteId, required this.stamp, this.width = 24});

  final String noteId;

  /// Muda quando o caderno é salvo (ex.: `updatedAt` da nota), para reler a página.
  final int stamp;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(notebookFirstPageProvider((noteId: noteId, stamp: stamp))).value;
    if (page == null || page.data.isEmpty) return const SizedBox.shrink();
    PageDoc doc;
    try {
      doc = decodePage(page.data);
    } on PageDecodeException {
      return const SizedBox.shrink();
    }
    if (doc.isEmpty) return const SizedBox.shrink();
    final line = Theme.of(context).dividerColor;
    return Container(
      key: ValueKey('notebook-thumb-$noteId'),
      width: width,
      height: width * pageHeight / pageWidth,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: line, width: 0.5),
        borderRadius: BorderRadius.circular(2),
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(painter: _ThumbPainter(doc)),
    );
  }
}

class _ThumbPainter extends CustomPainter {
  _ThumbPainter(this.doc);

  final PageDoc doc;

  static const _maxPointsPerStroke = 48;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / pageWidth;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final s in doc.strokes) {
      final pts = s.points;
      final step = (pts.length / _maxPointsPerStroke).ceil().clamp(1, 1 << 20);
      final path = Path()..moveTo(pts.first.x * k, pts.first.y * k);
      for (var i = step; i < pts.length; i += step) {
        path.lineTo(pts[i].x * k, pts[i].y * k);
      }
      path.lineTo(pts.last.x * k, pts.last.y * k);
      paint
        ..color = Color(s.argb)
        ..strokeWidth = (s.width * k).clamp(0.6, 6.0);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_ThumbPainter old) => !identical(old.doc, doc);
}
