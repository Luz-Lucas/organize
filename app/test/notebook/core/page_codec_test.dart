import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/core/notebook_core.dart';

import 'test_support.dart';

String pack(Object json) =>
    base64Encode(gzip.encode(utf8.encode(jsonEncode(json))));

Map<String, dynamic> unpack(String data) =>
    jsonDecode(utf8.decode(gzip.decode(base64Decode(data))))
        as Map<String, dynamic>;

PageDoc sample() => PageDoc.empty
    .withStroke(
      Stroke(
        id: 's001',
        tool: PenTool.fountain,
        argb: 0xFF336699,
        width: 2.5,
        points: const [
          InkPoint(12.0, 34.5, 0.5),
          InkPoint(13.25, 35.04, 0.0),
          InkPoint(-4.6, 1000.0, 1.0),
        ],
      ),
    )
    .withStroke(
      Stroke(
        id: 's002',
        tool: PenTool.highlighter,
        argb: 0x80FFEB3B,
        width: 14,
        points: const [InkPoint(100, 100, 0.37)],
      ),
    )
    .withText(
      const TextBox(
        id: 't001',
        x: 10,
        y: 20.5,
        w: 300,
        text: 'Olá, "mundo"!\nlinha 2 \u{1F600} ç',
        size: 18,
        argb: 0xFF000000,
      ),
    )
    .withImage(
      const ImageBox(id: 'i001', x: 1, y: 2, w: 3.5, h: 4.5, path: 'u/n/i.png'),
    )
    .without({'velho1', 'velho2'});

