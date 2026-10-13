import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide TextBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/core/notebook_core.dart';

import 'menu_support.dart';
import 'ui_support.dart';

void main() {
  testWidgets('borracha parcial: um gesto longo grava tombstone só do traço que existia antes', (tester) async {
    final s = FakeSession(
      docs: [
        PageDoc.empty.withStroke(testStroke('a1', const Offset(100, 300), const Offset(900, 300), n: 160)),
      ],
    );
    await pumpNotebook(tester, s);
    await tester.tap(find.byKey(const ValueKey('nb-tool-eraser')));
    await tester.pump();
    await tapMenu(tester, 'nb-eraser-mode');
    // A borracha anda ao longo do traço: cada movimento corta de novo os pedaços do anterior.
    await SimPointer(tester, PointerDeviceKind.stylus).drag(
      linePath(const Offset(120, 300), const Offset(880, 300), n: 40),
    );
    final doc = s.updates.last.doc;
    expect(doc.deleted, {'a1'}, reason: 'pedaços intermediários não deixam tombstone');
    expect(doc.strokes.every((e) => e.id != 'a1'), isTrue);
  });

  testWidgets('desfazer a borracha parcial ainda traz o traço de volta', (tester) async {
    final s = FakeSession(
      docs: [
        PageDoc.empty.withStroke(testStroke('a1', const Offset(100, 300), const Offset(900, 300), n: 160)),
      ],
    );
    await pumpNotebook(tester, s);
    await tester.tap(find.byKey(const ValueKey('nb-tool-eraser')));
    await tester.pump();
    await tapMenu(tester, 'nb-eraser-mode');
    await SimPointer(tester, PointerDeviceKind.stylus).drag(
      linePath(const Offset(400, 250), const Offset(400, 350), n: 8),
    );
    expect(s.docOf(0).strokes, hasLength(2));
    await tester.tap(find.byKey(const ValueKey('nb-undo')));
    await tester.pump();
    expect(s.docOf(0).strokes, hasLength(1));
  });
}
