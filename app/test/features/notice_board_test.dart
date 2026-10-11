import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/notice.dart';
import 'package:organizacional/domain/task_item.dart';
import 'package:organizacional/ui/org_widgets.dart';

import '../helpers.dart';

void main() {
  testWidgets('mostra fixado e esconde expirado e arquivado', (tester) async {
    final repo = MemoryRepository();
    await repo.upsertNotice(const Notice(id: 'a', title: 'Prova de Cálculo', pinned: true));
    await repo.upsertNotice(Notice(id: 'b', title: 'Velho', expiresAt: DateTime(2026, 9, 27)));
    await repo.upsertNotice(Notice(id: 'c', title: 'Guardado', archivedAt: DateTime(2026, 9, 1)));
    await pumpApp(tester, repo);
    expect(find.text('Prova de Cálculo'), findsOneWidget);
    expect(find.text('Velho'), findsNothing);
    expect(find.text('Guardado'), findsNothing);
  });

  testWidgets('aviso do sistema de tarefas atrasadas leva a /tarefas', (tester) async {
    final repo = MemoryRepository();
    await repo.upsertTask(TaskItem(id: 't', title: 'Atrasada', dueAt: DateTime(2026, 9, 20)));
    await pumpApp(tester, repo);
    expect(find.text('1 tarefa atrasada'), findsOneWidget);
    expect(find.widgetWithText(OrgBadge, 'sistema'), findsOneWidget);
    await tester.tap(find.text('1 tarefa atrasada'));
    await tester.pumpAndSettle();
    final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
    expect(router.routeInformationProvider.value.uri.path, '/tarefas');
  });

  testWidgets('cria um aviso pelo diálogo', (tester) async {
    final repo = MemoryRepository();
    await pumpApp(tester, repo);
    await tester.tap(find.byKey(const Key('new-notice')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('notice-title')), 'Entregar trabalho');
    await tester.enterText(find.byKey(const Key('notice-body')), 'Até sexta');
    await tester.tap(find.byKey(const Key('notice-pinned')));
    await tester.tap(find.byKey(const Key('notice-priority-alta')));
    await tester.tap(find.byKey(const Key('notice-save')));
    await tester.pumpAndSettle();
    final saved = (await repo.watchNotices().first).single;
    expect(saved.title, 'Entregar trabalho');
    expect(saved.body, 'Até sexta');
    expect(saved.pinned, isTrue);
    expect(saved.priority, NoticePriority.alta);
    expect(find.text('Entregar trabalho'), findsOneWidget);
    expect(find.text('alta'), findsOneWidget);
  });

  testWidgets('arquiva e edita pelo menu', (tester) async {
    final repo = MemoryRepository();
    await repo.upsertNotice(const Notice(id: 'a', title: 'Aviso A'));
    await repo.upsertNotice(const Notice(id: 'b', title: 'Aviso B', pinned: true));
    await pumpApp(tester, repo);

    await tester.tap(find.byKey(const ValueKey('notice-menu-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editar'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Aviso A'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('notice-title')), 'Aviso A2');
    await tester.tap(find.byKey(const Key('notice-save')));
    await tester.pumpAndSettle();
    expect(find.text('Aviso A2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('notice-menu-b')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('archive-notice-b')));
    await tester.pumpAndSettle();
    expect(find.text('Aviso B'), findsNothing);
    final b = (await repo.watchNotices().first).firstWhere((n) => n.id == 'b');
    expect(b.archivedAt, isNotNull);
  });

  testWidgets('falha ao salvar mantém o diálogo aberto com o texto', (tester) async {
    final repo = MemoryRepository();
    await pumpApp(tester, repo);
    await tester.tap(find.byKey(const Key('new-notice')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('notice-title')), 'Importante');
    repo.failWrites = true;
    await tester.tap(find.byKey(const Key('notice-save')));
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível salvar o aviso.'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Importante'), findsOneWidget);
  });
}
