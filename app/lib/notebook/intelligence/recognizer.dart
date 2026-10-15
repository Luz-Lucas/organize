import 'dart:ui' show Size;

import '../core/notebook_core.dart';

/// Reconhecimento de escrita à mão (tinta → texto), em pt-BR.
///
/// A implementação real é o `MlKitInkRecognizer` (só Android). Nas outras
/// plataformas, e nos testes, usa-se o [NoopInkRecognizer]: nada quebra, só não
/// há texto.
abstract class InkRecognizer {
  const InkRecognizer();

  /// A plataforma consegue reconhecer? `false` no [NoopInkRecognizer] (Linux,
  /// Windows, web): a interface esconde as ações que dependem disso.
  bool get supported => true;

  /// O modelo de idioma está no aparelho e pronto para uso?
  Future<bool> isModelReady();

  /// Baixa o modelo. Emite o progresso de 0 a 1 **quando conhecido** (o ML Kit
  /// não informa bytes: só termina); completa quando o modelo está pronto e
  /// emite erro se falhar.
  Stream<double> downloadModel();

  /// Apaga o modelo do aparelho (libera ~20 MB).
  Future<void> deleteModel() async {}

  /// Candidatos de texto para [strokes], do mais provável ao menos. Vazio se não
  /// há modelo ou nada foi reconhecido. [writingArea] é o tamanho da área escrita
  /// (ajuda o modelo) e [preContext] o texto que vem antes (a linha anterior).
  Future<List<String>> recognize(List<Stroke> strokes, {Size? writingArea, String preContext = ''});
}

/// Não reconhece nada (Linux, Windows, web, testes).
class NoopInkRecognizer extends InkRecognizer {
  const NoopInkRecognizer();

  @override
  bool get supported => false;

  @override
  Future<bool> isModelReady() async => false;

  @override
  Stream<double> downloadModel() => const Stream<double>.empty();

  @override
  Future<List<String>> recognize(List<Stroke> strokes, {Size? writingArea, String preContext = ''}) async =>
      const [];
}

/// Regra de rede do download do modelo. O padrão é **só Wi-Fi**; a tela de Ajustes
/// liga [allowMobileData] quando o usuário confirma baixar com dados móveis.
class InkDownloadPolicy {
  bool allowMobileData = false;

  /// O ML Kit deve exigir Wi-Fi neste download?
  bool get wifiRequired => !allowMobileData;
}
