import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/task_item.dart';

import '../helpers.dart';

const _notice = 'Sem conexão com o servidor. Tentando de novo…';

void main() {
  testWidgets(
      'queda do stream: o campo rápido não perde texto, prioridade nem aba, e só há UMA faixa (depois de 4 s)',
      (tester) async {
    final repo = MemoryRepository();
    await repo.upsertTask(const TaskItem(id: 'a', title: 'Relatório'));
    await pumpApp(tester, repo, location: '/tarefas', size: const Size(400, 800));

    // Celular: vai para a aba "Fazendo", digita e escolhe prioridade Alta.
    await tester.tap(find.text('Fazendo 0'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('quick-add-doing')), 'Estudar para a prova');
    await tester.tap(find.byKey(const Key('quick-priority-doing')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('quick-priority-doing-alta')));
    await tester.pumpAndSettle();

    void expectDraftIntact() {
      expect(find.text('Estudar para a prova'), findsOneWidget, reason: 'texto digitado');
      expect(
        find.descendant(of: find.byKey(const Key('quick-priority-doing')), matching: find.text('Alta')),
        findsOneWidget,
        reason: 'prioridade escolhida',
      );
      expect(find.byKey(const Key('quick-add-doing')), findsOneWidget, reason: 'aba Fazendo ativa');
    }

    expectDraftIntact();

    // Queda do websocket: o servidor fica fora do ar por mais de 4 s.
    repo.emitStreamError();
    await tester.pump(const Duration(seconds: 1));
    expectDraftIntact();
    expect(find.text(_notice), findsNothing, reason: 'quedas curtas não mostram nada');

    await tester.pump(const Duration(seconds: 5));
    expectDraftIntact();
    expect(find.text(_notice), findsOneWidget, reason: 'uma única faixa global');

    // A conexão volta: a faixa some e o rascunho continua lá.
    repo.emitData();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expectDraftIntact();
    expect(find.text(_notice), findsNothing);
  });

  testWidgets('queda curta (menos de 4 s) não mostra faixa nenhuma', (tester) async {
    final repo = MemoryRepository();
    await pumpApp(tester, repo, location: '/tarefas');

    repo.emitStreamError();
    await tester.pump(const Duration(seconds: 3));
    repo.emitData();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 3));

    expect(find.text(_notice), findsNothing);
  });

  testWidgets('a faixa global aparece também em outras telas (ex.: Início) sem chip duplicado',
      (tester) async {
    final repo = MemoryRepository();
    await pumpApp(tester, repo);

    repo.emitStreamError();
    await tester.pump(const Duration(seconds: 5));

    expect(find.text(_notice), findsOneWidget);
    expect(find.byKey(const Key('status-connection')), findsNothing);
  });
}
