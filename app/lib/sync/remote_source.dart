/// Erro ao falar com a nuvem. O sincronizador só distingue os dois tipos abaixo.
sealed class SyncError implements Exception {
  const SyncError(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Falha que passa sozinha (sem rede, tempo esgotado, 5xx, 429, sessão renovando): a alteração
/// continua na fila e é enviada de novo mais tarde.
class TransientSyncError extends SyncError {
  const TransientSyncError(super.message);
}

/// A nuvem recusou a alteração de vez (regra de segurança, violação de restrição…): reenviar não adianta.
class PermanentSyncError extends SyncError {
  const PermanentSyncError(super.message);
}

enum RemoteChangeType { upsert, delete }

/// Mudança vinda da nuvem em tempo real. No `delete`, [row] tem ao menos a chave da linha.
class RemoteChange {
  const RemoteChange(this.type, this.row);

  final RemoteChangeType type;
  final Map<String, dynamic> row;
}

/// A nuvem, como o sincronizador a enxerga. Os métodos lançam [TransientSyncError] ou [PermanentSyncError].
abstract interface class RemoteSource {
  Future<List<Map<String, dynamic>>> fetchAll(String tbl);

  Future<void> upsert(String tbl, List<Map<String, dynamic>> rows);

  Future<void> delete(String tbl, List<String> ids);

  /// Mudanças em tempo real da tabela. Um erro no stream significa que eventos podem ter se perdido.
  Stream<RemoteChange> changes(String tbl);
}
