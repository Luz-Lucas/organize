import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/task_item.dart';

import '../helpers.dart';

final _icon = find.byKey(const Key('sync-status-icon'));
final _cloudOff = find.descendant(of: _icon, matching: find.byIcon(Icons.cloud_off_outlined));

void main() {
  testWidgets(
      'queda do stream: o campo rápido não perde texto, prioridade nem aba, e só há UM ícone discreto (depois de 4 s)',
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
    expect(_icon, findsNothing, reason: 'quedas curtas não mostram nada');

    await tester.pump(const Duration(seconds: 5));
    expectDraftIntact();
    expect(_cloudOff, findsOneWidget, reason: 'um único ícone global');
    expect(find.textContaining('Sem conexão'), findsNothing, reason: 'nenhuma faixa nem texto na tela');

    // A conexão volta: o ícone some e o rascunho continua lá.
    repo.emitData();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expectDraftIntact();
    expect(_icon, findsNothing);
  });

  testWidgets('queda curta (menos de 4 s) não mostra ícone nenhum', (tester) async {
    final repo = MemoryRepository();
    await pumpApp(tester, repo, location: '/tarefas');

    repo.emitStreamError();
    await tester.pump(const Duration(seconds: 3));
    repo.emitData();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 3));

    expect(_icon, findsNothing);
  });

  testWidgets('o ícone aparece também em outras telas (ex.: Início) sem chip duplicado', (tester) async {
    final repo = MemoryRepository();
    await pumpApp(tester, repo);

    repo.emitStreamError();
    await tester.pump(const Duration(seconds: 5));

    expect(_cloudOff, findsOneWidget);
    expect(find.byKey(const Key('status-connection')), findsNothing);
  });

  testWidgets('o ícone não cobre o botão Casa do cabeçalho da Início nem muda o layout', (tester) async {
    final repo = MemoryRepository();
    await pumpApp(tester, repo);
    final home = tester.getRect(find.byKey(const Key('open-home')));
    repo.emitStreamError();
    await tester.pump(const Duration(seconds: 5));
    final icon = tester.getRect(_icon);
    expect(tester.getRect(find.byKey(const Key('open-home'))), home);
    expect(icon.size.longestSide, lessThanOrEqualTo(24));
    final overlap = icon.intersect(home);
    expect(overlap.width <= 0 || overlap.height <= 0 || overlap.width * overlap.height < 80, isTrue,
        reason: 'no máximo um cantinho de folga do botão Casa');
  });

  for (final size in const [Size(400, 800), Size(1000, 800)]) {
    testWidgets('o ícone não cobre botões nas telas principais (${size.width.toInt()} dp de largura)', (tester) async {
      for (final route in const ['/', '/agenda', '/tarefas', '/notas', '/espacos', '/academia', '/compras', '/noticias', '/casa', '/ajustes']) {
        final repo = MemoryRepository();
        await pumpApp(tester, repo, location: route, size: size);
        repo.emitStreamError();
        await tester.pump(const Duration(seconds: 5));
        final icon = tester.getRect(_icon);
        for (final type in [IconButton, FilledButton, TextButton, OutlinedButton, PopupMenuButton, FloatingActionButton]) {
          for (final e in find.byType(type).evaluate()) {
            final full = tester.getRect(find.byWidget(e.widget));
            // IconButton tem 48 dp de toque, mas o desenho é só o ícone de 24 dp no centro.
            final r = type == IconButton ? Rect.fromCenter(center: full.center, width: 24, height: 24) : full;
            final o = icon.intersect(r);
            final area = o.width <= 0 || o.height <= 0 ? 0.0 : o.width * o.height;
            expect(area, lessThanOrEqualTo(40), reason: '$route: $type em $r cobre o ícone em $icon');
          }
        }
        await tester.pumpWidget(const SizedBox());
      }
    });
  }
}
