import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/core/notebook_core.dart';
import 'package:organizacional/notebook/intelligence/ink_types.dart';
import 'package:organizacional/notebook/intelligence/recognizer.dart';
import 'package:organizacional/notebook/intelligence/transcript.dart';

import 'fake_recognizer.dart';
import 'handwriting.dart';

void main() {
  PageDoc doc6() => docWithStrokes(['a', 'b', 'c', 'd', 'e', 'f']);

  group('transcribe com segmentação injetada', () {
    test('texto da página = linhas reconhecidas separadas por \\n', () async {
      final doc = doc6();
      final lines = [
        inkLine([['a'], ['b']], top: 90),
        inkLine([['c'], ['d']], top: 140),
      ];
      final r = FakeInkRecognizer(table: {
        'a,b': ['olá mundo'],
        'c,d': ['segunda linha'],
      });
      final t = await transcribe(doc, r, segment: (_) => lines);
      expect(t.text, 'olá mundo\nsegunda linha');
    });

    test('palavras recebem o texto: chave = ids ordenados unidos por vírgula', () async {
      final doc = doc6();
      final lines = [
        inkLine([['b', 'a'], ['c']]), // ids fora de ordem dentro da palavra
      ];
      final r = FakeInkRecognizer(table: {
        'a,b,c': ['casa grande'],
      });
      final t = await transcribe(doc, r, segment: (_) => lines);
      expect(t.wordText, {'a,b': 'casa', 'c': 'grande'});
      expect(lines.single.words[0].text, 'casa');
      expect(lines.single.words[1].text, 'grande');
    });

    test('cada linha é reconhecida com a linha anterior como preContext e a área escrita', () async {
      final doc = doc6();
      final lines = [
        inkLine([['a'], ['b']], top: 90),
        inkLine([['c'], ['d']], top: 140),
        inkLine([['e']], top: 190),
      ];
      final r = FakeInkRecognizer(table: {
        'a,b': ['um dois'],
        'c,d': ['três quatro'],
        'e': ['cinco'],
      });
      await transcribe(doc, r, segment: (_) => lines);
      expect(r.calls.map((c) => c.preContext), ['', 'um dois', 'três quatro']);
      expect(r.calls.first.ids, ['a', 'b']);
      expect(r.calls.first.area, lines.first.bounds.size);
    });

    test('número de palavras diferente do texto da linha: reconhece palavra por palavra', () async {
      final doc = doc6();
      final lines = [
        inkLine([['a'], ['b'], ['c']]),
      ];
      final r = FakeInkRecognizer(table: {
        'a,b,c': ['totalmente errado e longo'], // 4 palavras para 3 grupos
        'a': ['bom', 'bem'],
        'b': ['dia'],
        'c': ['gente'],
      });
      final t = await transcribe(doc, r, segment: (_) => lines);
      expect(t.text, 'bom dia gente');
      expect(t.wordText, {'a': 'bom', 'b': 'dia', 'c': 'gente'});
      expect(lines.single.words.first.candidates, ['bom', 'bem']);
    });

    test('só uma chamada por linha quando as contagens batem', () async {
      final lines = [
        inkLine([['a'], ['b']]),
      ];
      final r = FakeInkRecognizer(table: {
        'a,b': ['ola mundo'],
      });
      await transcribe(docWithStrokes(['a', 'b']), r, segment: (_) => lines);
      expect(r.calls, hasLength(1));
    });

    test('linha sem reconhecimento fica de fora e as outras seguem', () async {
      final doc = doc6();
      final lines = [
        inkLine([['a']], top: 90),
        inkLine([['b']], top: 140),
        inkLine([['c']], top: 190),
      ];
      final r = FakeInkRecognizer(table: {
        'a': ['primeira'],
        'c': ['terceira'],
      });
      final t = await transcribe(doc, r, segment: (_) => lines);
      expect(t.text, 'primeira\nterceira');
      expect(t.wordText.keys, ['a', 'c']);
    });

    test('erro do reconhecedor numa linha não derruba a página', () async {
      final doc = doc6();
      final lines = [
        inkLine([['a']], top: 90),
        inkLine([['b']], top: 140),
      ];
      var n = 0;
      final r = FakeInkRecognizer(resolve: (s) {
        n++;
        if (n == 1) throw StateError('boom');
        return ['segunda'];
      });
      final t = await transcribe(doc, r, segment: (_) => lines);
      expect(t.text, 'segunda');
    });

    test('espaços extras e quebras viram um espaço só', () async {
      final lines = [
        inkLine([['a'], ['b']]),
      ];
      final r = FakeInkRecognizer(table: {
        'a,b': ['  ola \n  mundo  '],
      });
      final t = await transcribe(docWithStrokes(['a', 'b']), r, segment: (_) => lines);
      expect(t.text, 'ola mundo');
      expect(t.wordText, {'a': 'ola', 'b': 'mundo'});
    });

    test('lineCount conta as linhas segmentadas, mesmo as que não geraram texto', () async {
      final doc = doc6();
      final lines = [
        inkLine([['a']], top: 90),
        inkLine([['b']], top: 140),
        inkLine([['c']], top: 190),
      ];
      final r = FakeInkRecognizer(table: {'a': ['um']});
      final t = await transcribe(doc, r, segment: (_) => lines);
      expect(t.text, 'um');
      expect(t.lineCount, 3);
      expect(PageTranscript.empty.lineCount, 0);
    });

    test('página sem tinta: transcrição vazia e nenhuma chamada', () async {
      final r = FakeInkRecognizer();
      final t = await transcribe(PageDoc.empty, r, segment: (_) => const []);
      expect(t.text, '');
      expect(t.wordText, isEmpty);
      expect(r.calls, isEmpty);
    });

    test('NoopInkRecognizer dá transcrição vazia', () async {
      final lines = [
        inkLine([['a']]),
      ];
      final t = await transcribe(docWithStrokes(['a']), const NoopInkRecognizer(), segment: (_) => lines);
      expect(t.text, '');
      expect(t.wordText, isEmpty);
    });

    test('traço que sumiu do documento é ignorado', () async {
      final lines = [
        inkLine([['a'], ['fantasma']]),
      ];
      final r = FakeInkRecognizer(resolve: (s) => ['só']);
      final t = await transcribe(docWithStrokes(['a']), r, segment: (_) => lines);
      expect(r.calls.single.ids, ['a']);
      expect(t.text, 'só');
    });
  });

  test('cancelar no meio interrompe sem reconhecer o resto', () async {
    final doc = doc6();
    final lines = [
      inkLine([['a']], top: 90),
      inkLine([['b']], top: 140),
      inkLine([['c']], top: 190),
    ];
    final r = FakeInkRecognizer(resolve: (s) => ['x']);
    final t = await transcribe(doc, r, segment: (_) => lines, isCancelled: () => r.calls.isNotEmpty);
    expect(r.calls, hasLength(1));
    expect(t.text, 'x');
  });

  group('transcribe com a segmentação real (escrita sintética)', () {
    test('linhas e palavras de uma página escrita viram texto e wordText', () async {
      final page = writePage(['casa grande', 'segunda linha de teste']);
      final table = <String, List<String>>{
        for (final (i, text) in ['casa grande', 'segunda linha de teste'].indexed)
          wordKey([for (final s in page.lines[i].strokes) s.id]): [text],
      };
      final r = FakeInkRecognizer(table: table);
      final t = await transcribe(page.doc, r);
      expect(t.text, 'casa grande\nsegunda linha de teste');
      final expected = <String, String>{};
      for (final (i, text) in ['casa grande', 'segunda linha de teste'].indexed) {
        final words = text.split(' ');
        for (var w = 0; w < words.length; w++) {
          expected[wordKey(page.lines[i].wordIds[w])] = words[w];
        }
      }
      expect(t.wordText, expected);
      expect(r.calls, hasLength(2));
      expect(r.calls[1].preContext, 'casa grande');
    });

    test('página sem tinta não chama o reconhecedor', () async {
      final r = FakeInkRecognizer();
      final t = await transcribe(PageDoc.empty, r);
      expect(t.isEmpty, isTrue);
      expect(r.calls, isEmpty);
    });
  });

  group('PageTranscript', () {
    test('empty', () {
      expect(PageTranscript.empty.text, '');
      expect(PageTranscript.empty.wordText, isEmpty);
      expect(PageTranscript.empty.isEmpty, isTrue);
    });
  });
}
