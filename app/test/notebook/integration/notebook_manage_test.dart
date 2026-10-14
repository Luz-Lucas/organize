import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/note.dart';
import 'package:organizacional/notebook/data/memory_notebook_repository.dart';
import 'package:organizacional/notebook/data/notebook_image_purger.dart';
import 'package:organizacional/notebook/ui/notebook_session.dart';

import '../../helpers.dart';

class _PurgeableStore implements NotebookImageStore, NotebookImagePurger {
  _PurgeableStore(this.noteId, this.purged);
  final String noteId;
  final List<String> purged;

  @override
  Future<void> purgeAll() async => purged.add(noteId);
  @override
  Future<String> upload(Uint8List bytes, String ext) async => 'x';
  @override
  Future<ImageProvider> load(String path) async => throw UnimplementedError();
}

const _phone = Size(400, 800);

void main() {
  late MemoryRepository repo;
  late MemoryNotebookRepository nb;
  late List<String> purged;

  setUp(() async {
    repo = MemoryRepository();
    nb = MemoryNotebookRepository();
    purged = [];
    await repo.upsertNote(const Note(id: 'c1', title: 'Biologia', kind: NoteKind.notebook));
    await repo.upsertNote(const Note(id: 'c2', title: 'Física', kind: NoteKind.notebook));
    await repo.upsertNote(const Note(id: 't1', title: 'Resumo'));
  });

  Future<void> open(WidgetTester tester) => pumpApp(tester, repo,
      notebookRepo: nb,
      size: _phone,
      location: '/notas',
      notebookImages: (id) => _PurgeableStore(id, purged));

  Future<List<Note>> notes() => repo.watchNotes().first;

  Future<void> menu(WidgetTester tester, String id) async {
    await tester.longPress(find.byKey(ValueKey('tree-note-$id')));
    await tester.pumpAndSettle();
  }

  testWidgets('segurar o caderno abre o menu Renomear/Excluir; nota de texto não tem menu', (tester) async {
    await open(tester);
    await menu(tester, 'c1');
    expect(find.byKey(const Key('notebook-menu-rename')), findsOneWidget);
    expect(find.byKey(const Key('notebook-menu-delete')), findsOneWidget);
    await tester.tapAt(const Offset(5, 5)); // fecha o menu
    await tester.pumpAndSettle();
    await menu(tester, 't1'); // sem onLongPress: o toque longo só abre a nota, como antes
    expect(find.byKey(const Key('notebook-menu-rename')), findsNothing);
  });

  testWidgets('renomear troca só o título e mantém o tipo caderno', (tester) async {
    await open(tester);
    await menu(tester, 'c1');
    await tester.tap(find.byKey(const Key('notebook-menu-rename')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('notebook-rename-field')), 'Biologia II');
    await tester.tap(find.byKey(const Key('notebook-rename-ok')));
    await tester.pumpAndSettle();
    final c1 = (await notes()).firstWhere((n) => n.id == 'c1');
    expect(c1.title, 'Biologia II');
    expect(c1.kind, NoteKind.notebook);
    expect(find.text('Biologia II'), findsOneWidget);
  });

  testWidgets('renomear para um título que já existe mostra o erro e mantém o nome', (tester) async {
    await open(tester);
    await menu(tester, 'c1');
    await tester.tap(find.byKey(const Key('notebook-menu-rename')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('notebook-rename-field')), 'Física');
    await tester.tap(find.byKey(const Key('notebook-rename-ok')));
    await tester.pumpAndSettle();
    expect(find.text('Já existe uma nota com esse título.'), findsOneWidget);
    expect((await notes()).firstWhere((n) => n.id == 'c1').title, 'Biologia');
  });

  testWidgets('excluir pede confirmação, apaga a nota e limpa as imagens do Storage', (tester) async {
    await open(tester);
    await menu(tester, 'c1');
    await tester.tap(find.byKey(const Key('notebook-menu-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notebook-delete-cancel')));
    await tester.pumpAndSettle();
    expect((await notes()).any((n) => n.id == 'c1'), isTrue);
    expect(purged, isEmpty);

    await menu(tester, 'c1');
    await tester.tap(find.byKey(const Key('notebook-menu-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notebook-delete-confirm')));
    await tester.pumpAndSettle();
    expect((await notes()).any((n) => n.id == 'c1'), isFalse);
    expect(purged, ['c1']);
    expect(find.byKey(const ValueKey('tree-note-c1')), findsNothing);
  });
}
