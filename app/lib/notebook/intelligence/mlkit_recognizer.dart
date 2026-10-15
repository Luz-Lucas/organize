import 'dart:ui' show Size;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart' as mlkit;

import '../core/notebook_core.dart';
import 'recognizer.dart';

/// Reconhecimento de escrita à mão do ML Kit (Digital Ink Recognition), só Android.
///
/// O modelo de idioma (~20 MB) **não** vem no APK: é baixado em tempo de execução
/// ([downloadModel]) e fica no aparelho até [deleteModel]. O plugin não informa
/// bytes baixados, então o download emite só o `1.0` final.
class MlKitInkRecognizer extends InkRecognizer {
  MlKitInkRecognizer({InkDownloadPolicy? policy, this.tags = const ['pt-BR', 'pt']})
      : policy = policy ?? InkDownloadPolicy();

  final InkDownloadPolicy policy;

  /// Etiquetas de idioma em ordem de preferência: usa a primeira que o ML Kit conhece.
  final List<String> tags;

  final _models = mlkit.DigitalInkRecognizerModelManager();
  final _recognizers = <String, mlkit.DigitalInkRecognizer>{};
  String? _tag;

  /// Passo de tempo sintético entre pontos de um traço e pausa entre traços (ms):
  /// o `InkPoint` do caderno não guarda o instante, e o ML Kit exige tempo crescente.
  static const _pointMs = 8;
  static const _gapMs = 150;

  /// Roda [op] com a etiqueta resolvida; se o ML Kit não conhece a etiqueta
  /// ("Model Identifier error"), tenta a próxima. Lembra a que funcionou.
  Future<T> _withTag<T>(Future<T> Function(String tag) op) async {
    final known = _tag;
    if (known != null) return op(known);
    PlatformException? last;
    for (final tag in tags) {
      try {
        final r = await op(tag);
        _tag = tag;
        return r;
      } on PlatformException catch (e) {
        final unknown = e.code == 'Model Identifier error' || e.code == 'Failed to create model identifier';
        if (!unknown) rethrow;
        last = e;
      }
    }
    throw last ?? StateError('Nenhum modelo de idioma disponível');
  }

  @override
  Future<bool> isModelReady() async {
    try {
      return await _withTag((tag) => _models.isModelDownloaded(tag));
    } catch (e) {
      debugPrint('Caderno: não foi possível consultar o modelo de escrita: $e');
      return false;
    }
  }

  @override
  Stream<double> downloadModel() async* {
    final ok = await _withTag((tag) => _models.downloadModel(tag, isWifiRequired: policy.wifiRequired));
    if (!ok) throw StateError('O download do modelo não terminou.');
    yield 1.0;
  }

  @override
  Future<void> deleteModel() async {
    try {
      await _withTag((tag) async {
        await _recognizers.remove(tag)?.close();
        return _models.deleteModel(tag);
      });
    } catch (e) {
      debugPrint('Caderno: não foi possível apagar o modelo de escrita: $e');
    }
  }

  @override
  Future<List<String>> recognize(List<Stroke> strokes, {Size? writingArea, String preContext = ''}) async {
    if (strokes.isEmpty) return const [];
    final ink = mlkit.Ink();
    var t = 0;
    for (final s in strokes) {
      final out = mlkit.Stroke();
      for (final p in s.points) {
        out.points.add(mlkit.StrokePoint(x: p.x, y: p.y, t: t));
        t += _pointMs;
      }
      ink.strokes.add(out);
      t += _gapMs;
    }
    final context = (writingArea == null && preContext.isEmpty)
        ? null
        : mlkit.DigitalInkRecognitionContext(
            preContext: preContext,
            writingArea: writingArea == null
                ? null
                : mlkit.WritingArea(width: writingArea.width, height: writingArea.height),
          );
    try {
      final candidates = await _withTag((tag) {
        final rec = _recognizers.putIfAbsent(tag, () => mlkit.DigitalInkRecognizer(languageCode: tag));
        return rec.recognize(ink, context: context);
      });
      return [
        for (final c in candidates)
          if (c.text.trim().isNotEmpty) c.text,
      ];
    } on PlatformException catch (e) {
      // Modelo ainda não baixado, ou falha do ML Kit: sem texto, a escrita segue normal.
      debugPrint('Caderno: reconhecimento falhou (${e.code}): ${e.message}');
      return const [];
    }
  }
}
