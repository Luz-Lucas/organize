import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/drive.dart';
import 'repository.dart';

/// Erro do Drive com o código devolvido pelo servidor (`auth_required`, `not_connected`...).
class DriveException extends RepositoryException {
  const DriveException(super.message, {this.code});

  final String? code;

  bool get needsReconnect => code == 'auth_required' || code == 'not_connected';
}

abstract interface class DriveRepository {
  /// Situação da conta (null = nunca conectou).
  Stream<DriveState?> watchState();

  /// URL de consentimento do Google (abrir no navegador). [email] sugere a conta.
  Future<Uri> connectUrl({String? email});

  /// Revoga o acesso e apaga os dados guardados do Drive.
  Future<void> disconnect();

  /// Conteúdo de uma pasta; [folderId] nulo = raiz "Organizacional"; `'root'` = Meu Drive.
  Future<DriveListing> list({String? folderId});

  Future<DriveSearchResult> search(String query);
  Future<DriveItem> createFolder(String parentId, String name);

  /// Acha a pasta [name] em [parentId] ou cria.
  Future<DriveItem> ensureFolder(String parentId, String name);
  Future<void> rename(String id, String name);
  Future<void> move(String id, String toFolderId);
  Future<void> trash(String id);
  Future<void> restore(String id);

  Future<void> share(String id, String email, DriveRole role, {bool notify = false});

  /// Liga/desliga o link público (somente leitura); devolve o link do arquivo.
  Future<String?> setLinkSharing(String id, bool enabled);
  Future<List<DrivePermission>> permissions(String id);
  Future<void> unshare(String id, String permissionId);

  /// Metadados atuais de um arquivo (data, tamanho e md5), para saber se a cópia do aparelho ainda vale.
  Future<DriveFileMeta> meta(String id);

  /// Baixa o conteúdo de um arquivo (até 50 MB; arquivos nativos do Google, como Docs, não). Lança
  /// [DriveException] com a mensagem do servidor quando o Drive recusa.
  Future<Uint8List> download(String id);

  /// Acha ou cria cada pasta de [path] a partir do Meu Drive (ex.: `['Organizacional', 'Samsung Notes']`)
  /// e devolve o id da última.
  Future<String> ensurePath(List<String> path);

  /// Arquivo (fora da lixeira) enviado com `appProperties.sha256 == [sha256]`; null se não houver.
  Future<DriveItem?> findBySha256(String sha256);

  /// Envia [data] (exatamente [size] bytes) para [parentId]. [appProperties] (opcional, só `sha256`)
  /// fica gravado no arquivo do Drive e permite achá-lo depois por `findBySha256`.
  Future<UploadedFile> upload({
    required String parentId,
    required String name,
    required String mimeType,
    required int size,
    required Stream<List<int>> data,
    void Function(int sent, int total)? onProgress,
    Map<String, String>? appProperties,
  });
}

final driveRepositoryProvider = Provider<DriveRepository>(
  (ref) => throw UnimplementedError('driveRepositoryProvider precisa de override'),
);

final driveStateProvider = StreamProvider<DriveState?>((ref) => ref.watch(driveRepositoryProvider).watchState());

/// Conta sugerida na tela de consentimento do Google.
const defaultDriveAccount = 'sua-conta@exemplo.com';
