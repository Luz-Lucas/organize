import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/ui/common.dart';

void main() {
  Future<StreamController<int>> pump(WidgetTester tester) async {
    final controller = StreamController<int>();
    final provider = StreamProvider<int>((ref) => controller.stream);
    await tester.pumpWidget(ProviderScope(
      child: Consumer(
        builder: (context, ref, _) {
          final value = ref.watch(provider);
          return MaterialApp(
            home: Scaffold(body: asyncView(value, (n) => Text('valor: $n'))),
          );
        },
      ),
    ));
    return controller;
  }

  testWidgets('erro depois de dados mantém os dados na tela (sem tela de erro)',
      (tester) async {
    final controller = await pump(tester);
    controller.add(1);
    await tester.pump();
    expect(find.text('valor: 1'), findsOneWidget);

    controller.addError(Exception('network blip'));
    await tester.pump();

    expect(find.text('valor: 1'), findsOneWidget, reason: 'os dados continuam na tela');
    expect(find.text('Não foi possível carregar. Tentando de novo…'), findsNothing);
    await controller.close();
  });

  testWidgets('erro sem dados mostra a tela de erro cheia em pt-BR', (tester) async {
    final controller = await pump(tester);
    // Um Error (em vez de Exception) não é retentado automaticamente pelo
    // Riverpod, então o estado de erro final é observável de imediato.
    controller.addError(StateError('network blip'));
    await tester.pump();

    expect(find.textContaining('valor:'), findsNothing);
    expect(find.text('Não foi possível carregar. Tentando de novo…'), findsOneWidget);
    await controller.close();
  });

  testWidgets('o que o usuário digitou no builder sobrevive à ida e volta dados -> erro -> dados',
      (tester) async {
    final controller = StreamController<int>();
    final provider = StreamProvider<int>((ref) => controller.stream);
    await tester.pumpWidget(ProviderScope(
      child: Consumer(
        builder: (context, ref, _) {
          final value = ref.watch(provider);
          return MaterialApp(
            home: Scaffold(
              body: asyncView(value, (n) => Column(children: [Text('valor: $n'), const TextField()])),
            ),
          );
        },
      ),
    ));
    controller.add(1);
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'rascunho');

    // StateError não é retentado pelo Riverpod: o erro fica observável.
    controller.addError(StateError('queda do websocket'));
    await tester.pump();
    expect(find.text('valor: 1'), findsOneWidget);
    expect(find.text('rascunho'), findsOneWidget, reason: 'o texto não some quando cai a conexão');

    controller.add(2);
    await tester.pump();
    expect(find.text('valor: 2'), findsOneWidget);
    expect(find.text('rascunho'), findsOneWidget, reason: 'nem quando a conexão volta');
    await controller.close();
  });

  testWidgets('asyncView não desenha aviso: o aviso é único e global na casca', (tester) async {
    final controller = await pump(tester);
    controller.add(1);
    await tester.pump();
    controller.addError(StateError('queda'));
    await tester.pump();
    expect(find.text('Sem conexão com o servidor. Tentando de novo…'), findsNothing);
    await controller.close();
  });
}
