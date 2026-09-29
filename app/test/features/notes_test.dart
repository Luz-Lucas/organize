import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/note.dart';

import '../helpers.dart';

void main() {
  testWidgets('edição é salva automaticamente', (tester) async {
    final repo = MemoryRepository();
    await repo.upsertNote(const Note(id: 'n1', title: 'Cálculo'));
    await pumpApp(tester, repo, location: '/nota/n1');
    await tester.enterText(find.byKey(const Key('note-body')), '# Limites');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect((await repo.watchNotes().first).single.body, '# Limites');
  });

  testWidgets('falha ao salvar mantém o texto e mostra aviso até salvar de novo', (tester) async {
    final repo = MemoryRepository();
    await repo.upsertNote(const Note(id: 'n1', title: 'Cálculo'));
    await pumpApp(tester, repo, location: '/nota/n1');
    repo.failWrites = true;
    await tester.enterText(find.byKey(const Key('note-body')), 'derivadas parciais');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.byKey(const Key('save-error')), findsOneWidget);
    expect(find.text('Não foi possível salvar. Suas alterações continuam aqui.'), findsOneWidget);
    expect(find.text('derivadas parciais'), findsOneWidget);

    repo.failWrites = false;
    await tester.enterText(find.byKey(const Key('note-body')), 'derivadas parciais!');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.byKey(const Key('save-error')), findsNothing);
    expect((await repo.watchNotes().first).single.body, 'derivadas parciais!');
  });

  testWidgets('título duplicado mostra aviso específico', (tester) async {
    final repo = MemoryRepository();
    await repo.upsertNote(const Note(id: 'n1', title: 'Cálculo'));
    await repo.upsertNote(const Note(id: 'n2', title: 'Física'));
    await pumpApp(tester, repo, location: '/nota/n2');
    await tester.enterText(find.byKey(const Key('note-title')), '  cálculo ');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('Já existe uma nota com esse título.'), findsOneWidget);
  });

  testWidgets('link [[...]] inexistente cria a nota, abre e mostra o backlink', (tester) async {
    final repo = MemoryRepository();
    await repo.upsertNote(const Note(id: 'n1', title: 'Cálculo', body: 'Ver [[Álgebra]]'));
    await pumpApp(tester, repo, location: '/nota/n1');
    await tester.tap(find.byKey(const Key('toggle-preview')));
    await tester.pumpAndSettle();
    await tester.tapOnText(find.textRange.ofSubstring('Álgebra'));
    await tester.pumpAndSettle();
    final notes = await repo.watchNotes().first;
    expect(notes.map((n) => n.title), containsAll(['Cálculo', 'Álgebra']));
    final title = tester.widget<TextField>(find.byKey(const Key('note-title')));
    expect(title.controller!.text, 'Álgebra');
    expect(find.text('Mencionada em'), findsOneWidget);
    expect(find.text('Cálculo'), findsOneWidget);
  });

  testWidgets('sair antes do debounce com falha ao salvar recupera o rascunho ao reabrir',
      (tester) async {
    final repo = MemoryRepository();
    await repo.upsertNote(const Note(id: 'n1', title: 'Cálculo'));
    await pumpApp(tester, repo, location: '/nota/n1');
    repo.failWrites = true;
    await tester.enterText(find.byKey(const Key('note-body')), 'texto perdido');
    // Navega para fora ANTES do debounce de 800 ms disparar: o dispose()
    // deve tentar salvar, falhar (failWrites) e guardar o rascunho.
    final awayContext = tester.element(find.byType(Scaffold).first);
    GoRouter.of(awayContext).go('/espacos');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('note-body')), findsNothing);

    repo.failWrites = false;
    final backContext = tester.element(find.byType(Scaffold).first);
    GoRouter.of(backContext).go('/nota/n1');
    await tester.pumpAndSettle();

    expect(find.text('texto perdido'), findsOneWidget);
    expect(find.byKey(const Key('save-error')), findsOneWidget);
    expect(
      find.text('Alterações não salvas foram recuperadas. Edite para tentar salvar de novo.'),
      findsOneWidget,
    );
  });

  testWidgets('rascunho recuperado e não editado continua recuperado ao sair e reabrir de novo',
      (tester) async {
    final repo = MemoryRepository();
    await repo.upsertNote(const Note(id: 'n1', title: 'Cálculo'));
    await pumpApp(tester, repo, location: '/nota/n1');
    repo.failWrites = true;
    await tester.enterText(find.byKey(const Key('note-body')), 'texto perdido');
    var context = tester.element(find.byType(Scaffold).first);
    GoRouter.of(context).go('/espacos');
    await tester.pumpAndSettle();

    // Reabre: o rascunho é recuperado, mas o usuário sai de novo sem editar.
    context = tester.element(find.byType(Scaffold).first);
    GoRouter.of(context).go('/nota/n1');
    await tester.pumpAndSettle();
    expect(find.text('texto perdido'), findsOneWidget);
    context = tester.element(find.byType(Scaffold).first);
    GoRouter.of(context).go('/espacos');
    await tester.pumpAndSettle();

    // Reabre de novo: ainda deve mostrar o rascunho recuperado.
    repo.failWrites = false;
    context = tester.element(find.byType(Scaffold).first);
    GoRouter.of(context).go('/nota/n1');
    await tester.pumpAndSettle();
    expect(find.text('texto perdido'), findsOneWidget);
    expect(
      find.text('Alterações não salvas foram recuperadas. Edite para tentar salvar de novo.'),
      findsOneWidget,
    );
  });

  testWidgets('título vazio ao sair mantém o corpo editado com o título anterior', (tester) async {
    final repo = MemoryRepository();
    await repo.upsertNote(const Note(id: 'n1', title: 'Cálculo'));
    await pumpApp(tester, repo, location: '/nota/n1');
    await tester.enterText(find.byKey(const Key('note-title')), '');
    await tester.enterText(find.byKey(const Key('note-body')), 'corpo sem título');
    final context = tester.element(find.byType(Scaffold).first);
    GoRouter.of(context).go('/espacos');
    await tester.pumpAndSettle();
    final saved = (await repo.watchNotes().first).single;
    expect(saved.title, 'Cálculo');
    expect(saved.body, 'corpo sem título');
  });

  testWidgets(
      'salvamentos concorrentes são serializados: o conteúdo final é sempre o mais recente',
      (tester) async {
    final repo = _GatedNoteRepository();
    await repo.upsertNote(const Note(id: 'n1', title: 'Cálculo'));
    await pumpApp(tester, repo, location: '/nota/n1');

    final gate1 = repo.addGate();
    final gate2 = repo.addGate();

    await tester.enterText(find.byKey(const Key('note-body')), 'v1');
    await tester.pump(const Duration(milliseconds: 800)); // dispara o 1º salvamento (preso)
    await tester.enterText(find.byKey(const Key('note-body')), 'v2 final');
    await tester.pump(const Duration(milliseconds: 800)); // dispara o 2º salvamento

    // Libera fora de ordem: o 2º portão termina antes do 1º.
    gate2.complete();
    await tester.pump();
    gate1.complete();
    await tester.pump();
    await tester.pumpAndSettle();

    final saved = (await repo.watchNotes().first).single;
    expect(saved.body, 'v2 final');
  });
}

/// Repositório de teste que atrasa upsertNote até que o portão correspondente
/// (na ordem de chamada) seja liberado, para simular respostas de rede que
/// terminam fora de ordem.
class _GatedNoteRepository extends MemoryRepository {
  final _gates = <Completer<void>>[];

  Completer<void> addGate() {
    final gate = Completer<void>();
    _gates.add(gate);
    return gate;
  }

  @override
  Future<void> upsertNote(Note note) async {
    if (_gates.isNotEmpty) {
      await _gates.removeAt(0).future;
    }
    return super.upsertNote(note);
  }
}
