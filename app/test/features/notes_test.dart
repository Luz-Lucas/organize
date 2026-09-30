import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/note.dart';
import 'package:organizacional/domain/space.dart';

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

  testWidgets(
      'link [[...]] inexistente cria a nota, abre empilhada (dá para voltar) e mostra o backlink',
      (tester) async {
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

    // context.push: a nota "Cálculo" continua na pilha, dá para voltar.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    final backTitle = tester.widget<TextField>(find.byKey(const Key('note-title')));
    expect(backTitle.controller!.text, 'Cálculo');
  });

  testWidgets('link [[...]] para nota existente abre empilhada e o backlink também',
      (tester) async {
    final repo = MemoryRepository();
    await repo.upsertNote(const Note(id: 'n1', title: 'Cálculo', body: 'Ver [[Álgebra]]'));
    await repo.upsertNote(const Note(id: 'n2', title: 'Álgebra'));
    await pumpApp(tester, repo, location: '/nota/n1');
    await tester.tap(find.byKey(const Key('toggle-preview')));
    await tester.pumpAndSettle();
    await tester.tapOnText(find.textRange.ofSubstring('Álgebra'));
    await tester.pumpAndSettle();
    var title = tester.widget<TextField>(find.byKey(const Key('note-title')));
    expect(title.controller!.text, 'Álgebra');

    // Abre o backlink "Cálculo" listado em "Mencionada em".
    await tester.tap(find.text('Cálculo'));
    await tester.pumpAndSettle();
    title = tester.widget<TextField>(find.byKey(const Key('note-title')));
    expect(title.controller!.text, 'Cálculo');

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    title = tester.widget<TextField>(find.byKey(const Key('note-title')));
    expect(title.controller!.text, 'Álgebra');
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

  testWidgets('atualização remota sem edição local atualiza os campos', (tester) async {
    final repo = MemoryRepository();
    await repo.upsertNote(const Note(id: 'n1', title: 'Cálculo', body: 'v1'));
    await pumpApp(tester, repo, location: '/nota/n1');
    expect(find.text('v1'), findsOneWidget);

    await repo.upsertNote(const Note(id: 'n1', title: 'Cálculo', body: 'v2 (remoto)'));
    await tester.pump();

    expect(find.text('v2 (remoto)'), findsOneWidget);
    expect(find.text('v1'), findsNothing);
  });

  testWidgets('atualização remota com edição local mantém o texto e mostra aviso',
      (tester) async {
    final repo = MemoryRepository();
    await repo.upsertNote(const Note(id: 'n1', title: 'Cálculo', body: 'v1'));
    await pumpApp(tester, repo, location: '/nota/n1');
    await tester.enterText(find.byKey(const Key('note-body')), 'editando localmente');

    await repo.upsertNote(const Note(id: 'n1', title: 'Cálculo', body: 'v2 (remoto)'));
    await tester.pump();

    expect(find.text('editando localmente'), findsOneWidget);
    expect(
      find.text(
        'Esta nota foi alterada em outro dispositivo; suas alterações vão substituí-la ao salvar.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('excluir nota pede confirmação e volta para a tela anterior', (tester) async {
    final repo = MemoryRepository();
    await repo.upsertSpace(const Space(id: 's1', name: 'Cálculo I', kind: SpaceKind.materia));
    await repo.upsertNote(const Note(id: 'n1', title: 'Limites', spaceId: 's1'));
    await pumpApp(tester, repo, location: '/espacos/s1');
    await tester.tap(find.text('Limites'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('delete-note')));
    await tester.pumpAndSettle();
    expect(find.text('Excluir “Limites”?'), findsOneWidget);

    // Cancelar não apaga nem sai da tela.
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('note-title')), findsOneWidget);
    expect(await repo.watchNotes().first, hasLength(1));

    await tester.tap(find.byKey(const Key('delete-note')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir'));
    await tester.pumpAndSettle();

    expect(await repo.watchNotes().first, isEmpty);
    expect(find.widgetWithText(AppBar, 'Cálculo I'), findsOneWidget);
    expect(find.byKey(const Key('note-title')), findsNothing);
  });

  testWidgets('excluir nota com edições pendentes não a recria', (tester) async {
    final repo = MemoryRepository();
    await repo.upsertSpace(const Space(id: 's1', name: 'Cálculo I', kind: SpaceKind.materia));
    await repo.upsertNote(const Note(id: 'n1', title: 'Limites', spaceId: 's1'));
    await pumpApp(tester, repo, location: '/espacos/s1');
    await tester.tap(find.text('Limites'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('note-body')), 'edição pendente');
    await tester.tap(find.byKey(const Key('delete-note')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Excluir'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(await repo.watchNotes().first, isEmpty);
  });

  testWidgets('falha ao excluir nota mostra aviso em pt-BR', (tester) async {
    final repo = MemoryRepository();
    await repo.upsertNote(const Note(id: 'n1', title: 'Limites'));
    await pumpApp(tester, repo, location: '/nota/n1');
    repo.failWrites = true;
    await tester.tap(find.byKey(const Key('delete-note')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir'));
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível excluir a nota.'), findsOneWidget);
    expect(find.byKey(const Key('note-title')), findsOneWidget);
  });

  testWidgets('queda de conexão no stream não derruba o editor com texto já carregado',
      (tester) async {
    final repo = _FlakyNoteRepository();
    await repo.upsertNote(const Note(id: 'n1', title: 'Cálculo', body: 'conteúdo'));
    await pumpApp(tester, repo, location: '/nota/n1');
    expect(find.byKey(const Key('note-body')), findsOneWidget);

    repo.failNotesStream(Exception('RealtimeSubscribeException: network blip'));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('note-body')), findsOneWidget);
    expect(find.text('conteúdo'), findsOneWidget);
    expect(find.text('Sem conexão com o servidor. Tentando de novo…'), findsOneWidget);
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

/// Repositório de teste cujo watchNotes() pode ser forçado a emitir um erro
/// (simulando uma queda de rede), sem fechar o stream.
class _FlakyNoteRepository extends MemoryRepository {
  final _errors = StreamController<Object>.broadcast();

  void failNotesStream(Object error) => _errors.add(error);

  @override
  Stream<List<Note>> watchNotes() {
    final base = super.watchNotes();
    late StreamController<List<Note>> controller;
    StreamSubscription<List<Note>>? dataSub;
    StreamSubscription<Object>? errSub;
    controller = StreamController<List<Note>>(
      onListen: () {
        dataSub = base.listen(controller.add, onError: controller.addError);
        errSub = _errors.stream.listen(controller.addError);
      },
      onCancel: () {
        dataSub?.cancel();
        errSub?.cancel();
      },
    );
    return controller.stream;
  }
}
