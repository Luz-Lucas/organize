import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/files/drive_cache.dart';
import 'package:organizacional/files/drive_file_opener.dart';
import 'package:organizacional/files/files_platform.dart';

import '../files/fakes.dart';
import '../helpers.dart';

const _phone = Size(400, 900);

Future<void> _pump(WidgetTester tester, {required DriveCache cache, bool supported = true}) => pumpApp(
      tester,
      MemoryRepository(),
      location: '/ajustes',
      size: _phone,
      overrides: [
        driveCacheProvider.overrideWithValue(cache),
        filesPlatformProvider.overrideWithValue(FakeFilesPlatform(supported: supported)),
      ],
    );

Future<void> _reveal(WidgetTester tester) async {
  await tester.scrollUntilVisible(find.byKey(const Key('downloads-card')), 300, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('mostra o tamanho total e o limite de 1 GB', (tester) async {
    await _pump(tester, cache: FakeDriveCache(5 * 1024 * 1024));
    await _reveal(tester);
    expect(find.text('Arquivos baixados'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('downloads-size'))).data, '5,0 MB no aparelho');
    expect(find.textContaining('1 GB'), findsOneWidget);
  });

  testWidgets('Limpar pede confirmação; cancelar mantém; confirmar apaga e zera o tamanho', (tester) async {
    final cache = FakeDriveCache(2048);
    await _pump(tester, cache: cache);
    await _reveal(tester);

    await tester.tap(find.byKey(const Key('downloads-clear')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('downloads-confirm-clear')), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(cache.clears, 0);
    expect(cache.bytes, 2048);

    await tester.tap(find.byKey(const Key('downloads-clear')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('downloads-confirm-clear')));
    await tester.pumpAndSettle();
    expect(cache.clears, 1);
    expect(tester.widget<Text>(find.byKey(const Key('downloads-size'))).data, 'Nenhum arquivo baixado');
    expect(tester.widget<OutlinedButton>(find.byKey(const Key('downloads-clear'))).onPressed, isNull);
  });

  testWidgets('sem nada baixado, Limpar fica desabilitado', (tester) async {
    await _pump(tester, cache: FakeDriveCache(0));
    await _reveal(tester);
    expect(tester.widget<Text>(find.byKey(const Key('downloads-size'))).data, 'Nenhum arquivo baixado');
    expect(tester.widget<OutlinedButton>(find.byKey(const Key('downloads-clear'))).onPressed, isNull);
  });

  testWidgets('em aparelho sem suporte a arquivos locais o cartão não aparece', (tester) async {
    await _pump(tester, cache: FakeDriveCache(10), supported: false);
    await tester.scrollUntilVisible(find.byKey(const Key('drive-card')), 300, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('downloads-card')), findsNothing);
  });
}
