import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/core/ink_math.dart';

void main() {
  group('distPointSegment', () {
    test('ponto sobre o segmento, ao lado e além das pontas', () {
      const a = Offset(0, 0), b = Offset(10, 0);
      expect(distPointSegment(const Offset(5, 0), a, b), 0);
      expect(distPointSegment(const Offset(5, 3), a, b), 3);
      expect(distPointSegment(const Offset(-3, 4), a, b), 5);
      expect(distPointSegment(const Offset(13, 4), a, b), 5);
    });
    test('segmento degenerado (ponto)', () {
      expect(distPointSegment(const Offset(3, 4), Offset.zero, Offset.zero), 5);
    });
  });

  group('distSegmentSegment', () {
    test('cruzando = 0', () {
      expect(
        distSegmentSegment(
          const Offset(0, 0),
          const Offset(10, 10),
          const Offset(0, 10),
          const Offset(10, 0),
        ),
        0,
      );
    });
    test('paralelos', () {
      expect(
        distSegmentSegment(
          const Offset(0, 0),
          const Offset(10, 0),
          const Offset(0, 4),
          const Offset(10, 4),
        ),
        4,
      );
    });
    test('pontas', () {
      expect(
        distSegmentSegment(
          const Offset(0, 0),
          const Offset(1, 0),
          const Offset(4, 4),
          const Offset(4, 10),
        ),
        5,
      );
    });
  });

  group('segmentCapsuleInterval', () {
    test('atravessa a cápsula pelo meio', () {
      // segmento (0,0)->(100,0); cápsula: ponto (50,0), raio 5
      final r = segmentCapsuleInterval(
        const Offset(0, 0),
        const Offset(100, 0),
        const Offset(50, 0),
        const Offset(50, 0),
        5,
      )!;
      expect(r.$1, closeTo(0.45, 1e-9));
      expect(r.$2, closeTo(0.55, 1e-9));
    });
    test('cápsula comprida perpendicular', () {
      final r = segmentCapsuleInterval(
        const Offset(0, 0),
        const Offset(100, 0),
        const Offset(50, -20),
        const Offset(50, 20),
        3,
      )!;
      expect(r.$1, closeTo(0.47, 1e-9));
      expect(r.$2, closeTo(0.53, 1e-9));
    });
    test('cápsula alinhada com o segmento', () {
      final r = segmentCapsuleInterval(
        const Offset(0, 0),
        const Offset(100, 0),
        const Offset(20, 2),
        const Offset(60, 2),
        4,
      )!;
      // o disco de raio 4 em (20,2) alcança x = 20 - sqrt(16-4)
      expect(r.$1, closeTo((20 - sqrt(12)) / 100, 1e-9));
      expect(r.$2, closeTo((60 + sqrt(12)) / 100, 1e-9));
    });
    test('não encosta -> null', () {
      expect(
        segmentCapsuleInterval(
          const Offset(0, 0),
          const Offset(100, 0),
          const Offset(50, 10),
          const Offset(50, 10),
          5,
        ),
        isNull,
      );
    });
    test('recorta em [0,1]', () {
      final r = segmentCapsuleInterval(
        const Offset(0, 0),
        const Offset(100, 0),
        const Offset(2, 0),
        const Offset(2, 0),
        5,
      )!;
      expect(r.$1, 0);
      expect(r.$2, closeTo(0.07, 1e-9));
    });
    test('segmento degenerado dentro da cápsula', () {
      final r = segmentCapsuleInterval(
        const Offset(50, 1),
        const Offset(50, 1),
        const Offset(50, 0),
        const Offset(50, 0),
        5,
      )!;
      expect(r.$1, 0);
      expect(r.$2, 1);
    });
  });

  group('pointInPolygon', () {
    final sq = [
      const Offset(0, 0),
      const Offset(10, 0),
      const Offset(10, 10),
      const Offset(0, 10),
    ];
    test('quadrado', () {
      expect(pointInPolygon(const Offset(5, 5), sq), isTrue);
      expect(pointInPolygon(const Offset(15, 5), sq), isFalse);
      expect(pointInPolygon(const Offset(-1, 5), sq), isFalse);
    });
    test('polígono côncavo (em U)', () {
      final u = [
        const Offset(0, 0),
        const Offset(30, 0),
        const Offset(30, 30),
        const Offset(20, 30),
        const Offset(20, 10),
        const Offset(10, 10),
        const Offset(10, 30),
        const Offset(0, 30),
      ];
      expect(pointInPolygon(const Offset(15, 20), u), isFalse); // no vão
      expect(pointInPolygon(const Offset(5, 20), u), isTrue);
      expect(pointInPolygon(const Offset(15, 5), u), isTrue);
    });
  });
}
