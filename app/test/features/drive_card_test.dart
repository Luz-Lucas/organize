import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_drive_repository.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/drive.dart';

import '../helpers.dart';

const _phone = Size(400, 900);

Future<void> _reveal(WidgetTester tester, Key key) async {
  await tester.scrollUntilVisible(find.byKey(key), 300, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('não conectado: mostra o status, a ajuda do Samsung Notes e conecta com a conta sugerida', (tester) async {
    final opened = <Uri>[];
    final repo = MemoryDriveRepository(state: const DriveState());
    await pumpApp(tester, MemoryRepository(), location: '/ajustes', size: _phone, driveRepo: repo, openLink: (u) async {
      opened.add(u);
      return true;
    });
    await _reveal(tester, const Key('drive-connect'));
    expect(find.byKey(const Key('drive-card')), findsOneWidget);
    expect(find.text('Não conectado'), findsWidgets);
    expect(find.byKey(const Key('drive-samsung-help')), findsOneWidget);
    expect(find.textContaining('Samsung Notes'), findsOneWidget);
    await tester.tap(find.byKey(const Key('drive-connect')));
    await tester.pumpAndSettle();
    expect(opened, [repo.connectUri]);
    expect(repo.lastConnectEmail, 'sua-conta@exemplo.com');
    expect(find.byKey(const Key('drive-info')), findsOneWidget);
  });

  testWidgets('falha ao conectar mostra erro', (tester) async {
    final repo = MemoryDriveRepository(state: const DriveState())..failActions = true;
    await pumpApp(tester, MemoryRepository(), location: '/ajustes', size: _phone, driveRepo: repo);
    await _reveal(tester, const Key('drive-connect'));
    await tester.tap(find.byKey(const Key('drive-connect')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('drive-error')), findsOneWidget);
  });

  testWidgets('conectado: mostra a conta e desconectar pede confirmação', (tester) async {
    final repo = MemoryDriveRepository(
      state: const DriveState(status: DriveStatus.ok, accountEmail: 'c@g.com', rootFolderId: 'org-root'),
    );
    await pumpApp(tester, MemoryRepository(), location: '/ajustes', size: _phone, driveRepo: repo);
    await _reveal(tester, const Key('drive-disconnect'));
    expect(find.text('Conectado'), findsWidgets);
    expect(find.text('c@g.com'), findsOneWidget);
    expect(find.byKey(const Key('drive-open-docs')), findsOneWidget);
    await tester.tap(find.byKey(const Key('drive-disconnect')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('drive-confirm-disconnect')));
    await tester.pumpAndSettle();
    expect(repo.disconnectCalls, 1);
    expect(find.byKey(const Key('drive-connect')), findsOneWidget);
  });

  testWidgets('acesso expirado oferece Reconectar', (tester) async {
    final repo = MemoryDriveRepository(
      state: const DriveState(status: DriveStatus.authRequired, accountEmail: 'c@g.com', rootFolderId: 'org-root'),
    );
    await pumpApp(tester, MemoryRepository(), location: '/ajustes', size: _phone, driveRepo: repo);
    await _reveal(tester, const Key('drive-connect'));
    expect(find.text('Reconectar'), findsOneWidget);
    expect(find.textContaining('expirado'), findsOneWidget);
  });
}
