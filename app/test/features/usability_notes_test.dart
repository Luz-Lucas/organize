import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/note.dart';
import 'package:organizacional/domain/space.dart';

import '../helpers.dart';

const _phone = Size(360, 760);

Future<MemoryRepository> _seed() async {
  final repo = MemoryRepository();
  await repo.upsertSpace(const Space(id: 's1', name: 'Cálculo I', kind: SpaceKind.materia));
  await repo.upsertNote(const Note(id: 'n1', title: 'Resumo', body: 'Teorema do Valor Intermediário', spaceId: 's1'));
  await repo.upsertNote(const Note(id: 'n2', title: 'Valor presente', body: 'finanças'));
  await repo.upsertNote(const Note(id: 'n3', title: 'Ideias soltas'));
  await repo.upsertNote(const Note(id: 'n4', title: 'Anotações', body: 'o valor aparece só aqui'));
  return repo;
}

EditableText _editable(WidgetTester tester) => tester.widget<EditableText>(
    find.descendant(of: find.byKey(const Key('note-title')), matching: find.byType(EditableText)));

void main() {
  group('Espaços no celular', () {
    testWidgets('ação da barra abre /espacos', (tester) async {
      await pumpApp(tester, await _seed(), location: '/notas', size: _phone);
      await tester.tap(find.byTooltip('Espaços'));
      await tester.pumpAndSettle();
      expect(find.text('Cálculo I'), findsWidgets);
      expect(find.byKey(const Key('open-spaces')), findsNothing); // saiu de Notas
    });

    testWidgets('botão do espaço na árvore abre o espaço', (tester) async {
      await pumpApp(tester, await _seed(), location: '/notas', size: _phone);
      await tester.tap(find.byKey(const ValueKey('tree-space-open-s1')));
      await tester.pumpAndSettle();
      // Tela do espaço: mostra o nome na AppBar e a nota dele.
      expect(find.widgetWithText(AppBar, 'Cálculo I'), findsOneWidget);
    });
  });

  group('busca no corpo', () {
    testWidgets('acha pelo texto do corpo, sem acento nem caixa, com títulos primeiro', (tester) async {
      await pumpApp(tester, await _seed(), location: '/notas', size: _phone);
      await tester.enterText(find.byKey(const Key('notes-search')), 'VALOR');
      await tester.pumpAndSettle();
      // n2 casa pelo título; n4 (que viria antes por ordem alfabética) só pelo corpo.
      final n2 = tester.getTopLeft(find.byKey(const ValueKey('tree-note-n2'))).dy;
      final n4 = tester.getTopLeft(find.byKey(const ValueKey('tree-note-n4'))).dy;
      expect(find.byKey(const ValueKey('tree-note-n3')), findsNothing);
      expect(find.byKey(const ValueKey('tree-note-n1')), findsOneWidget); // corpo, dentro do espaço
      expect(n2, lessThan(n4));

      await tester.enterText(find.byKey(const Key('notes-search')), 'financas');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tree-note-n2')), findsOneWidget);
      expect(find.byKey(const ValueKey('tree-note-n1')), findsNothing);

      await tester.enterText(find.byKey(const Key('notes-search')), 'intermediario');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tree-note-n1')), findsOneWidget);
    });
  });

  group('alvos de toque', () {
    testWidgets('linhas, espaços e busca têm 48 dp no celular', (tester) async {
      await pumpApp(tester, await _seed(), location: '/notas', size: _phone);
      expect(tester.getSize(find.byKey(const ValueKey('tree-note-n3'))).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(find.byKey(const Key('notes-search'))).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(find.byKey(const ValueKey('tree-space-s1'))).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(find.byKey(const ValueKey('tree-space-open-s1'))).height, greaterThanOrEqualTo(48));
    });

    testWidgets('no computador a árvore continua densa', (tester) async {
      await pumpApp(tester, await _seed(), location: '/notas');
      expect(tester.getSize(find.byKey(const ValueKey('tree-note-n3'))).height, lessThan(40));
    });
  });

  group('notas: excluir e criar', () {
    testWidgets('excluir mantém a confirmação e Desfazer recria a nota', (tester) async {
      final repo = await _seed();
      await pumpApp(tester, repo, location: '/nota/n3', size: _phone);
      await tester.tap(find.byKey(const Key('delete-note')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Excluir'));
      await tester.pumpAndSettle();
      expect((await repo.watchNotes().first).where((n) => n.id == 'n3'), isEmpty);
      expect(find.text('Nota excluída'), findsOneWidget);

      await tester.tap(find.text('Desfazer'));
      await tester.pumpAndSettle();
      final back = (await repo.watchNotes().first).where((n) => n.id == 'n3');
      expect(back.single.title, 'Ideias soltas');
    });

    testWidgets('nota nova abre com o título focado e todo selecionado', (tester) async {
      final repo = MemoryRepository();
      await repo.upsertNote(const Note(id: 'n1', title: 'Sem título'));
      await pumpApp(tester, repo, location: '/nota/n1', size: _phone);
      final field = tester.widget<TextField>(find.byKey(const Key('note-title')));
      expect(_editable(tester).focusNode.hasFocus, isTrue);
      expect(field.controller!.selection, const TextSelection(baseOffset: 0, extentOffset: 'Sem título'.length));
      expect(field.textCapitalization, TextCapitalization.sentences);
    });

    testWidgets('nota existente não rouba o foco', (tester) async {
      await pumpApp(tester, await _seed(), location: '/nota/n3', size: _phone);
      expect(_editable(tester).focusNode.hasFocus, isFalse);
    });
  });
}
