import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/core/notebook_core.dart';

import 'test_support.dart';

PageDoc _doc(int n, int seed) {
  final r = Random(seed);
  return PageDoc.empty
      .withStrokes([for (var i = 0; i < n; i++) handwritingStroke(newInkId(), r)])
      .withText(mkText('t1'))
      .without(['gone']);
}

void main() {
  group('codificação reaproveita o JSON de cada traço', () {
    test('a saída é idêntica à de sempre (mesmo texto, mesmos bytes)', () {
      final doc = _doc(40, 1);
      final first = encodePage(doc);
      // 2ª chamada usa os fragmentos em cache e tem que dar exatamente o mesmo texto.
      expect(encodePage(doc), first);
      expect(decodePage(first), doc);
    });

    test('o JSON montado por fragmentos é o mesmo que jsonEncode daria ao mapa', () {
      final doc = _doc(25, 8);
      final json = pageJson(doc);
      expect(jsonEncode(jsonDecode(json)), json, reason: 'compacto, mesma ordem de chaves');
      expect(utf8.decode(gzip.decode(base64Decode(encodePage(doc)))), json);
      expect(pageJson(PageDoc.empty), '');
      expect(jsonDecode(pageJson(PageDoc.empty.without(['x']))), containsPair('deleted', ['x']));
    });

    test('só os traços novos são serializados de novo', () {
      final doc = _doc(100, 2);
      encodePage(doc);
      final before = PageCodecStats.strokesSerialized;
      final next = doc.withStroke(handwritingStroke(newInkId(), Random(9)));
      encodePage(next);
      expect(PageCodecStats.strokesSerialized - before, 1);
    });

    test('um traço decodificado também entra no cache depois da 1ª codificação', () {
      final doc = decodePage(encodePage(_doc(30, 3)));
      encodePage(doc);
      final before = PageCodecStats.strokesSerialized;
      encodePage(doc);
      expect(PageCodecStats.strokesSerialized, before);
    });
  });

  group('encodePageAsync', () {
    test('página pequena: mesmo resultado, sem sair da thread', () async {
      final doc = _doc(5, 4);
      expect(await encodePageAsync(doc), encodePage(doc));
      expect(await encodePageAsync(PageDoc.empty), '');
    });

    test('página grande vai para outro isolate e dá o mesmo resultado', () async {
      final doc = _doc(300, 5);
      final before = PageCodecStats.isolateRuns;
      final viaIsolate = await encodePageAsync(doc, inlineLimit: 0);
      expect(PageCodecStats.isolateRuns, before + 1);
      expect(viaIsolate, encodePage(doc));
      expect(decodePage(viaIsolate), doc);
    });

    test('abaixo do limite não usa isolate', () async {
      final doc = _doc(300, 6);
      final before = PageCodecStats.isolateRuns;
      await encodePageAsync(doc, inlineLimit: 100 * 1024 * 1024);
      expect(PageCodecStats.isolateRuns, before);
    });
  });

  test('decodePage conta as decodificações (para os testes do controller)', () {
    final data = encodePage(_doc(3, 7));
    final before = PageCodecStats.decodes;
    decodePage(data);
    expect(PageCodecStats.decodes, before + 1);
  });
}
