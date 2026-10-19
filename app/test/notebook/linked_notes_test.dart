import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/data/repository.dart';
import 'package:organizacional/domain/note.dart';
import 'package:organizacional/domain/notebook_cover.dart';
import 'package:organizacional/domain/notebook_linked_note.dart';
import 'package:organizacional/domain/notebook_pdf.dart';
import 'package:organizacional/notebook/linked_notes.dart';

/// Repositório cuja leitura nunca responde (sem rede): a escrita ainda funciona.
class _HangingReads extends MemoryRepository {
  @override
  Stream<List<Note>> watchNotes() => StreamController<List<Note>>().stream;
}

void main() {
  late MemoryRepository repo;
  late LinkedNotes linked;
  const pdf = NotebookPdfFile(path: 'u/c1/0.pdf', name: 'Cálculo.pdf', pages: 10);
  final cover = NotebookCover(kind: CoverKind.emoji, emoji: '📒');

  Note nb() => const Note(id: 'c1', title: 'Cálculo', kind: NoteKind.notebook, spaceId: 's1')
      .withPdfFile(pdf, book: true)
      .withCover(cover);

  Future<List<Note>> notes() => repo.watchNotes().first;
  Future<Note> notebook() async => (await notes()).firstWhere((n) => n.id == 'c1');
  Future<List<Note>> texts() async => (await notes()).where((n) => !n.isNotebook).toList();

  setUp(() async {
    repo = MemoryRepository();
    linked = LinkedNotes(repo);
    await repo.upsertNote(nb());
  });

  test('o primeiro envio cria "Notas — <caderno>" na mesma pasta e grava o vínculo sem perder capa nem PDF', () async {
    final r = await linked.add('c1', 'BLOCO 1');
    expect(r.created, isTrue);
    final note = (await texts()).single;
    expect(note.id, r.note.id);
    expect(note.title, 'Notas — Cálculo');
    expect(note.spaceId, 's1');
    expect(note.isNotebook, isFalse);
    expect(note.body, 'BLOCO 1');
    final book = await notebook();
    expect(book.linkedNoteId, note.id);
    expect(book.cover, cover);
    expect(book.pdfInfo!.files, [pdf]);
    expect(book.isPdfBook, isTrue);
  });

  test('o segundo envio acrescenta à mesma nota, ao fim', () async {
    final first = await linked.add('c1', 'BLOCO 1');
    final second = await linked.add('c1', 'BLOCO 2');
    expect(second.created, isFalse);
    expect(second.note.id, first.note.id);
    final all = await texts();
    expect(all, hasLength(1));
    expect(all.single.body, 'BLOCO 1\n\nBLOCO 2');
  });

  test('nota vinculada apagada: cria outra e atualiza o vínculo', () async {
    final first = await linked.add('c1', 'BLOCO 1');
    await repo.deleteNote(first.note.id);
    final again = await linked.add('c1', 'BLOCO 2');
    expect(again.created, isTrue);
    expect(again.note.id, isNot(first.note.id));
    expect((await texts()).single.body, 'BLOCO 2');
    expect((await notebook()).linkedNoteId, again.note.id);
  });

  test('título ocupado por outra nota com texto: usa "(2)"', () async {
    await repo.upsertNote(const Note(id: 'x', title: 'Notas — Cálculo', body: 'minhas coisas'));
    final r = await linked.add('c1', 'BLOCO');
    expect(r.created, isTrue);
    expect(r.note.title, 'Notas — Cálculo (2)');
    expect((await notes()).firstWhere((n) => n.id == 'x').body, 'minhas coisas');
    // Próximo envio: continua na "(2)".
    final next = await linked.add('c1', 'BLOCO 2');
    expect(next.note.id, r.note.id);
  });

  test('título ocupado por (2) também: usa "(3)"', () async {
    await repo.upsertNote(const Note(id: 'x', title: 'Notas — Cálculo', body: 'a'));
    await repo.upsertNote(const Note(id: 'y', title: 'notas — cálculo (2)', body: 'b'));
    expect((await linked.add('c1', 'B')).note.title, 'Notas — Cálculo (3)');
  });

  test('título ocupado por nota vazia: reaproveita, sem criar outra', () async {
    await repo.upsertNote(const Note(id: 'x', title: 'Notas — Cálculo', spaceId: 's2'));
    final r = await linked.add('c1', 'BLOCO');
    expect(r.note.id, 'x');
    expect(r.created, isFalse, reason: 'já existia: desfazer não a apaga');
    expect(await texts(), hasLength(1));
    expect((await notebook()).linkedNoteId, 'x');
    expect((await texts()).single.body, 'BLOCO');
  });

  test('nota vazia que já é a vinculada de outro caderno não é reaproveitada', () async {
    await repo.upsertNote(const Note(id: 'x', title: 'Notas — Cálculo'));
    await repo.upsertNote(const Note(id: 'c2', title: 'Outro', kind: NoteKind.notebook).withLinkedNoteId('x'));
    final r = await linked.add('c1', 'BLOCO');
    expect(r.note.id, isNot('x'));
    expect(r.note.title, 'Notas — Cálculo (2)');
  });

  test('acrescentar relê a nota mais recente: não perde o que outro aparelho escreveu', () async {
    final first = await linked.add('c1', 'BLOCO 1');
    // Outro aparelho editou a nota; este aparelho ainda tem a versão antiga em cache.
    await repo.upsertNote(first.note.copyWith(body: 'BLOCO 1\n\nescrito no tablet'));
    final stale = [first.note, await notebook()];
    final cached = LinkedNotes(repo, cachedNotes: () => stale);
    await cached.add('c1', 'BLOCO 2');
    expect((await texts()).single.body, 'BLOCO 1\n\nescrito no tablet\n\nBLOCO 2');
  });

  test('sem resposta do servidor, usa as notas em cache e ainda grava', () async {
    final hanging = _HangingReads();
    await hanging.upsertNote(nb());
    final cached = LinkedNotes(
      hanging,
      cachedNotes: () => [nb()],
      readTimeout: const Duration(milliseconds: 20),
    );
    final r = await cached.add('c1', 'BLOCO');
    expect(r.note.title, 'Notas — Cálculo');
  });

  test('caderno que não existe: erro do repositório', () async {
    expect(() => linked.add('nada', 'B'), throwsA(isA<RepositoryException>()));
  });

  test('sem conexão: o erro sobe e nada fica pela metade', () async {
    repo.failWrites = true;
    await expectLater(linked.add('c1', 'B'), throwsA(isA<RepositoryException>()));
    repo.failWrites = false;
    expect(await texts(), isEmpty);
    expect((await notebook()).linkedNoteId, isNull);
  });

  group('ensure (botão Notas)', () {
    test('cria a nota vazia e vincula; da segunda vez devolve a mesma', () async {
      final a = await linked.ensure('c1');
      expect(a.created, isTrue);
      expect(a.note.body, '');
      final b = await linked.ensure('c1');
      expect(b.created, isFalse);
      expect(b.note.id, a.note.id);
      expect(await texts(), hasLength(1));
      expect((await notebook()).cover, cover);
    });
  });

  group('desfazer', () {
    test('tira o bloco recém-acrescentado e deixa o resto', () async {
      await linked.add('c1', 'BLOCO 1');
      final r = await linked.add('c1', 'BLOCO 2');
      await linked.undo('c1', r);
      expect((await texts()).single.body, 'BLOCO 1');
      expect((await notebook()).linkedNoteId, isNotNull);
    });

    test('nota criada agora e ficou vazia: apaga a nota e limpa o vínculo, mantendo capa e PDF', () async {
      final r = await linked.add('c1', 'BLOCO 1');
      await linked.undo('c1', r);
      expect(await texts(), isEmpty);
      final book = await notebook();
      expect(book.linkedNoteId, isNull);
      expect(book.cover, cover);
      expect(book.pdfInfo!.files, [pdf]);
    });

    test('nota criada agora, mas o usuário já escreveu nela: fica, só sem o bloco', () async {
      final r = await linked.add('c1', 'BLOCO 1');
      await repo.upsertNote(r.note.copyWith(body: 'meu texto\n\nBLOCO 1'));
      await linked.undo('c1', r);
      expect((await texts()).single.body, 'meu texto');
      expect((await notebook()).linkedNoteId, r.note.id);
    });

    test('nota reaproveitada (já existia vazia) não é apagada', () async {
      await repo.upsertNote(const Note(id: 'x', title: 'Notas — Cálculo'));
      final r = await linked.add('c1', 'BLOCO');
      await linked.undo('c1', r);
      expect((await texts()).single.body, '');
    });

    test('bloco que já não está na nota: não mexe em nada', () async {
      final r = await linked.add('c1', 'BLOCO 1');
      await repo.upsertNote(r.note.copyWith(body: 'reescrito'));
      await linked.undo('c1', r);
      expect((await texts()).single.body, 'reescrito');
    });

    test('nota apagada nesse meio tempo: não falha', () async {
      final r = await linked.add('c1', 'BLOCO 1');
      await repo.deleteNote(r.note.id);
      await linked.undo('c1', r);
      expect(await texts(), isEmpty);
    });
  });
}
