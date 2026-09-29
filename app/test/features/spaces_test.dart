import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/note.dart';
import 'package:organizacional/domain/space.dart';
import 'package:organizacional/domain/task_item.dart';

import '../helpers.dart';

void main() {
  testWidgets('cria um espaço de hobby pelo diálogo', (tester) async {
    final repo = MemoryRepository();
    await pumpApp(tester, repo, location: '/espacos');
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

  testWidgets('nova nota no espaço abre o editor com título único', (tester) async {
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
