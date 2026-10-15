import 'dart:async';
import 'dart:io' show NetworkInterface, Platform;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'recognizer.dart';

/// O reconhecedor de escrita desta plataforma. Padrão: [NoopInkRecognizer];
/// `main.dart` troca por `MlKitInkRecognizer` no Android.
final inkRecognizerProvider = Provider<InkRecognizer>((ref) => const NoopInkRecognizer());

/// Regra de rede do download (só Wi-Fi, a menos que o usuário confirme).
final inkDownloadPolicyProvider = Provider<InkDownloadPolicy>((ref) => InkDownloadPolicy());

/// Está no Wi-Fi? No Android olha as interfaces de rede ativas (`wlan*`/`eth*`);
/// os testes trocam por uma função fixa.
final inkWifiCheckProvider = Provider<Future<bool> Function()>((ref) => _onWifi);

Future<bool> _onWifi() async {
  if (kIsWeb || !Platform.isAndroid) return true;
  try {
    final all = await NetworkInterface.list(includeLoopback: false);
    return all.any((i) => (i.name.startsWith('wlan') || i.name.startsWith('eth')) && i.addresses.isNotEmpty);
  } catch (_) {
    return false; // sem certeza: melhor perguntar do que gastar dados móveis
  }
}

enum InkModelStatus { checking, missing, downloading, ready, error, unsupported }

class InkModelState {
  const InkModelState(this.status, {this.progress, this.error});

  final InkModelStatus status;

  /// 0–1 quando o reconhecedor informa; `null` = desconhecido (barra indeterminada).
  final double? progress;
  final String? error;

  @override
  bool operator ==(Object other) =>
      other is InkModelState && other.status == status && other.progress == progress && other.error == error;

  @override
  int get hashCode => Object.hash(status, progress, error);
}

enum InkDownloadOutcome { finished, failed, needsWifi, alreadyRunning, unsupported }

/// Estado do modelo de escrita (pt-BR): verificar, baixar (com progresso quando
/// houver), apagar. Usado pelo cartão "Escrita à mão" de Ajustes.
class InkModelManager extends Notifier<InkModelState> {
  bool _busy = false;

  InkRecognizer get _rec => ref.read(inkRecognizerProvider);

  @override
  InkModelState build() {
    final rec = ref.watch(inkRecognizerProvider);
    if (!rec.supported) return const InkModelState(InkModelStatus.unsupported);
    unawaited(refresh());
    return const InkModelState(InkModelStatus.checking);
  }

  /// Relê do aparelho se o modelo está pronto.
  Future<void> refresh() async {
    if (!_rec.supported || _busy) return;
    final ready = await _rec.isModelReady();
    if (!ref.mounted || _busy) return;
    state = InkModelState(ready ? InkModelStatus.ready : InkModelStatus.missing);
  }

  /// Baixa o modelo. Sem Wi-Fi e sem [allowMobileData] não baixa: devolve
  /// [InkDownloadOutcome.needsWifi] para a tela perguntar ao usuário.
  Future<InkDownloadOutcome> download({bool allowMobileData = false}) async {
    if (!_rec.supported) return InkDownloadOutcome.unsupported;
    if (_busy) return InkDownloadOutcome.alreadyRunning;
    if (!allowMobileData && !await ref.read(inkWifiCheckProvider)()) return InkDownloadOutcome.needsWifi;
    if (!ref.mounted) return InkDownloadOutcome.failed;
    if (_busy) return InkDownloadOutcome.alreadyRunning;
    _busy = true;
    final policy = ref.read(inkDownloadPolicyProvider);
    policy.allowMobileData = allowMobileData;
    state = const InkModelState(InkModelStatus.downloading);
    try {
      await for (final p in _rec.downloadModel()) {
        if (ref.mounted) state = InkModelState(InkModelStatus.downloading, progress: p.clamp(0.0, 1.0));
      }
      final ready = await _rec.isModelReady();
      _busy = false;
      if (ref.mounted) {
        state = ready
            ? const InkModelState(InkModelStatus.ready)
            : const InkModelState(InkModelStatus.error, error: 'Não foi possível baixar o modelo. Tente de novo.');
      }
      return ready ? InkDownloadOutcome.finished : InkDownloadOutcome.failed;
    } catch (e) {
      _busy = false;
      debugPrint('Caderno: download do modelo de escrita falhou: $e');
      if (ref.mounted) {
        state = InkModelState(
          InkModelStatus.error,
          error: 'Não foi possível baixar o modelo. Verifique a conexão e tente de novo.\n'
              'Detalhe: ${downloadErrorDetail(e)}',
        );
      }
      return InkDownloadOutcome.failed;
    } finally {
      _busy = false;
      policy.allowMobileData = false;
    }
  }

  /// Apaga o modelo do aparelho.
  Future<void> delete() async {
    if (!_rec.supported || _busy) return;
    await _rec.deleteModel();
    if (ref.mounted) state = const InkModelState(InkModelStatus.missing);
    await refresh();
  }
}

final inkModelManagerProvider = NotifierProvider<InkModelManager, InkModelState>(InkModelManager.new);

/// O motivo técnico de uma falha no download, curto o bastante para a tela
/// (o reconhecedor do Android devolve o código e a mensagem da exceção nativa).
String downloadErrorDetail(Object e) {
  final text = switch (e) {
    PlatformException(:final code, :final message) => message == null || message.isEmpty ? code : '$code: $message',
    StateError(:final message) => message,
    _ => e.toString(),
  };
  return text.length > 200 ? '${text.substring(0, 200)}…' : text;
}
