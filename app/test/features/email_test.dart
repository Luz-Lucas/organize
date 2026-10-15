import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/email_repository.dart';
import 'package:organizacional/data/memory_email_repository.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/data/repository.dart';
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

    test('EmailState.canModify vem de can_modify e, sem a coluna, é falso', () {
      expect(EmailState.fromMap({'status': 'ok', 'can_modify': true}).canModify, isTrue);
      expect(EmailState.fromMap({'status': 'ok', 'can_modify': false}).canModify, isFalse);
      expect(EmailState.fromMap({'status': 'ok'}).canModify, isFalse);
      expect(const EmailState().canModify, isFalse);
    });

    test('EmailItem.copyWith(unread:) muda só o não lido', () {
      const m = EmailItem(id: '1', fromName: 'A', subject: 'S', unread: true);
      final r = m.copyWith(unread: false);
      expect(r.unread, isFalse);
      expect(r.id, '1');
      expect(r.fromName, 'A');
      expect(r.subject, 'S');
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

  group('repositório em memória', () {
    test('markRead tira os ids da lista de não lidos e baixa a contagem', () async {
      final repo = MemoryEmailRepository(
        state: const EmailState(status: EmailStatus.ok, unreadCount: 3),
        items: [_mail('1', 'A', 'a', defaultNow), _mail('2', 'B', 'b', defaultNow), _mail('3', 'C', 'c', defaultNow, unread: false)],
      );
      await repo.markRead(['1', '3']);
      final items = await repo.watchItems().first;
      expect(items.map((m) => m.unread), [false, true, false]);
      expect((await repo.watchState().first)!.unreadCount, 2); // '3' já estava lido
      expect(repo.markReadCalls, [
        ['1', '3'],
      ]);
    });

    test('markAllRead zera os não lidos das mensagens e conta a chamada', () async {
      final repo = MemoryEmailRepository(
        state: const EmailState(status: EmailStatus.ok, unreadCount: 2),
        items: [_mail('1', 'A', 'a', defaultNow), _mail('2', 'B', 'b', defaultNow)],
      );
      await repo.markAllRead();
      expect((await repo.watchItems().first).any((m) => m.unread), isFalse);
      expect((await repo.watchState().first)!.unreadCount, 0);
      expect(repo.markAllReadCalls, 1);
    });

    test('needsReconnect lança EmailNeedsReconnect (uma RepositoryException) e não altera nada', () async {
      final repo = MemoryEmailRepository(
        state: const EmailState(status: EmailStatus.ok, unreadCount: 1),
        items: [_mail('1', 'A', 'a', defaultNow)],
      )..needsReconnect = true;
      await expectLater(repo.markRead(['1']), throwsA(isA<EmailNeedsReconnect>()));
      await expectLater(repo.markAllRead(), throwsA(isA<RepositoryException>()));
      expect((await repo.watchItems().first).single.unread, isTrue);
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

    group('marcar como lida', () {
      MemoryEmailRepository repoWith({int unread = 2, bool canModify = true}) => MemoryEmailRepository(
            state: EmailState(status: EmailStatus.ok, unreadCount: unread, accountEmail: 'c@g.com', canModify: canModify),
            items: [
              _mail('1', 'Banco', 'Fatura disponível', defaultNow.subtract(const Duration(minutes: 5))),
              _mail('2', 'Professor', 'Aviso da prova', defaultNow.subtract(const Duration(hours: 2))),
              _mail('3', 'Loja', 'Promoção', defaultNow.subtract(const Duration(hours: 3)), unread: false),
            ],
          );

      FontWeight? senderWeight(WidgetTester tester, String text) =>
          tester.widget<Text>(find.text(text)).style?.fontWeight;

      testWidgets('só mensagens não lidas ganham o botão de 48 dp com dica', (tester) async {
        await pumpApp(tester, MemoryRepository(), size: _phone, emailRepo: repoWith());
        await _reveal(tester, const Key('email-read-1'));
        expect(find.byKey(const Key('email-read-1')), findsOneWidget);
        expect(find.byKey(const Key('email-read-2')), findsOneWidget);
        expect(find.byKey(const Key('email-read-3')), findsNothing);
        final size = tester.getSize(find.byKey(const Key('email-read-1')));
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
        expect(find.descendant(of: find.byKey(const Key('email-read-1')), matching: find.byIcon(Icons.mark_email_read_outlined)),
            findsOneWidget);
        expect(tester.widget<IconButton>(find.byKey(const Key('email-read-1'))).tooltip, 'Marcar como lida');
      });

      testWidgets('tocar no botão marca como lida: some o negrito, a contagem cai e o servidor é chamado', (tester) async {
        final repo = repoWith();
        await pumpApp(tester, MemoryRepository(), size: _phone, emailRepo: repo);
        await _reveal(tester, const Key('email-read-1'));
        expect(find.text('2 não lidos'), findsOneWidget);
        expect(senderWeight(tester, 'Banco'), FontWeight.w700);

        await tester.tap(find.byKey(const Key('email-read-1')));
        await tester.pumpAndSettle();

        expect(repo.markReadCalls, [
          ['1'],
        ]);
        expect(find.text('1 não lido'), findsOneWidget);
        expect(senderWeight(tester, 'Banco'), FontWeight.w400);
        expect(senderWeight(tester, 'Professor'), FontWeight.w700);
        expect(find.byKey(const Key('email-read-1')), findsNothing);
      });

      testWidgets('é otimista: a mudança aparece antes de o servidor responder', (tester) async {
        final repo = repoWith()..markGate = Completer<void>();
        await pumpApp(tester, MemoryRepository(), size: _phone, emailRepo: repo);
        await _reveal(tester, const Key('email-read-1'));

        await tester.tap(find.byKey(const Key('email-read-1')));
        await tester.pump();

        expect(find.text('1 não lido'), findsOneWidget); // servidor ainda não respondeu
        expect(senderWeight(tester, 'Banco'), FontWeight.w400);

        repo.markGate!.complete();
        await tester.pumpAndSettle();
        expect(find.text('1 não lido'), findsOneWidget);
      });

      testWidgets('deslizar a linha para a direita marca como lida sem remover a linha', (tester) async {
        final repo = repoWith();
        await pumpApp(tester, MemoryRepository(), size: _phone, emailRepo: repo);
        await _reveal(tester, const Key('email-swipe-1'));

        await tester.drag(find.byKey(const Key('email-swipe-1')), const Offset(300, 0));
        await tester.pumpAndSettle();

        expect(repo.markReadCalls, [
          ['1'],
        ]);
        expect(find.text('Banco'), findsOneWidget); // a linha continua lá
        expect(find.text('Fatura disponível'), findsOneWidget);
        expect(senderWeight(tester, 'Banco'), FontWeight.w400);
        expect(find.text('1 não lido'), findsOneWidget);
      });

      testWidgets('deslizar para a esquerda não faz nada', (tester) async {
        final repo = repoWith();
        await pumpApp(tester, MemoryRepository(), size: _phone, emailRepo: repo);
        await _reveal(tester, const Key('email-swipe-1'));
        await tester.drag(find.byKey(const Key('email-swipe-1')), const Offset(-300, 0));
        await tester.pumpAndSettle();
        expect(repo.markReadCalls, isEmpty);
        expect(find.text('2 não lidos'), findsOneWidget);
      });

      testWidgets('menu do cabeçalho: "Marcar todas como lidas" zera tudo', (tester) async {
        final repo = repoWith();
        await pumpApp(tester, MemoryRepository(), size: _phone, emailRepo: repo);
        await _reveal(tester, const Key('email-menu'));
        await tester.tap(find.byKey(const Key('email-menu')));
        await tester.pumpAndSettle();
        expect(find.text('Marcar todas como lidas'), findsOneWidget);
        await tester.tap(find.byKey(const Key('email-read-all')));
        await tester.pumpAndSettle();

        expect(repo.markAllReadCalls, 1);
        expect(find.byKey(const Key('email-unread')), findsNothing);
        expect(senderWeight(tester, 'Banco'), FontWeight.w400);
        expect(senderWeight(tester, 'Professor'), FontWeight.w400);
        expect(find.byKey(const Key('email-read-2')), findsNothing);
      });

      testWidgets('sem não lidos não há menu de "marcar todas"', (tester) async {
        final repo = MemoryEmailRepository(
          state: const EmailState(status: EmailStatus.ok, unreadCount: 0),
          items: [_mail('3', 'Loja', 'Promoção', defaultNow, unread: false)],
        );
        await pumpApp(tester, MemoryRepository(), size: _phone, emailRepo: repo);
        await tester.ensureVisible(find.byKey(const Key('email-card')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('email-menu')), findsNothing);
        expect(find.byKey(const Key('email-read-all')), findsNothing);
      });

      testWidgets('falha do servidor desfaz a mudança e mostra snackbar', (tester) async {
        final repo = repoWith()..failActions = true;
        await pumpApp(tester, MemoryRepository(), size: _phone, emailRepo: repo);
        await _reveal(tester, const Key('email-read-1'));
        await tester.tap(find.byKey(const Key('email-read-1')));
        await tester.pumpAndSettle();

        expect(find.text('Não foi possível marcar como lida.'), findsOneWidget);
        expect(find.text('2 não lidos'), findsOneWidget);
        expect(senderWeight(tester, 'Banco'), FontWeight.w700);
        expect(find.byKey(const Key('email-read-1')), findsOneWidget);
      });

      testWidgets('falha em "marcar todas" também desfaz', (tester) async {
        final repo = repoWith()..failActions = true;
        await pumpApp(tester, MemoryRepository(), size: _phone, emailRepo: repo);
        await _reveal(tester, const Key('email-menu'));
        await tester.tap(find.byKey(const Key('email-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('email-read-all')));
        await tester.pumpAndSettle();
        expect(find.text('Não foi possível marcar como lida.'), findsOneWidget);
        expect(find.text('2 não lidos'), findsOneWidget);
        expect(senderWeight(tester, 'Professor'), FontWeight.w700);
      });

      testWidgets('EmailNeedsReconnect: snackbar pede reconexão, ação "Ajustes" abre Ajustes, e desfaz', (tester) async {
        final repo = repoWith(canModify: false)..needsReconnect = true;
        await pumpApp(tester, MemoryRepository(), size: _phone, emailRepo: repo);
        await _reveal(tester, const Key('email-read-1'));
        await tester.tap(find.byKey(const Key('email-read-1')));
        await tester.pumpAndSettle();

        expect(find.text('Reconecte o Gmail em Ajustes para marcar como lida'), findsOneWidget);
        expect(find.text('2 não lidos'), findsOneWidget);
        expect(senderWeight(tester, 'Banco'), FontWeight.w700);

        await tester.tap(find.text('Ajustes'));
        await tester.pumpAndSettle();
        await _reveal(tester, const Key('gmail-card'));
        expect(find.byKey(const Key('gmail-card')), findsOneWidget);
      });
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
      expect(repo.lastConnectEmail, defaultGmailAccount.isEmpty ? null : defaultGmailAccount);
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
      await tester.scrollUntilVisible(find.byKey(const Key('gmail-connect')), -300,
          scrollable: find.byType(Scrollable).first);
      expect(find.byKey(const Key('gmail-connect')), findsOneWidget);
    });

    testWidgets('texto novo explica que dá para marcar como lida e que o corpo nunca é guardado', (tester) async {
      final repo = MemoryEmailRepository(state: const EmailState(status: EmailStatus.ok, canModify: true));
      await pumpApp(tester, MemoryRepository(), location: '/ajustes', size: _phone, emailRepo: repo);
      await _reveal(tester, const Key('gmail-card'));
      expect(
        find.text('Mostra não lidos e remetente/assunto na Início e permite marcar como lida. '
            'O app guarda só remetente, assunto e data; nunca o corpo nem os anexos.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('gmail-upgrade-scope')), findsNothing);
    });

    testWidgets('conta com o escopo antigo mostra "Reconectar para permitir marcar como lida"', (tester) async {
      final opened = <Uri>[];
      final repo = MemoryEmailRepository(state: const EmailState(status: EmailStatus.ok, canModify: false));
      await pumpApp(tester, MemoryRepository(),
          location: '/ajustes', size: _phone, emailRepo: repo, openLink: (u) async {
        opened.add(u);
        return true;
      });
      await _reveal(tester, const Key('gmail-upgrade-scope'));
      expect(find.text('Reconectar para permitir marcar como lida'), findsOneWidget);
      await tester.tap(find.byKey(const Key('gmail-upgrade-scope')));
      await tester.pumpAndSettle();
      expect(opened, [repo.connectUri]);
    });

    testWidgets('sem conexão ou com acesso expirado não mostra o aviso de escopo', (tester) async {
      final repo = MemoryEmailRepository(state: const EmailState(status: EmailStatus.authRequired));
      await pumpApp(tester, MemoryRepository(), location: '/ajustes', size: _phone, emailRepo: repo);
      await _reveal(tester, const Key('gmail-card'));
      expect(find.byKey(const Key('gmail-upgrade-scope')), findsNothing);
    });
  });
}
