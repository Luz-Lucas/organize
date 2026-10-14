import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/intelligence/mlkit_recognizer.dart';
import 'package:organizacional/notebook/intelligence/recognizer.dart';

import '../core/test_support.dart';

const _channel = MethodChannel('google_mlkit_digital_ink_recognizer');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> calls;
  late Object? Function(MethodCall call) onCall;
  late InkDownloadPolicy policy;
  late MlKitInkRecognizer r;

  setUp(() {
    calls = [];
    onCall = (_) => null;
    policy = InkDownloadPolicy();
    r = MlKitInkRecognizer(policy: policy);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (c) async {
      calls.add(c);
      return onCall(c);
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null);
  });

  group('modelo', () {
    test('isModelReady pergunta ao ML Kit pelo modelo pt-BR', () async {
      onCall = (_) => true;
      expect(await r.isModelReady(), isTrue);
      expect(calls.single.arguments, {'task': 'check', 'model': 'pt-BR'});
      onCall = (_) => false;
      expect(await r.isModelReady(), isFalse);
    });

    test('se o modelo pt-BR não existe, usa pt (e lembra)', () async {
      onCall = (c) {
        final args = c.arguments as Map;
        if (args['model'] == 'pt-BR') throw PlatformException(code: 'Model Identifier error', message: 'No model was found');
        return true;
      };
      expect(await r.isModelReady(), isTrue);
      expect(calls.map((c) => (c.arguments as Map)['model']), ['pt-BR', 'pt']);
      calls.clear();
      expect(await r.isModelReady(), isTrue);
      expect(calls.map((c) => (c.arguments as Map)['model']), ['pt']);
    });

    test('isModelReady com erro da plataforma vira false (não quebra)', () async {
      onCall = (_) => throw PlatformException(code: 'x');
      expect(await r.isModelReady(), isFalse);
    });

    test('download só no Wi-Fi por padrão; com permissão, também em dados móveis', () async {
      onCall = (_) => 'success';
      expect(await r.downloadModel().toList(), [1.0]);
      expect((calls.single.arguments as Map)['wifi'], isTrue);
      expect((calls.single.arguments as Map)['task'], 'download');
      calls.clear();
      policy.allowMobileData = true;
      await r.downloadModel().drain<void>();
      expect((calls.single.arguments as Map)['wifi'], isFalse);
    });

    test('falha no download chega como erro do stream', () async {
      onCall = (_) => throw PlatformException(code: 'download', message: 'sem rede');
      await expectLater(r.downloadModel().toList(), throwsA(isA<PlatformException>()));
    });

    test('deleteModel apaga o modelo', () async {
      onCall = (_) => 'success';
      await r.deleteModel();
      expect(calls.single.arguments, {'task': 'delete', 'model': 'pt-BR'});
    });
  });

  group('recognize', () {
    Map<String, dynamic> inkOf(MethodCall c) => ((c.arguments as Map)['ink'] as Map).cast<String, dynamic>();

    test('traços viram tinta com tempo crescente; candidatos voltam na ordem do ML Kit', () async {
      onCall = (c) => [
            {'text': 'casa', 'score': 0.1},
            {'text': 'cara', 'score': 0.4},
          ];
      final a = lineStroke('a', const Offset(10, 20), const Offset(30, 20), n: 5);
      final b = lineStroke('b', const Offset(40, 20), const Offset(60, 20), n: 5);
      final out = await r.recognize([a, b]);
      expect(out, ['casa', 'cara']);
      final c = calls.single;
      expect(c.method, 'vision#startDigitalInkRecognizer');
      expect((c.arguments as Map)['model'], 'pt-BR');
      final strokes = (inkOf(c)['strokes'] as List).cast<Map>();
      expect(strokes, hasLength(2));
      final pts0 = (strokes[0]['points'] as List).cast<Map>();
      expect(pts0, hasLength(5));
      expect([pts0.first['x'], pts0.first['y']], [10.0, 20.0]);
      final times = [for (final s in strokes) for (final p in (s['points'] as List).cast<Map>()) p['t'] as int];
      for (var i = 1; i < times.length; i++) {
        expect(times[i], greaterThan(times[i - 1]), reason: 'tempo estritamente crescente');
      }
    });

    test('área escrita e contexto anterior vão junto', () async {
      onCall = (_) => [
            {'text': 'x', 'score': 0.0},
          ];
      await r.recognize([lineStroke('a', const Offset(0, 0), const Offset(5, 0))],
          writingArea: const Size(200, 40), preContext: 'olá ');
      final ctx = ((calls.single.arguments as Map)['context'] as Map).cast<String, dynamic>();
      expect(ctx['preContext'], 'olá ');
      expect(ctx['writingArea'], {'width': 200.0, 'height': 40.0});
    });

    test('sem traços não chama o ML Kit', () async {
      expect(await r.recognize(const []), isEmpty);
      expect(calls, isEmpty);
    });

    test('modelo ausente / erro da plataforma: lista vazia, sem exceção', () async {
      onCall = (_) => throw PlatformException(code: 'Model Error', message: 'Model has not been downloaded yet');
      expect(await r.recognize([lineStroke('a', const Offset(0, 0), const Offset(5, 0))]), isEmpty);
    });

    test('candidatos vazios ou em branco são descartados', () async {
      onCall = (_) => [
            {'text': '  ', 'score': 0.0},
            {'text': 'ok', 'score': 0.2},
          ];
      expect(await r.recognize([lineStroke('a', const Offset(0, 0), const Offset(5, 0))]), ['ok']);
    });
  });

  test('suportado', () => expect(r.supported, isTrue));
}
