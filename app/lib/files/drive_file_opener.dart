import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/drive_repository.dart';
import '../data/repository.dart';
import '../domain/drive.dart';
import 'drive_cache.dart';
import 'file_names.dart';
import 'files_platform.dart';

enum OpenOutcome {
  /// Abriu a cópia do aparelho (baixada agora ou já em dia).
  opened,

  /// Sem como conferir com o Drive: abriu a cópia que estava no aparelho, que pode estar desatualizada.
  openedStale,

  /// Arquivo nativo do Google (Docs, Planilhas...): não há o que baixar, abrir no navegador.
  needsBrowser,

  /// Baixou, mas nenhum app abriu o arquivo: oferecer "Abrir no Drive".
  notOpened,

  /// Não baixou ou não gravou: [OpenResult.message] explica.
  failed,

  /// O usuário cancelou o download.
  cancelled,
}

class OpenResult {
  const OpenResult(this.outcome, [this.message]);

  final OpenOutcome outcome;

  /// Em [OpenOutcome.failed], o motivo; em [OpenOutcome.openedStale], o aviso.
  final String? message;
}

/// Pedido de cancelamento de uma abertura em andamento.
class OpenCancel {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

const _staleMessage = 'Sem conexão: abri a cópia guardada no aparelho, que pode estar desatualizada.';
const _downloadFailed = 'Não foi possível baixar o arquivo. Tente de novo.';
const _storeFailed = 'Não foi possível guardar o arquivo no aparelho.';
const _unsupported = 'Abrir arquivos do Drive não é possível neste aparelho. Use "Abrir no Drive".';
const _incomplete = 'O download veio incompleto ou o arquivo mudou no Drive. Tente de novo.';

/// A resposta do servidor não diz nada sobre o arquivo (rede, Drive fora do ar, acesso expirado): dá para
/// usar a cópia do aparelho. Respostas definitivas (não encontrado, sem permissão, grande demais) não.
bool _unreachable(Object e) {
  if (e is DriveException) return e.code == null || e.code == 'unavailable' || e.needsReconnect;
  return true;
}

String _messageOf(Object e) => e is RepositoryException ? e.message : _downloadFailed;

/// Abre um arquivo do Drive pelo aparelho: confere os metadados atuais, usa a cópia guardada se for a mesma
/// (ou a única possível, sem rede) e senão baixa, guarda no cache persistente e abre no app padrão do sistema
/// para o tipo do arquivo.
class DriveFileOpener {
  DriveFileOpener({required this.drive, required this.platform, required this.cache});

  final DriveRepository drive;
  final FilesPlatform platform;
  final DriveCache cache;

  /// [onDownloading] avisa que a cópia local não serve e o download começou (a tela mostra progresso e
  /// "Cancelar"). Cancelar descarta o que foi baixado.
  Future<OpenResult> open(String fileId, {OpenCancel? cancel, void Function(DriveFileMeta meta)? onDownloading}) async {
    if (!platform.supported) return const OpenResult(OpenOutcome.failed, _unsupported);

    final DriveFileMeta meta;
    try {
      meta = await drive.meta(fileId);
    } catch (e) {
      if (!_unreachable(e)) return OpenResult(OpenOutcome.failed, _messageOf(e));
      final cached = await _lookup(fileId);
      if (cached == null) return OpenResult(OpenOutcome.failed, _messageOf(e));
      return _openCached(cached, null, stale: true);
    }
    if (cancel?.isCancelled ?? false) return const OpenResult(OpenOutcome.cancelled);
    if (meta.isGoogleNative) return const OpenResult(OpenOutcome.needsBrowser);

    final cached = await _lookup(fileId);
    if (cached != null && cached.toMeta().sameContentAs(meta)) return _openCached(cached, meta, stale: false);

    onDownloading?.call(meta);
    final Uint8List bytes;
    try {
      bytes = await drive.download(fileId);
    } catch (e) {
      if (cancel?.isCancelled ?? false) return const OpenResult(OpenOutcome.cancelled);
      if (cached != null && _unreachable(e)) return _openCached(cached, null, stale: true);
      return OpenResult(OpenOutcome.failed, _messageOf(e));
    }
    if (cancel?.isCancelled ?? false) return const OpenResult(OpenOutcome.cancelled);
    if (!_complete(meta, bytes)) return const OpenResult(OpenOutcome.failed, _incomplete);

    final CachedFile stored;
    try {
      stored = await cache.store(meta, bytes);
    } catch (_) {
      return const OpenResult(OpenOutcome.failed, _storeFailed);
    }
    return _openCached(stored, meta, stale: false);
  }

  /// O que chegou é o que o Drive anunciou? (tamanho e, havendo, md5)
  bool _complete(DriveFileMeta meta, Uint8List bytes) {
    if (meta.size != null && bytes.length != meta.size) return false;
    final md5 = meta.md5;
    return md5 == null || crypto.md5.convert(bytes).toString() == md5;
  }

  Future<CachedFile?> _lookup(String fileId) async {
    try {
      return await cache.lookup(fileId);
    } catch (_) {
      return null;
    }
  }

  Future<OpenResult> _openCached(CachedFile file, DriveFileMeta? meta, {required bool stale}) async {
    final mime = mimeForFile(file.name, meta?.mimeType);
    final opened = await platform.openFile(file.path, mime);
    if (!opened) return const OpenResult(OpenOutcome.notOpened);
    try {
      await cache.markOpened(file.fileId);
    } catch (_) {
      // só o último uso não foi atualizado
    }
    return stale ? const OpenResult(OpenOutcome.openedStale, _staleMessage) : const OpenResult(OpenOutcome.opened);
  }
}

/// A pasta persistente é pedida à plataforma só quando preciso.
final driveCacheProvider = Provider<DriveCache>((ref) => DriveCache.lazy(ref.watch(filesPlatformProvider).cacheRoot));

final driveFileOpenerProvider = Provider<DriveFileOpener>((ref) => DriveFileOpener(
      drive: ref.watch(driveRepositoryProvider),
      platform: ref.watch(filesPlatformProvider),
      cache: ref.watch(driveCacheProvider),
    ));
