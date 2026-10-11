import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/app/app.dart';
import 'package:organizacional/app/providers.dart';
import 'package:organizacional/app/router.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/note.dart';
import 'package:organizacional/domain/space.dart';
import 'package:organizacional/domain/task_item.dart';

import '../helpers.dart';

void main() {
  testWidgets('cria um espaço de hobby pelo diálogo', (tester) async {
    final repo = MemoryRepository();
    await pumpApp(tester, repo, location: '/espacos', size: const Size(600, 800));
    await tester.tap(find.byKey(const Key('new-space')));
    await tester.pumpAndSettle();
    final criar = find.widgetWithText(FilledButton, 'Criar');
    expect(tester.widget<FilledButton>(criar).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('space-name')), 'Violão');
    await tester.tap(find.text('Hobby'));
    await tester.pump();
    await tester.tap(criar);
    await tester.pumpAndSettle();
    expect(find.text('Hobbies'), findsOneWidget);
    expect(find.text('Violão'), findsOneWidget);
    expect((await repo.watchSpaces().first).single.kind, SpaceKind.hobby);
  });

  testWidgets('nova nota no espaço abre o editor com título único e permite voltar',
      (tester) async {
    final repo = MemoryRepository();
    await repo.upsertSpace(const Space(id: 's1', name: 'Cálculo I', kind: SpaceKind.materia));
    await repo.upsertNote(const Note(id: 'n0', title: 'Sem título'));
    await pumpApp(tester, repo, location: '/espacos/s1');
    await tester.tap(find.byKey(const Key('new-note')));
    await tester.pumpAndSettle();
    final title = tester.widget<TextField>(find.byKey(const Key('note-title')));
    expect(title.controller!.text, 'Sem título 2');
    final created = (await repo.watchNotes().first).firstWhere((n) => n.id != 'n0');
    expect(created.spaceId, 's1');

    // A nota foi empilhada (context.push), não substituiu a tela: dá para
    // voltar ao espaço em vez de sair do app.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Cálculo I'), findsOneWidget);
  });

  testWidgets('abrir nota na lista do espaço empilha a tela (dá para voltar)', (tester) async {
    final repo = MemoryRepository();
    await repo.upsertSpace(const Space(id: 's1', name: 'Cálculo I', kind: SpaceKind.materia));
    await repo.upsertNote(const Note(id: 'n1', title: 'Limites', spaceId: 's1'));
    await pumpApp(tester, repo, location: '/espacos/s1');
    await tester.tap(find.text('Limites'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('note-title')), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Cálculo I'), findsOneWidget);
    expect(find.byKey(const Key('note-title')), findsNothing);
  });

  testWidgets('botão Sair na AppBar de Espaços chama o callback de logout', (tester) async {
    var signedOut = false;
    final repo = MemoryRepository();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        clockProvider.overrideWithValue(() => defaultNow),
        signOutProvider.overrideWithValue(() async {
          signedOut = true;
        }),
      ],
      child: OrganizacionalApp(
        router: buildRouter(initialLocation: '/espacos', isSignedIn: () => true),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sign-out')));
    await tester.pumpAndSettle();
    expect(signedOut, isTrue);
  });

  testWidgets(
      'botão de excluir espaço fica desabilitado até notas e tarefas carregarem',
      (tester) async {
    final repo = _SlowContentRepository();
    await repo.upsertSpace(const Space(id: 's1', name: 'Cálculo I', kind: SpaceKind.materia));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        clockProvider.overrideWithValue(() => defaultNow),
      ],
      child: OrganizacionalApp(
        router: buildRouter(initialLocation: '/espacos/s1', isSignedIn: () => true),
      ),
    ));
    // O espaço carrega normalmente, mas notas/tarefas ficam presas no portão
    // (o spinner delas fica girando, então não dá para usar pumpAndSettle).
    await tester.pump();
    await tester.pump();
    final button = tester.widget<IconButton>(find.byKey(const Key('delete-space')));
    expect(button.onPressed, isNull);

    repo.release();
    await tester.pumpAndSettle();
    final loaded = tester.widget<IconButton>(find.byKey(const Key('delete-space')));
    expect(loaded.onPressed, isNotNull);
  });

  testWidgets('excluir espaço confirma com a contagem e apaga o conteúdo', (tester) async {
    final repo = MemoryRepository();
    await repo.upsertSpace(const Space(id: 's1', name: 'Cálculo I', kind: SpaceKind.materia));
    await repo.upsertNote(const Note(id: 'n1', title: 'Limites', spaceId: 's1'));
    await repo.upsertNote(const Note(id: 'n2', title: 'Derivadas', spaceId: 's1'));
    await repo.upsertTask(const TaskItem(id: 't1', title: 'Lista 1', spaceId: 's1'));
    await pumpApp(tester, repo, location: '/espacos/s1');
    expect(find.text('Limites'), findsOneWidget);
    await tester.tap(find.byKey(const Key('delete-space')));
    await tester.pumpAndSettle();
    expect(
      find.text('Isso apaga 2 notas e 1 tarefa. Os eventos da agenda são mantidos.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Excluir'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Espaços'), findsOneWidget);
    expect(await repo.watchSpaces().first, isEmpty);
    expect(await repo.watchNotes().first, isEmpty);
  });
}

/// Repositório de teste cujas notas/tarefas só passam a emitir depois que
/// [release] é chamado, para simular a janela antes dos dados chegarem.
class _SlowContentRepository extends MemoryRepository {
  final _gate = Completer<void>();

  void release() {
    if (!_gate.isCompleted) _gate.complete();
  }

  Stream<List<T>> _delayed<T>(Stream<List<T>> source) async* {
    await _gate.future;
    yield* source;
  }

  @override
  Stream<List<Note>> watchNotes() => _delayed(super.watchNotes());

  @override
  Stream<List<TaskItem>> watchTasks() => _delayed(super.watchTasks());
}
