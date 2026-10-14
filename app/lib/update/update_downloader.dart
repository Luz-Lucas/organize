import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;

/// Falha ao baixar (rede, servidor). [message] já está pronta para o usuário.
class UpdateDownloadException implements Exception {
  const UpdateDownloadException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// O arquivo baixado não é o que foi publicado (tamanho ou SHA-256 diferentes); já foi apagado.
class UpdateIntegrityException extends UpdateDownloadException {
  const UpdateIntegrityException(super.message);
}

/// O usuário cancelou o download.
class UpdateCancelled implements Exception {
  const UpdateCancelled();
}

/// Pedido de cancelamento, entregue ao download mesmo se a rede estiver parada.
class DownloadCancelToken {
  final _completer = Completer<void>();

  bool get isCancelled => _completer.isCompleted;
  Future<void> get whenCancelled => _completer.future;

  void cancel() {
    if (!_completer.isCompleted) _completer.complete();
  }
}

typedef DownloadProgress = void Function(int received, int total);

/// Baixa o pacote de atualização e só o entrega depois de conferir tamanho e SHA-256.
abstract interface class UpdateDownloader {
  /// Baixa [url] para [target] (gravando antes em `<target>.part`). Joga [UpdateIntegrityException] se o
  /// tamanho ou o SHA-256 não baterem, [UpdateCancelled] se [cancel] for acionado e [UpdateDownloadException]
  /// nas demais falhas. Em qualquer falha nenhum arquivo (nem parcial) fica no disco.
  Future<File> download({
    required Uri url,
    required File target,
    required String sha256,
    required int size,
    DownloadProgress? onProgress,
    DownloadCancelToken? cancel,
  });
}

class _DigestSink implements Sink<crypto.Digest> {
  crypto.Digest? value;
  @override
  void add(crypto.Digest data) => value = data;
  @override
  void close() {}
}

class HttpUpdateDownloader implements UpdateDownloader {
  HttpUpdateDownloader({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<File> download({
    required Uri url,
    required File target,
    required String sha256,
    required int size,
    DownloadProgress? onProgress,
    DownloadCancelToken? cancel,
  }) async {
    final part = File('${target.path}.part');
    IOSink? sink;
    StreamSubscription<List<int>>? sub;
    try {
      await target.parent.create(recursive: true);
      if (target.existsSync()) await target.delete();
      if (part.existsSync()) await part.delete();

      final http.StreamedResponse response;
      try {
        response = await _client.send(http.Request('GET', url));
      } on Exception {
        throw const UpdateDownloadException('Não foi possível baixar a atualização. Verifique a conexão.');
      }
      if (response.statusCode != 200) {
        throw UpdateDownloadException('O servidor recusou o download (erro ${response.statusCode}).');
      }

      sink = part.openWrite();
      final digest = _DigestSink();
      final hasher = crypto.sha256.startChunkedConversion(digest);
      var received = 0;
      final done = Completer<void>();
      Object? failure;

      sub = response.stream.listen(
        (chunk) {
          received += chunk.length;
          if (received > size) {
            failure = const UpdateIntegrityException(
                'O arquivo baixado é maior do que o publicado. Nada foi instalado.');
            sub?.cancel();
            if (!done.isCompleted) done.complete();
            return;
          }
          hasher.add(chunk);
          sink?.add(chunk);
          onProgress?.call(received, size);
        },
        onError: (Object e) {
          failure = const UpdateDownloadException(
              'A conexão caiu durante o download. Tente de novo.');
          if (!done.isCompleted) done.complete();
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        cancelOnError: true,
      );
      cancel?.whenCancelled.then((_) {
        failure ??= const UpdateCancelled();
        sub?.cancel();
        if (!done.isCompleted) done.complete();
      });

      await done.future;
      await sink.flush();
      await sink.close();
      sink = null;
      final problem = failure;
      if (problem != null) throw problem;

      if (received != size) {
        throw const UpdateIntegrityException(
            'O tamanho do arquivo baixado não confere com o publicado. Nada foi instalado.');
      }
      hasher.close();
      if (digest.value.toString() != sha256.toLowerCase()) {
        throw const UpdateIntegrityException(
            'A verificação de integridade (SHA-256) não confere: o arquivo baixado foi descartado. '
            'Nada foi instalado.');
      }
      await part.rename(target.path);
      return target;
    } catch (_) {
      try {
        // Sem await: cancelar uma assinatura parada só termina quando a fonte volta a andar.
        unawaited(sub?.cancel().catchError((_) {}) ?? Future<void>.value());
        await sink?.close();
      } catch (_) {}
      if (part.existsSync()) await part.delete();
      if (target.existsSync()) await target.delete();
      rethrow;
    }
  }
}
