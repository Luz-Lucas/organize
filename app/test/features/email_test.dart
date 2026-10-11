import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_email_repository.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/email.dart';
import 'package:organizacional/features/email/email_card.dart';

import '../helpers.dart';

const _phone = Size(360, 900);

EmailItem _mail(String id, String from, String subject, DateTime at, {bool unread = true}) =>
    EmailItem(id: id, fromName: from, subject: subject, receivedAt: at, unread: unread);

Future<void> _reveal(WidgetTester tester, Key key) async {
  await tester.scrollUntilVisible(find.byKey(key), 300, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

void main() {
  group('domínio', () {
    test('EmailState.fromMap e status desconhecido', () {
      final s = EmailState.fromMap({
        'account_email': 'a@b.c',
        'unread_count': 7,
        'status': 'ok',
        'last_synced_at': '2026-09-28T12:00:00Z',
      });
      expect(s.status, EmailStatus.ok);
      expect(s.unreadCount, 7);
      expect(s.connected, isTrue);
      expect(EmailState.fromMap({'status': 'qualquer'}).status, EmailStatus.notConnected);
    });

    test('EmailItem cai para endereço e "(sem assunto)"', () {
      const m = EmailItem(id: '1', fromAddr: 'x@y.z');
      expect(m.sender, 'x@y.z');
      expect(m.title, '(sem assunto)');
      expect(const EmailItem(id: '2').sender, 'Remetente desconhecido');
    });

    test('emailAgoLabel', () {
      final now = DateTime(2026, 9, 28, 12);
      expect(emailAgoLabel(now.subtract(const Duration(seconds: 20)), now), 'agora');
      expect(emailAgoLabel(now.subtract(const Duration(minutes: 5)), now), 'há 5 min');
      expect(emailAgoLabel(now.subtract(const Duration(hours: 3)), now), 'há 3 h');
      expect(emailAgoLabel(now.subtract(const Duration(hours: 30)), now), 'ontem');
      expect(emailAgoLabel(DateTime(2026, 9, 20), now), '20 set');
    });
  });

  group('cartão na Início', () {
    testWidgets('não conectado convida a abrir Ajustes', (tester) async {
      await pumpApp(tester, MemoryRepository(), size: _phone);
      expect(find.byKey(const Key('email-card')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('email-open-settings')));
      expect(find.byKey(const Key('email-open-settings')), findsOneWidget);
    });

    testWidgets('conectado mostra não lidos e mensagens', (tester) async {
      final repo = MemoryEmailRepository(
        state: const EmailState(status: EmailStatus.ok, unreadCount: 3, accountEmail: 'c@g.com'),
        items: [
          _mail('1', 'Banco', 'Fatura disponível', defaultNow.subtract(const Duration(minutes: 5))),
          _mail('2', 'Professor', 'Aviso da prova', defaultNow.subtract(const Duration(hours: 2)), unread: false),
        ],
      );
      await pumpApp(tester, MemoryRepository(), size: _phone, emailRepo: repo);
      await tester.ensureVisible(find.byKey(const Key('email-card')));
      await tester.pumpAndSettle();
      expect(find.text('3 não lidos'), findsOneWidget);
      expect(find.text('Banco'), findsOneWidget);
      expect(find.text('Fatura disponível'), findsOneWidget);
      expect(find.text('há 5 min'), findsOneWidget);
      expect(find.text('há 2 h'), findsOneWidget);
    });

    testWidgets('atualizar chama a sincronização', (tester) async {
      final repo = MemoryEmailRepository(state: const EmailState(status: EmailStatus.ok));
      await pumpApp(tester, MemoryRepository(), size: _phone, emailRepo: repo);
      await tester.ensureVisible(find.byKey(const Key('email-refresh')));
      await tester.tap(find.byKey(const Key('email-refresh')));
      await tester.pumpAndSettle();
      expect(repo.syncCalls, 1);
      expect(find.text('Nenhuma mensagem recente'), findsOneWidget);
    });

    testWidgets('acesso expirado pede reconexão', (tester) async {
      final repo = MemoryEmailRepository(state: const EmailState(status: EmailStatus.authRequired));
      await pumpApp(tester, MemoryRepository(), size: _phone, emailRepo: repo);
      await tester.ensureVisible(find.byKey(const Key('email-reconnect')));
      expect(find.byKey(const Key('email-reconnect')), findsOneWidget);
    });

    testWidgets('erro de sincronização mantém a lista e avisa', (tester) async {
      final repo = MemoryEmailRepository(
        state: const EmailState(status: EmailStatus.error, unreadCount: 1),
        items: [_mail('1', 'Alguém', 'Oi', defaultNow)],
      );
      await pumpApp(tester, MemoryRepository(), size: _phone, emailRepo: repo);
      await tester.ensureVisible(find.byKey(const Key('email-error')));
      expect(find.byKey(const Key('email-error')), findsOneWidget);
      expect(find.text('Alguém'), findsOneWidget);
    });
  });

  group('Ajustes', () {
    testWidgets('conectar abre a URL de consentimento sugerindo a conta', (tester) async {
      final opened = <Uri>[];
      final repo = MemoryEmailRepository();
      await pumpApp(tester, MemoryRepository(),
          location: '/ajustes', size: _phone, emailRepo: repo, openLink: (u) async {
        opened.add(u);
        return true;
      });
      await _reveal(tester, const Key('gmail-connect'));
      await tester.tap(find.byKey(const Key('gmail-connect')));
      await tester.pumpAndSettle();
      expect(opened, [repo.connectUri]);
      expect(repo.lastConnectEmail, 'seu-contato@exemplo.com');
      expect(find.byKey(const Key('gmail-info')), findsOneWidget);
    });

    testWidgets('falha ao conectar mostra erro', (tester) async {
      final repo = MemoryEmailRepository()..failActions = true;
      await pumpApp(tester, MemoryRepository(), location: '/ajustes', size: _phone, emailRepo: repo);
      await _reveal(tester, const Key('gmail-connect'));
      await tester.tap(find.byKey(const Key('gmail-connect')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('gmail-error')), findsOneWidget);
    });

    testWidgets('desconectar pede confirmação e apaga', (tester) async {
      final repo = MemoryEmailRepository(
        state: const EmailState(status: EmailStatus.ok, accountEmail: 'c@g.com'),
      );
      await pumpApp(tester, MemoryRepository(), location: '/ajustes', size: _phone, emailRepo: repo);
      await _reveal(tester, const Key('gmail-disconnect'));
      await tester.tap(find.byKey(const Key('gmail-disconnect')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('gmail-confirm-disconnect')));
      await tester.pumpAndSettle();
      expect(repo.disconnectCalls, 1);
      expect(find.byKey(const Key('gmail-connect')), findsOneWidget);
    });
  });
}
