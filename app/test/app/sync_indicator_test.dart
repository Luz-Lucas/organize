import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/app/sync_providers.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/sync/sync_engine.dart';

import '../helpers.dart';

SyncState _state(int pending, {bool online = true}) =>
    SyncState(pending: pending, online: online, lastError: online ? null : 'sem rede');

void main() {
  late StreamController<SyncState> states;
  late StreamController<SyncRejection> rejections;

  setUp(() {
    states = StreamController<SyncState>.broadcast();
    rejections = StreamController<SyncRejection>.broadcast();
  });
  tearDown(() async {
    await states.close();
    await rejections.close();
  });

  List<Override> overrides() => [
        syncStateProvider.overrideWith((ref) => states.stream),
        syncRejectionsProvider.overrideWithValue(rejections.stream),
      ];

  final icon = find.byKey(const Key('sync-status-icon'));
  Finder glyph(IconData d) => find.descendant(of: icon, matching: find.byIcon(d));

  testWidgets('sem nada pendente não há ícone nenhum', (tester) async {
    await pumpApp(tester, MemoryRepository(), overrides: overrides());
    states.add(_state(0));
    await tester.pump(const Duration(seconds: 10));
    expect(icon, findsNothing);
  });

  testWidgets('fila parada há mais de 4 s mostra o ícone de envio pendente, sem mexer no layout', (tester) async {
    await pumpApp(tester, MemoryRepository(), overrides: overrides());
    final before = tester.getTopLeft(find.text('Bom dia'));
    states.add(_state(3));
    await tester.pump(const Duration(seconds: 3));
    expect(icon, findsNothing, reason: 'abaixo de 4 s não mostra nada');

    await tester.pump(const Duration(seconds: 2));
    expect(glyph(Icons.cloud_upload_outlined), findsOneWidget);
    expect(tester.getTopLeft(find.text('Bom dia')), before, reason: 'o ícone não empurra o conteúdo');
    expect(find.byTooltip('3 alterações aguardando envio'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    states.add(_state(0));
    await tester.pumpAndSettle();
    expect(icon, findsNothing);
  });

  testWidgets('tocar no ícone abre o detalhe com a contagem', (tester) async {
    await pumpApp(tester, MemoryRepository(), overrides: overrides());
    states.add(_state(1));
    await tester.pump(const Duration(seconds: 5));
    await tester.tap(icon);
    await tester.pumpAndSettle();
    expect(find.text('1 alteração aguardando envio'), findsOneWidget);
  });

  testWidgets('envio que anda (fila diminui) reinicia a contagem dos 4 s', (tester) async {
    await pumpApp(tester, MemoryRepository(), overrides: overrides());
    states.add(_state(2));
    await tester.pump(const Duration(seconds: 3));
    states.add(_state(1)); // andou
    await tester.pump(const Duration(seconds: 3));
    expect(icon, findsNothing);
    await tester.pump(const Duration(seconds: 2));
    expect(glyph(Icons.cloud_upload_outlined), findsOneWidget);
  });

  testWidgets('fila que se esvazia antes dos 4 s nunca mostra o ícone', (tester) async {
    await pumpApp(tester, MemoryRepository(), overrides: overrides());
    states.add(_state(1));
    await tester.pump(const Duration(seconds: 2));
    states.add(_state(0));
    await tester.pump(const Duration(seconds: 6));
    expect(icon, findsNothing);
  });

  testWidgets('sem conexão há mais de 4 s mostra a nuvem riscada; voltar a conexão some', (tester) async {
    await pumpApp(tester, MemoryRepository(), overrides: overrides());
    states.add(_state(2, online: false));
    await tester.pump(const Duration(seconds: 2));
    expect(icon, findsNothing, reason: 'queda curta não mostra nada');
    await tester.pump(const Duration(seconds: 3));
    expect(glyph(Icons.cloud_off_outlined), findsOneWidget, reason: 'sem conexão vale mais que pendente');
    await tester.tap(icon);
    await tester.pumpAndSettle();
    expect(find.text('Sem conexão — as alterações ficam salvas no aparelho'), findsOneWidget);
    expect(find.text('2 alterações aguardando envio'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10)); // fecha o sheet
    await tester.pumpAndSettle();

    states.add(_state(0));
    await tester.pumpAndSettle();
    expect(icon, findsNothing);
  });

  testWidgets('queda curta (menos de 4 s) não mostra nada', (tester) async {
    await pumpApp(tester, MemoryRepository(), overrides: overrides());
    states.add(_state(0, online: false));
    await tester.pump(const Duration(seconds: 3));
    states.add(_state(0));
    await tester.pump(const Duration(seconds: 6));
    expect(icon, findsNothing);
  });

  testWidgets('recusa do servidor vira ícone de erro (sem SnackBar) até o usuário tocar; o detalhe lista o motivo',
      (tester) async {
    await pumpApp(tester, MemoryRepository(), overrides: overrides());
    rejections.add(const SyncRejection(tbl: 'tasks', id: 't1', message: 'new row violates row-level security policy'));
    rejections.add(const SyncRejection(tbl: 'events', id: 'e1', message: 'violates check constraint "x"'));
    await tester.pump(const Duration(seconds: 30));
    expect(glyph(Icons.sync_problem), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    final color = tester.widget<Icon>(glyph(Icons.sync_problem)).color;
    expect(color, Theme.of(tester.element(icon)).colorScheme.error);

    await tester.tap(icon);
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível salvar: sem permissão'), findsOneWidget);
    expect(find.text('Não foi possível salvar: um valor não é aceito'), findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(icon, findsNothing, reason: 'já foi visto');
  });
}
