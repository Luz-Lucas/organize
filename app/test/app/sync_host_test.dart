import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/app/sync_host.dart';
import 'package:organizacional/sync/fake_remote_source.dart';
import 'package:organizacional/sync/sync_session.dart';

void main() {
  late Directory dir;
  late FakeRemoteSource remote;
  late StreamController<String?> users;
  final opened = <String>[];
  final built = <String?>[];

  setUp(() {
    dir = Directory.systemTemp.createTempSync('sync-host');
    remote = FakeRemoteSource();
    users = StreamController<String?>.broadcast(sync: true);
    opened.clear();
    built.clear();
  });
  tearDown(() async {
    await users.close();
    await remote.close();
    dir.deleteSync(recursive: true);
  });

  Future<SyncSession> openSession(String id) async {
    opened.add(id);
    return SyncSession.open(
      userId: id,
      supportDir: dir,
      remote: remote,
      flushInterval: null,
      refreshInterval: null,
      externalCheckInterval: null,
      retryDelay: (_) => const Duration(milliseconds: 50),
    );
  }

  Widget host({String? initial, Future<SyncSession> Function(String)? open}) => Directionality(
        textDirection: TextDirection.ltr,
        child: SyncHost(
          userIds: users.stream,
          initialUserId: initial,
          openSession: open ?? openSession,
          loading: const Text('carregando'),
          builder: (context, session) {
            built.add(session?.userId);
            return Text('app:${session?.userId ?? 'sem sessão'}');
          },
        ),
      );

  // O SQLite e os arquivos são de verdade (assíncronos): fora do relógio falso do testWidgets.
  // Os callbacks dos futuros iniciados dentro do teste só rodam quando o relógio falso avança (pump).
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
      await tester.pump();
    }
  }

  testWidgets('deslogado: constrói sem sessão e não abre banco nenhum', (tester) async {
    await tester.pumpWidget(host());
    expect(find.text('app:sem sessão'), findsOneWidget);
    expect(opened, isEmpty);
    expect(Directory('${dir.path}/sync').existsSync(), isFalse);
  });

  testWidgets('já logado ao abrir: mostra "carregando" até o banco abrir e então constrói com a sessão',
      (tester) async {
    await tester.pumpWidget(host(initial: 'ana'));
    expect(find.text('carregando'), findsOneWidget);
    await settle(tester);
    expect(find.text('app:ana'), findsOneWidget);
    expect(opened, ['ana']);
    await tester.pumpWidget(const SizedBox()); // desmonta: fecha a sessão
    await settle(tester);
  });

  testWidgets('entrar depois: abre a sessão do usuário que entrou', (tester) async {
    await tester.pumpWidget(host());
    users.add('ana');
    await tester.pump();
    expect(find.text('carregando'), findsOneWidget);
    await settle(tester);
    expect(find.text('app:ana'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });

  testWidgets('sair da conta: volta ao estado sem sessão e apaga o banco local', (tester) async {
    await tester.pumpWidget(host(initial: 'ana'));
    await settle(tester);
    final session = built.last;
    expect(session, 'ana');
    expect(File('${dir.path}/sync/ana.db').existsSync(), isTrue);
    users.add(null);
    await tester.pump();
    expect(find.text('app:sem sessão'), findsOneWidget);
    await settle(tester);
    expect(File('${dir.path}/sync/ana.db').existsSync(), isFalse);
  });

  testWidgets('trocar de conta: fecha e apaga a anterior, abre a nova e reconstrói tudo', (tester) async {
    await tester.pumpWidget(host(initial: 'ana'));
    await settle(tester);
    users.add('beto');
    await tester.pump();
    await settle(tester);
    expect(find.text('app:beto'), findsOneWidget);
    expect(File('${dir.path}/sync/ana.db').existsSync(), isFalse);
    expect(File('${dir.path}/sync/beto.db').existsSync(), isTrue);
    expect(opened, ['ana', 'beto']);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });

  testWidgets('o mesmo usuário de novo (token renovado) não reabre nem reconstrói', (tester) async {
    await tester.pumpWidget(host(initial: 'ana'));
    await settle(tester);
    final before = built.length;
    users.add('ana');
    users.add('ana');
    await tester.pump();
    await settle(tester);
    expect(opened, ['ana']);
    expect(built.length, before);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });

  testWidgets('se o banco local não abrir, o app entra mesmo assim sem sessão (modo online)', (tester) async {
    await tester.pumpWidget(host(initial: 'ana', open: (_) async => throw const FileSystemException('sem espaço')));
    await settle(tester);
    expect(find.text('app:sem sessão'), findsOneWidget);
  });

  testWidgets('entrar e sair antes do banco abrir não deixa arquivo para trás', (tester) async {
    await tester.pumpWidget(host());
    users.add('ana');
    await tester.pump();
    users.add(null);
    await tester.pump();
    await settle(tester);
    await settle(tester);
    expect(find.text('app:sem sessão'), findsOneWidget);
    final left = Directory('${dir.path}/sync').existsSync()
        ? Directory('${dir.path}/sync').listSync().where((f) => f.path.contains('ana.db')).toList()
        : const <FileSystemEntity>[];
    expect(left, isEmpty);
  });

  testWidgets('voltar ao app (resumed) manda a sessão recarregar', (tester) async {
    await tester.pumpWidget(host(initial: 'ana'));
    await settle(tester);
    final before = remote.calls.where((c) => c.op == 'fetch').length;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
    expect(remote.calls.where((c) => c.op == 'fetch').length, greaterThan(before));
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });
}
