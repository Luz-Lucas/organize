import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/email.dart';

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
}

final emailRepositoryProvider = Provider<EmailRepository>(
  (ref) => throw UnimplementedError('emailRepositoryProvider precisa de override'),
);

final emailStateProvider = StreamProvider<EmailState?>((ref) => ref.watch(emailRepositoryProvider).watchState());

final emailItemsProvider =
    StreamProvider<List<EmailItem>>((ref) => ref.watch(emailRepositoryProvider).watchItems(limit: 5));

/// Conta sugerida na tela de consentimento do Google.
const defaultGmailAccount = 'seu-contato@exemplo.com';
