import 'package:organizacional/notebook/core/notebook_core.dart';

Stroke stroke(String id, {double x = 10}) => Stroke(
      id: id,
      tool: PenTool.pen,
      argb: 0xFF000000,
      width: 3,
      points: [InkPoint(x, 10, 0.5), InkPoint(x + 20, 30, 0.5)],
    );

PageDoc docOf(Iterable<String> ids) => PageDoc(strokes: [for (final id in ids) stroke(id)]);

String enc(Iterable<String> ids) => encodePage(docOf(ids));

Set<String> idsOf(String data) => {for (final s in decodePage(data).strokes) s.id};
