import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// Imagens já decodificadas de uma página, com dono claro do ciclo de vida:
///
/// * guarda um **clone** de cada `ImageInfo` (o original continua do stream) e
///   libera o clone ao trocar a imagem do caminho e em [dispose];
/// * [attach] usa só o **primeiro quadro** (GIF animado vira imagem parada) e
///   deixa de ouvir o stream logo depois, então a página não é regravada a
///   cada quadro e o decodificador não fica animando fora da tela.
class PageImageSet {
  final Map<String, ui.Image> _images = {};
  final Map<String, ImageInfo> _infos = {};
  final Map<String, (ImageStream, ImageStreamListener)> _listening = {};
  bool _disposed = false;

  /// Caminho -> imagem pronta (mapa estável, mutado no lugar).
  Map<String, ui.Image> get images => _images;

  bool has(String path) => _images.containsKey(path);

  void put(String path, ImageInfo info) {
    if (_disposed) return;
    final clone = info.clone();
    _infos.remove(path)?.dispose();
    _infos[path] = clone;
    _images[path] = clone.image;
  }

  /// Ouve [stream] até o primeiro quadro; chama [onFirstFrame] quando ele chega.
  void attach(String path, ImageStream stream, VoidCallback onFirstFrame) {
    if (_disposed || _listening.containsKey(path) || has(path)) return;
    late final ImageStreamListener l;
    l = ImageStreamListener(
      (info, _) {
        if (_disposed) return;
        // Só o primeiro quadro; depois disso para de ouvir (GIF não anima).
        _stop(path);
        if (has(path)) return;
        put(path, info);
        onFirstFrame();
      },
      onError: (_, _) => _stop(path),
    );
    _listening[path] = (stream, l);
    stream.addListener(l);
  }

  void _stop(String path) {
    final e = _listening.remove(path);
    if (e != null) e.$1.removeListener(e.$2);
  }

  void dispose() {
    _disposed = true;
    for (final path in _listening.keys.toList()) {
      _stop(path);
    }
    for (final info in _infos.values) {
      info.dispose();
    }
    _infos.clear();
    _images.clear();
  }
}
