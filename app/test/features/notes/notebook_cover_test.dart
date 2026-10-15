import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/note.dart';
import 'package:organizacional/domain/notebook_cover.dart';
import 'package:organizacional/features/notes/notebooks/cover_editor.dart';
import 'package:organizacional/features/notes/notebooks/notebooks_prefs.dart';
import 'package:organizacional/notebook/data/memory_notebook_repository.dart';
import 'package:organizacional/notebook/notebook_cover_view.dart';
import 'package:organizacional/notebook/ui/notebook_screen.dart' show PickedImage;

import '../../helpers.dart';
import '../../notebook/data/fake_image_store.dart';

Finder _key(String k) => find.byKey(Key(k));
Finder _vkey(String k) => find.byKey(ValueKey(k));

// PNG 1x1 transparente.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

void main() {
  late MemoryRepository repo;
  late FakeNotebookImageStore images;
  PickedImage? nextPick;

  setUp(() async {
    repo = MemoryRepository();
    images = FakeNotebookImageStore();
    nextPick = null;
    await repo.upsertNote(Note(id: 'c1', title: 'Limites', kind: NoteKind.notebook, updatedAt: DateTime(2026, 9, 28)));
  });

  Future<void> open(WidgetTester tester) async {
    await pumpApp(
      tester,
      repo,
      notebookRepo: MemoryNotebookRepository(),
      notebookImages: (_) => images,
      size: const Size(400, 800),
      location: '/notas',
      overrides: [
        notesTabPrefsProvider.overrideWithValue(MemoryNotesTabPrefs()),
        coverImagePickerProvider.overrideWithValue(() async => nextPick),
      ],
    );
    await tester.tap(_key('notes-tab-notebooks'));
    await tester.pumpAndSettle();
  }

  Future<void> openEditor(WidgetTester tester) async {
    await tester.longPress(_vkey('nb-card-c1'));
    await tester.pumpAndSettle();
    await tester.tap(_key('notebook-menu-cover'));
    await tester.pumpAndSettle();
  }

  Future<NotebookCover?> cover() async => (await repo.watchNotes().first).firstWhere((n) => n.id == 'c1').cover;

  testWidgets('capa de texto com cor: grava e aparece no cartão', (tester) async {
    await open(tester);
    expect(find.descendant(of: _vkey('nb-card-c1'), matching: _vkey('nb-cover')), findsNothing);
    await openEditor(tester);
    // Começa com o título do caderno.
    expect(find.descendant(of: _key('cover-text'), matching: find.text('Limites')), findsOneWidget);
    await tester.enterText(_key('cover-text'), 'Cálculo I');
    await tester.tap(_vkey('cover-color-${kCoverColors.first}'));
    await tester.pump();
    await tester.tap(_key('cover-save'));
    await tester.pumpAndSettle();

    expect(await cover(), NotebookCover(kind: CoverKind.text, text: 'Cálculo I', color: kCoverColors.first));
    expect(find.descendant(of: _vkey('nb-card-c1'), matching: _vkey('nb-cover')), findsOneWidget);
    expect(find.descendant(of: _vkey('nb-card-c1'), matching: find.text('Cálculo I')), findsOneWidget);
  });

  testWidgets('capa de emoji: fica só um emoji', (tester) async {
    await open(tester);
    await openEditor(tester);
    await tester.tap(find.text('Emoji'));
    await tester.pump();
    expect(tester.widget<FilledButton>(_key('cover-save')).onPressed, isNull);
    await tester.enterText(_key('cover-emoji'), '📐🧪');
    await tester.pump();
    await tester.tap(_key('cover-save'));
    await tester.pumpAndSettle();
    final c = await cover();
    expect(c?.kind, CoverKind.emoji);
    expect(c?.emoji, '🧪');
  });

  testWidgets('capa de imagem: envia ao Storage do caderno e guarda o encaixe', (tester) async {
    nextPick = PickedImage(bytes: _png, ext: 'png');
    await open(tester);
    await openEditor(tester);
    await tester.tap(find.text('Imagem'));
    await tester.pump();
    // Preencher não mostra a cor (não sobra fundo).
    expect(_vkey('cover-color-${kCoverColors.first}'), findsNothing);
    await tester.tap(_key('cover-pick-image'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inteira (com fundo)'));
    await tester.pump();
    await tester.tap(_vkey('cover-color-${kCoverColors.last}'));
    await tester.pump();
    await tester.tap(_key('cover-save'));
    await tester.pumpAndSettle();

    final c = await cover();
    expect(c?.kind, CoverKind.image);
    expect(c?.fit, CoverFit.fit);
    expect(c?.color, kCoverColors.last);
    expect(images.uploads.keys, [c?.imagePath]);
    expect(find.descendant(of: _vkey('nb-card-c1'), matching: find.byType(NotebookCoverView)), findsOneWidget);
  });

  testWidgets('tirar a capa volta à miniatura da página', (tester) async {
    await repo.upsertNote(
      Note(
        id: 'c1',
        title: 'Limites',
        kind: NoteKind.notebook,
      ).withCover(const NotebookCover(kind: CoverKind.emoji, emoji: '📐')),
    );
    await open(tester);
    expect(find.descendant(of: _vkey('nb-card-c1'), matching: find.text('📐')), findsOneWidget);
    await openEditor(tester);
    await tester.tap(_key('cover-remove'));
    await tester.pumpAndSettle();
    expect(await cover(), isNull);
    expect(find.descendant(of: _vkey('nb-card-c1'), matching: _vkey('nb-cover')), findsNothing);
  });

  testWidgets('cancelar não muda nada', (tester) async {
    await open(tester);
    await openEditor(tester);
    await tester.enterText(_key('cover-text'), 'Outro');
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(await cover(), isNull);
  });

  testWidgets('na árvore: miniatura com a capa; a busca acha o texto da capa, não o JSON', (tester) async {
    await repo.upsertNote(
      Note(
        id: 'c1',
        title: 'Limites',
        kind: NoteKind.notebook,
      ).withCover(const NotebookCover(kind: CoverKind.text, text: 'Derivadas')),
    );
    await pumpApp(
      tester,
      repo,
      notebookRepo: MemoryNotebookRepository(),
      size: const Size(400, 800),
      location: '/notas',
      overrides: [notesTabPrefsProvider.overrideWithValue(MemoryNotesTabPrefs())],
    );
    expect(_vkey('tree-note-c1'), findsOneWidget);
    expect(find.descendant(of: _vkey('tree-note-c1'), matching: _vkey('nb-cover')), findsOneWidget);
    await tester.enterText(_key('notes-search'), 'derivadas');
    await tester.pumpAndSettle();
    expect(_vkey('tree-note-c1'), findsOneWidget);
    await tester.enterText(_key('notes-search'), 'cover');
    await tester.pumpAndSettle();
    expect(_vkey('tree-note-c1'), findsNothing);
  });
}
