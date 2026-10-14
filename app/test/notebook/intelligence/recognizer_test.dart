import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/intelligence/recognizer.dart';

import '../core/test_support.dart';

void main() {
  group('NoopInkRecognizer', () {
    const r = NoopInkRecognizer();

    test('não está disponível: modelo nunca pronto e plataforma sem suporte', () async {
      expect(r.supported, isFalse);
      expect(await r.isModelReady(), isFalse);
    });

    test('não reconhece nada e não quebra', () async {
      final s = lineStroke('a', const Offset(0, 0), const Offset(10, 0));
      expect(await r.recognize([s]), isEmpty);
      expect(await r.recognize([s], preContext: 'x'), isEmpty);
    });

    test('download não emite nada e termina; apagar não faz nada', () async {
      expect(await r.downloadModel().toList(), isEmpty);
      await r.deleteModel();
    });
  });
}