void main() {
  group('decodePage / encodePage: vazio', () {
    test("decodePage('') devolve página vazia", () {
      expect(decodePage(''), PageDoc.empty);
      expect(decodePage('   \n'), PageDoc.empty);
    });

    test('página vazia codifica para string vazia', () {
      expect(encodePage(PageDoc.empty), '');
    });

    test('só tombstones NÃO é vazio (precisa propagar)', () {
      final d = PageDoc.empty.without({'x'});
      final s = encodePage(d);
      expect(s, isNotEmpty);
      expect(decodePage(s).deleted, {'x'});
    });
  });

  group('ida e volta', () {
    test('documento completo volta idêntico', () {
      final d = sample();
      expect(decodePage(encodePage(d)), d);
    });

    test('encode é determinístico e estável após decode', () {
      final e = encodePage(sample());
      expect(encodePage(decodePage(e)), e);
      expect(encodePage(sample()), e);
    });

    test('valores não quantizados são arredondados ao salvar', () {
      final d = PageDoc(
        strokes: [
          Stroke(
            id: 'a',
            tool: PenTool.pen,
            argb: 0xFF000000,
            width: 3.14159,
            points: const [
              InkPoint(1.23456, 2.98765, 0.456),
              InkPoint(9, 9, 2),
            ],
          ),
        ],
      );
      final back = decodePage(encodePage(d)).strokes.single;
      expect(back.points.first, const InkPoint(1.2, 3.0, 0.46));
      expect(back.points.last.p, 1.0, reason: 'pressão limitada a 0–1');
      expect(back.width, 3.14);
    });

    test('100 documentos aleatórios: decode(encode(x)) == x', () {
      final r = Random(7);
      for (var i = 0; i < 100; i++) {
        var d = PageDoc.empty;
        for (var k = 0; k < 1 + r.nextInt(6); k++) {
          d = d.withStroke(curveStroke(newInkId(), r, n: 1 + r.nextInt(30)));
        }
        if (r.nextBool()) d = d.withText(mkText(newInkId()));
        if (r.nextBool()) d = d.without({newInkId()});
        expect(decodePage(encodePage(d)), d, reason: 'caso $i');
      }
    });
  });

  group('formato JSON v1 -> gzip -> base64', () {
    test('fonte manuscrita: grava "font" só quando existe e volta igual', () {
      const t = TextBox(id: 't9', x: 1, y: 2, w: 80, text: 'gato', size: 30, argb: 0xFF000000, font: kHandwritingFont);
      final doc = PageDoc.empty.withText(t);
      final j = unpack(encodePage(doc));
      expect(((j['texts'] as List).single as Map)['font'], 'caveat');
      expect(decodePage(encodePage(doc)), doc);
      expect(decodePage(encodePage(doc)).texts.single.font, kHandwritingFont);
      // Página antiga (sem a chave) continua lendo, com a fonte padrão.
      final old = pack({
        'v': 1,
        'strokes': [],
        'texts': [
          {'id': 't1', 'x': 0, 'y': 0, 'w': 10, 'text': 'a', 'size': 12, 'color': '#000000FF'},
        ],
        'images': [],
        'deleted': [],
      });
      expect(decodePage(old).texts.single.font, isNull);
    });

    test('estrutura v1 (traços em deltas inteiros)', () {
      final j = unpack(encodePage(sample()));
      expect(j['v'], 1);
      final s = (j['strokes'] as List).first as Map<String, dynamic>;
      expect(s['id'], 's001');
      expect(s['tool'], 'fountain');
      expect(s['color'], '#336699FF');
      expect(s['width'], 2.5);
      // Forma compacta: inteiros (0,1 / 0,01), 1º ponto absoluto e o resto
      // em deltas em relação ao ponto anterior.
      expect(s['q'], [120, 345, 50, 13, 5, -50, -179, 9650, 100]);
      expect(s.containsKey('pts'), isFalse);
      expect(((j['strokes'] as List)[1] as Map)['color'], '#FFEB3B80');
      final t = (j['texts'] as List).single as Map<String, dynamic>;
      expect(t, {
        'id': 't001',
        'x': 10,
        'y': 20.5,
        'w': 300,
        'text': 'Olá, "mundo"!\nlinha 2 \u{1F600} ç',
        'size': 18,
        'color': '#000000FF',
      });
      final i = (j['images'] as List).single as Map<String, dynamic>;
      expect(i, {
        'id': 'i001',
        'x': 1,
        'y': 2,
        'w': 3.5,
        'h': 4.5,
        'path': 'u/n/i.png',
      });
      expect((j['deleted'] as List).toSet(), {'velho1', 'velho2'});
    });

    test('números inteiros saem sem ".0" (compacto)', () {
      final raw = utf8.decode(gzip.decode(base64Decode(encodePage(sample()))));
      expect(raw.contains('.0,'), isFalse);
      expect(raw.contains('.0]'), isFalse);
      expect(raw.contains('.0}'), isFalse);
      expect(raw.contains(' '), isTrue, reason: 'só no texto do usuário');
      expect(raw.contains('\n'), isFalse, reason: 'sem indentação');
    });

    test('lê também a forma literal da spec (pts absolutos em float)', () {
      final literal = pack({
        'v': 1,
        'strokes': [
          {
            'id': 's001',
            'tool': 'fountain',
            'color': '#336699FF',
            'width': 2.5,
            'pts': [12, 34.5, 0.5, 13.3, 35.0, 0, -4.6, 1000, 1],
          },
          {
            'id': 's002',
            'tool': 'highlighter',
            'color': '#FFEB3B80',
            'width': 14,
            'pts': [100, 100, 0.37],
          },
        ],
        'texts': [
          {
            'id': 't001',
            'x': 10,
            'y': 20.5,
            'w': 300,
            'text': 'Olá, "mundo"!\nlinha 2 \u{1F600} ç',
            'size': 18,
            'color': '#000000FF',
          },
        ],
        'images': [
          {
            'id': 'i001',
            'x': 1,
            'y': 2,
            'w': 3.5,
            'h': 4.5,
            'path': 'u/n/i.png',
          },
        ],
        'deleted': ['velho1', 'velho2'],
      });
      expect(decodePage(literal), sample());
    });

    test('é base64 padrão (sem quebras de linha)', () {
      final e = encodePage(sample());
      expect(e, matches(RegExp(r'^[A-Za-z0-9+/]+=*$')));
    });
  });

  group('erros claros', () {
    test('versão desconhecida', () {
      final e = pack({'v': 2, 'strokes': []});
      expect(
        () => decodePage(e),
        throwsA(
          isA<UnsupportedPageVersionException>()
              .having((x) => x.version, 'version', 2)
              .having((x) => x.message, 'message', contains('versão 2')),
        ),
      );
    });

    test('sem versão', () {
      expect(
        () => decodePage(pack({'strokes': []})),
        throwsA(isA<PageDecodeException>()),
      );
    });

    test('lixo que não é base64', () {
      expect(
        () => decodePage('isto não é base64!!'),
        throwsA(isA<PageDecodeException>()),
      );
    });

    test('base64 válido mas não é gzip', () {
      expect(
        () => decodePage(base64Encode(utf8.encode('{"v":1}'))),
        throwsA(isA<PageDecodeException>()),
      );
    });

    test('gzip com JSON inválido', () {
      expect(
        () => decodePage(base64Encode(gzip.encode(utf8.encode('{nao json')))),
        throwsA(isA<PageDecodeException>()),
      );
    });

    test('JSON que não é objeto', () {
      expect(
        () => decodePage(pack([1, 2])),
        throwsA(isA<PageDecodeException>()),
      );
    });

    test('pts com tamanho não múltiplo de 3', () {
      expect(
        () => decodePage(
          pack({
            'v': 1,
            'strokes': [
              {
                'id': 'a',
                'tool': 'pen',
                'color': '#000000FF',
                'width': 2,
                'pts': [1, 2],
              },
            ],
          }),
        ),
        throwsA(
          isA<PageDecodeException>().having(
            (e) => e.message,
            'message',
            contains('pts'),
          ),
        ),
      );
    });

    test('q (forma compacta) malformada', () {
      Map<String, dynamic> st(Object? q) => {
        'id': 'a',
        'tool': 'pen',
        'color': '#000000FF',
        'width': 2,
        'q': q,
      };
      for (final bad in [
        [1, 2],
        [],
        [1, 2, 3, 4],
        ['a', 'b', 'c'],
        [1.5, 2, 3],
        'x',
      ]) {
        expect(
          () => decodePage(
            pack({
              'v': 1,
              'strokes': [st(bad)],
            }),
          ),
          throwsA(isA<PageDecodeException>()),
          reason: '$bad',
        );
      }
    });

    test('traço sem pontos (nem q nem pts)', () {
      expect(
        () => decodePage(
          pack({
            'v': 1,
            'strokes': [
              {'id': 'a', 'tool': 'pen', 'color': '#000000FF', 'width': 2},
            ],
          }),
        ),
        throwsA(isA<PageDecodeException>()),
      );
    });

    test('ferramenta desconhecida e cor inválida', () {
      Map<String, dynamic> st(String tool, String color) => {
        'id': 'a',
        'tool': tool,
        'color': color,
        'width': 2,
        'pts': [1, 2, 0.5],
      };
      expect(
        () => decodePage(
          pack({
            'v': 1,
            'strokes': [st('giz', '#000000FF')],
          }),
        ),
        throwsA(isA<PageDecodeException>()),
      );
      expect(
        () => decodePage(
          pack({
            'v': 1,
            'strokes': [st('pen', 'preto')],
          }),
        ),
        throwsA(isA<PageDecodeException>()),
      );
    });

    test('campo obrigatório faltando', () {
      expect(
        () => decodePage(
          pack({
            'v': 1,
            'texts': [
              {'id': 't', 'x': 1},
            ],
          }),
        ),
        throwsA(isA<PageDecodeException>()),
      );
    });

    test('campos desconhecidos são ignorados e itens apagados filtrados', () {
      final d = decodePage(
        pack({
          'v': 1,
          'futuro': {'qualquer': 1},
          'strokes': [
            {
              'id': 'a',
              'tool': 'pen',
              'color': '#000000FF',
              'width': 2,
              'pts': [1, 2, 0.5],
              'extra': true,
            },
            {
              'id': 'b',
              'tool': 'pen',
              'color': '#000000FF',
              'width': 2,
              'pts': [1, 2, 0.5],
            },
          ],
          'deleted': ['b'],
        }),
      );
      expect(d.strokes.map((s) => s.id), ['a']);
      expect(d.deleted, {'b'});
    });
  });

  group('tamanho', () {
    test('2.000 traços x 100 pontos (escrita à mão) < 1,5 MB codificados', () {
      final r = Random(1);
      final d = PageDoc.empty.withStrokes([
        for (var i = 0; i < 2000; i++) handwritingStroke(newInkId(), r),
      ]);
      final e = encodePage(d);
      // ignore: avoid_print
      print('2000x100 pts (escrita): ${e.length} bytes codificados');
      expect(e.length, lessThan(1500000));
      expect(decodePage(e), d);
    });

    test('pior caso (pontos aleatórios, incompressíveis) cabe no limite '
        'de 4 MB do banco', () {
      final r = Random(1);
      final d = PageDoc.empty.withStrokes([
        for (var i = 0; i < 2000; i++) noiseStroke(newInkId(), r),
      ]);
      final e = encodePage(d);
      // ignore: avoid_print
      print('2000x100 pts (pior caso): ${e.length} bytes codificados');
      expect(e.length, lessThan(4000000));
      expect(decodePage(e).strokes.length, 2000);
    });
  });
}
