import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/ui/page_images.dart';

class _Completer extends ImageStreamCompleter {
  void emit(ImageInfo info) => setImage(info);
}

void main() {
  late ui.Image a, b;

  setUp(() async {
    a = await createTestImage(width: 4, height: 4);
    b = await createTestImage(width: 8, height: 8);
  });

  test('put guarda um clone e dispose libera o clone, nunca o original do stream', () {
    final set = PageImageSet();
    final info = ImageInfo(image: a);
    set.put('x', info);
    final shown = set.images['x']!;
    expect(shown.width, 4);
    expect(shown.debugDisposed, isFalse);
    set.dispose();
    expect(shown.debugDisposed, isTrue, reason: 'o clone é liberado ao desmontar');
    expect(a.debugDisposed, isFalse, reason: 'o original pertence ao stream');
    expect(set.images, isEmpty);
  });

  test('trocar a imagem do mesmo caminho libera a anterior', () {
    final set = PageImageSet();
    set.put('x', ImageInfo(image: a));
    final old = set.images['x']!;
    set.put('x', ImageInfo(image: b));
    expect(old.debugDisposed, isTrue);
    expect(set.images['x']!.width, 8);
    expect(set.images['x']!.debugDisposed, isFalse);
    set.dispose();
  });

  test('GIF animado: só o primeiro quadro é usado e o stream deixa de ser ouvido', () {
    final set = PageImageSet();
    final completer = _Completer();
    final keep = completer.keepAlive(); // o teste emite depois de o stream ficar sem ouvintes
    addTearDown(keep.dispose);
    var notified = 0;
    set.attach('g', ImageStream()..setCompleter(completer), () => notified++);
    completer.emit(ImageInfo(image: a));
    expect(notified, 1);
    final first = set.images['g']!;
    expect(completer.hasListeners, isFalse, reason: 'sem ouvir, o decodificador para de animar');
    completer.emit(ImageInfo(image: b.clone()));
    completer.emit(ImageInfo(image: b.clone()));
    expect(notified, 1, reason: 'nenhum regravo da página por quadro');
    expect(set.images['g'], same(first));
    expect(first.width, 4);
    set.dispose();
  });

  test('dispose antes de a imagem chegar não vaza nem notifica', () {
    final set = PageImageSet();
    final completer = _Completer();
    final keep = completer.keepAlive(); // o teste emite depois de o stream ficar sem ouvintes
    addTearDown(keep.dispose);
    var notified = 0;
    set.attach('g', ImageStream()..setCompleter(completer), () => notified++);
    expect(completer.hasListeners, isTrue);
    set.dispose();
    expect(completer.hasListeners, isFalse);
    completer.emit(ImageInfo(image: a));
    expect(notified, 0);
    expect(set.images, isEmpty);
  });
}
