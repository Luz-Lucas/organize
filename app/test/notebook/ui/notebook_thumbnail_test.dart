import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart' hide TextBox;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/core/notebook_core.dart';
import 'package:organizacional/notebook/data/notebook_page.dart';
import 'package:organizacional/notebook/notebook_thumbnail.dart';
import 'package:organizacional/notebook/state/notebook_providers.dart';

Stroke _s(String id, int n) => Stroke(
  id: id,
  tool: PenTool.pen,
  argb: 0xFF000000,
  width: 3,
  points: [for (var i = 0; i < n; i++) InkPoint(10.0 + i, 20.0 + (i % 5), 0.5)],
);

String smallData() => encodePage(PageDoc(strokes: [_s('a', 5), _s('b', 5)]));

String bigData() {
  final r = Random(3);
  return encodePage(
    PageDoc(
      strokes: [
        for (var i = 0; i < 300; i++)
          Stroke(
            id: 's${i.toString().padLeft(4, '0')}',
            tool: PenTool.pen,
            argb: 0xFF000000,
            width: 3,
            points: [for (var k = 0; k < 40; k++) InkPoint(r.nextDouble() * 900, r.nextDouble() * 1300, r.nextDouble())],
          ),
      ],
    ),
  );
}

void main() {
  tearDown(() {
    thumbnailCache = ThumbnailCache();
  });

  group('decodeThumb', () {
    test('reduz cada traço a no máximo 50 pontos', () {
      final t = decodeThumb(encodePage(PageDoc(strokes: [_s('a', 500)])))!;
      expect(t.strokes, hasLength(1));
      expect(t.strokes.single.xy.length ~/ 2, lessThanOrEqualTo(50));
      expect(t.strokes.single.xy.first, closeTo(10, 0.2));
      expect(t.strokes.single.xy[t.strokes.single.xy.length - 2], closeTo(509, 0.2), reason: 'o último ponto fica');
    });

    test('página vazia, vazio ou inválido não vira miniatura', () {
      expect(decodeThumb(''), isNull);
      expect(decodeThumb(encodePage(PageDoc.empty)), isNull);
      expect(decodeThumb('isso não é uma página'), isNull);
    });
  });

  test('o decodificador padrão roda de verdade em outro isolate', () async {
    final data = bigData();
    final t = await compute(decodeThumb, data);
    expect(t, isNotNull);
    expect(t!.strokes, hasLength(300));
    expect(t.strokes.first.xy.length ~/ 2, lessThanOrEqualTo(50));
  });

  group('ThumbnailCache', () {
    test('releitura no máximo a cada 30 s por caderno', () {
      var now = Duration.zero;
      final c = ThumbnailCache(now: () => now);
      expect(c.stampFor('n1', 100), 100, reason: 'primeira leitura');
      now = const Duration(seconds: 5);
      expect(c.stampFor('n1', 101), 100, reason: 'salvou de novo: ainda vale a anterior');
      now = const Duration(seconds: 29);
      expect(c.stampFor('n1', 102), 100);
      expect(c.untilRefetch('n1'), const Duration(seconds: 1));
      now = const Duration(seconds: 31);
      expect(c.stampFor('n1', 102), 102, reason: 'passou o intervalo');
      now = const Duration(seconds: 32);
      expect(c.stampFor('n1', 103), 102);
      expect(c.stampFor('outro', 7), 7, reason: 'cada caderno tem o seu relógio');
    });

    test('cache por nota + conteúdo, com limite', () {
      final c = ThumbnailCache(maxEntries: 2);
      c.store('n', 'a', null);
      c.store('n', 'b', const ThumbData([]));
      expect(c.lookup('n', 'a').$1, isTrue);
      c.store('n', 'c', null);
      expect(c.lookup('n', 'b').$1, isFalse, reason: 'o menos recente saiu');
      expect(c.lookup('n', 'a').$1, isTrue);
      expect(c.lookup('m', 'a').$1, isFalse, reason: 'outra nota');
    });
  });

  group('NotebookThumbnail', () {
    late List<int> fetched;
    late String data;

    Future<void> pump(WidgetTester tester, {required int stamp, Key? key, String noteId = 'n1'}) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notebookFirstPageProvider.overrideWith((ref, k) async {
              fetched.add(k.stamp);
              return NotebookPage(id: 'p1', noteId: k.noteId, idx: 0, data: data);
            }),
          ],
          child: MaterialApp(
            home: Scaffold(body: NotebookThumbnail(key: key, noteId: noteId, stamp: stamp)),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    setUp(() {
      fetched = [];
      data = smallData();
    });

    testWidgets('página pequena aparece na hora e sem usar o decodificador de fora da UI', (tester) async {
      var calls = 0;
      thumbnailDecoder = (d) async {
        calls++;
        return decodeThumb(d);
      };
      await pump(tester, stamp: 1);
      expect(find.byKey(const ValueKey('notebook-thumb-n1')), findsOneWidget);
      expect(calls, 0);
    });

    testWidgets('página grande: decodifica fora da UI, mostra quando termina e guarda em cache', (tester) async {
      data = bigData();
      expect(data.length, greaterThan(kThumbInlineMaxChars), reason: 'o teste precisa de uma página grande');
      final done = Completer<ThumbData?>();
      var calls = 0;
      thumbnailDecoder = (d) {
        calls++;
        return done.future;
      };
      await pump(tester, stamp: 1);
      expect(calls, 1);
      expect(find.byKey(const ValueKey('notebook-thumb-n1')), findsNothing, reason: 'ainda decodificando, sem travar a UI');
      done.complete(decodeThumb(data));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('notebook-thumb-n1')), findsOneWidget);

      // reconstruir o widget (outro item da lista, rolagem…) reaproveita o cache
      await tester.pumpWidget(const SizedBox());
      await pump(tester, stamp: 1);
      expect(calls, 1, reason: 'mesmo conteúdo: não decodifica de novo');
      expect(find.byKey(const ValueKey('notebook-thumb-n1')), findsOneWidget);
    });

    testWidgets('mesmo conteúdo com updated_at novo não decodifica de novo (nota + hash do data)', (tester) async {
      data = bigData();
      var now = Duration.zero;
      thumbnailCache = ThumbnailCache(now: () => now);
      var calls = 0;
      thumbnailDecoder = (d) async {
        calls++;
        return decodeThumb(d);
      };
      await pump(tester, stamp: 1);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      expect(calls, 1);
      expect(find.byKey(const ValueKey('notebook-thumb-n1')), findsOneWidget);
      // a lista é reaberta depois do intervalo: a página é relida (stamp novo), mas é o mesmo desenho
      await tester.pumpWidget(const SizedBox());
      now = const Duration(seconds: 100);
      await pump(tester, stamp: 2);
      expect(fetched, [1, 2]);
      expect(calls, 1, reason: 'o hash do data é o mesmo');
      expect(find.byKey(const ValueKey('notebook-thumb-n1')), findsOneWidget);
    });

    testWidgets('salvar várias vezes seguidas relê a página no máximo a cada 30 s', (tester) async {
      var now = Duration.zero;
      thumbnailCache = ThumbnailCache(now: () => now);
      await pump(tester, stamp: 1);
      expect(fetched, [1]);
      now = const Duration(seconds: 3);
      await pump(tester, stamp: 2);
      now = const Duration(seconds: 6);
      await pump(tester, stamp: 3);
      expect(fetched, [1], reason: 'saves dentro dos 30 s não releem');
      expect(find.byKey(const ValueKey('notebook-thumb-n1')), findsOneWidget, reason: 'segue mostrando a anterior');

      now = const Duration(seconds: 31);
      await tester.pump(const Duration(seconds: 31));
      await tester.pump();
      expect(fetched, [1, 3], reason: 'passado o intervalo, relê com o stamp mais novo');
    });
  });
}
