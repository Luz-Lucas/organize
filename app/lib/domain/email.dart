import 'json.dart';

enum EmailStatus {
  notConnected,
  ok,
  authRequired,
  error;

  static EmailStatus parse(Object? raw) => switch (raw) {
        'ok' => ok,
        'auth_required' => authRequired,
        'error' => error,
        _ => notConnected,
      };
}

/// Situação da conta Gmail conectada (uma linha por usuário em `email_state`).
class EmailState {
  const EmailState({
    this.accountEmail,
    this.unreadCount = 0,
    this.status = EmailStatus.notConnected,
    this.lastSyncedAt,
    this.message,
  });

  final String? accountEmail;
  final int unreadCount;
  final EmailStatus status;
  final DateTime? lastSyncedAt;
  final String? message;

  bool get connected => status == EmailStatus.ok || status == EmailStatus.authRequired || status == EmailStatus.error;

  factory EmailState.fromMap(Map<String, dynamic> m) => EmailState(
        accountEmail: m['account_email'] as String?,
        unreadCount: (m['unread_count'] as num?)?.toInt() ?? 0,
        status: EmailStatus.parse(m['status']),
        lastSyncedAt: parseDate(m['last_synced_at']),
        message: m['message'] as String?,
      );
}

/// Uma mensagem (só cabeçalhos) de `email_items`.
class EmailItem {
  const EmailItem({
    required this.id,
    this.fromName,
    this.fromAddr,
    this.subject,
    this.receivedAt,
    this.unread = false,
  });

  final String id;
  final String? fromName;
  final String? fromAddr;
  final String? subject;
  final DateTime? receivedAt;
  final bool unread;

  /// Remetente para exibição: nome, senão o endereço.
  String get sender {
    final n = fromName?.trim() ?? '';
    if (n.isNotEmpty) return n;
    final a = fromAddr?.trim() ?? '';
    return a.isNotEmpty ? a : 'Remetente desconhecido';
  }

  String get title {
    final s = subject?.trim() ?? '';
    return s.isEmpty ? '(sem assunto)' : s;
  }

  factory EmailItem.fromMap(Map<String, dynamic> m) => EmailItem(
        id: m['gmail_id'] as String,
        fromName: m['from_name'] as String?,
        fromAddr: m['from_addr'] as String?,
        subject: m['subject'] as String?,
        receivedAt: parseDate(m['received_at']),
        unread: m['unread'] as bool? ?? false,
      );
}
