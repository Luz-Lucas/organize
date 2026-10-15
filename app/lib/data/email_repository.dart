import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/email.dart';
import 'repository.dart';

abstract interface class EmailRepository {
  /// Situação da conta (null = nunca conectou).
  Stream<EmailState?> watchState();

  /// Mensagens recentes, da mais nova para a mais antiga.
  Stream<List<EmailItem>> watchItems({int limit = 10});

  /// URL de consentimento do Google (abrir no navegador). [email] sugere a conta.
  Future<Uri> connectUrl({String? email});

  /// Pede ao servidor uma sincronização agora.
  Future<void> syncNow();

  /// Revoga o acesso e apaga os dados do e-mail.
  Future<void> disconnect();

  /// Marca as mensagens (ids do Gmail) como lidas. Lança [EmailNeedsReconnect] se a conta
  /// ainda não deu a permissão de alterar.
  Future<void> markRead(List<String> ids);

  /// Marca como lidas todas as mensagens não lidas guardadas no app.
  Future<void> markAllRead();
}

/// A conta foi conectada só com leitura: é preciso reconectar para marcar como lida.
class EmailNeedsReconnect extends RepositoryException {
  const EmailNeedsReconnect() : super('Reconecte o Gmail para permitir marcar como lida.');
}

final emailRepositoryProvider = Provider<EmailRepository>(
  (ref) => throw UnimplementedError('emailRepositoryProvider precisa de override'),
);

final emailStateProvider = StreamProvider<EmailState?>((ref) => ref.watch(emailRepositoryProvider).watchState());

final emailItemsProvider =
    StreamProvider<List<EmailItem>>((ref) => ref.watch(emailRepositoryProvider).watchItems(limit: 5));

/// Conta sugerida na tela de consentimento do Google (`GMAIL_ACCOUNT` no
/// env.json; vazio = o Google pergunta a conta).
const defaultGmailAccount = String.fromEnvironment('GMAIL_ACCOUNT');
