import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide TextBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/notebook/core/notebook_core.dart';
import 'package:organizacional/notebook/ui/notebook_screen.dart';

import 'menu_support.dart';
import 'ui_support.dart';

PageDoc docWith(String id, {double y = 300}) =>
    PageDoc.empty.withStroke(testStroke(id, Offset(200, y), Offset(400, y)));

Set<String> ids(PageDoc d) => {for (final s in d.strokes) s.id};

Future<void> draw(WidgetTester tester, {int idx = 0}) => SimPointer(tester, PointerDeviceKind.stylus, idx: idx)
    .drag(linePath(const Offset(100, 100), const Offset(400, 100)));

const _tall = Size(800, 5000);

void main() {
  group('páginas casadas por id, não por posição', () {
    testWidgets('duplicar com A e B e depois desenhar em B não mistura a tinta de A', (tester) async {
      final s = FakeSession(pageCount: 2, docs: [docWith('a'), docWith('b')]);
      await pumpNotebook(tester, s, size: _tall);
      await tester.tap(find.byKey(const ValueKey('nb-page-dup-0')));
      await tester.pump();
      await tester.pump();
      expect(s.current, hasLength(3));
      // Ordem agora: A, cópia de A, B.
      await draw(tester, idx: 2);
      final upd = s.updates.single;
      expect(upd.id, s.idOf(2));
      expect(ids(upd.doc), hasLength(2));
      expect(ids(upd.doc), contains('b'));
      expect(ids(upd.doc), isNot(contains('a')));
      // A cópia e a original seguem só com a tinta de A.
      expect(ids(s.docOf(0)), {'a'});
      expect(ids(s.docOf(1)), {'a'});
    });

    testWidgets('uma página inserida no meio por outro aparelho não mistura as vizinhas', (tester) async {
      final s = FakeSession(pageCount: 2, docs: [docWith('a'), docWith('b')]);
      await pumpNotebook(tester, s, size: _tall);
      s.remoteInsert(1, doc: docWith('x'));
      await tester.pump();
      await tester.pump();
      expect(s.current.map((p) => ids(p.doc)), [
        {'a'},
        {'x'},
        {'b'},
      ]);
      await draw(tester, idx: 2);
      expect(ids(s.updates.single.doc), contains('b'));
      expect(ids(s.updates.single.doc), isNot(contains('x')));
      expect(ids(s.updates.single.doc), isNot(contains('a')));
      await draw(tester, idx: 1);
      expect(ids(s.updates.last.doc), contains('x'));
      expect(ids(s.updates.last.doc), isNot(contains('b')));
    });

    testWidgets('apagar uma página não faz as seguintes herdarem a tinta da apagada', (tester) async {
      final s = FakeSession(pageCount: 3, docs: [docWith('a'), docWith('b'), docWith('c')]);
      await pumpNotebook(tester, s, size: _tall);
      await tester.tap(find.byKey(const ValueKey('nb-page-del-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nb-confirm-yes')));
      await tester.pumpAndSettle();
      expect(s.current, hasLength(2));
      await draw(tester, idx: 0);
      expect(ids(s.updates.single.doc), contains('b'));
      expect(ids(s.updates.single.doc), isNot(contains('a')));
    });

    testWidgets('desfazer depois de uma inserção remota vai para a página certa', (tester) async {
      final s = FakeSession(pageCount: 2);
      await pumpNotebook(tester, s, size: _tall);
      await draw(tester, idx: 0); // ativa a página A
      final aId = s.idOf(0);
      expect(s.docOf(0).strokes, hasLength(1));
      s.remoteInsert(0, doc: docWith('x')); // A desce para o índice 1
      await tester.pump();
      await tester.pump();
      expect(s.idOf(1), aId);
      await tester.tap(find.byKey(const ValueKey('nb-undo')));
      await tester.pump();
      expect(s.updates.last.id, aId);
      expect(s.docOf(1).strokes, isEmpty);
      expect(ids(s.docOf(0)), {'x'});
    });

    testWidgets('apagar a página: o diálogo fixa o id, mesmo que a lista mude enquanto ele está aberto', (tester) async {
      final s = FakeSession(pageCount: 2, docs: [docWith('a'), docWith('b')]);
      await pumpNotebook(tester, s, size: _tall);
      final bId = s.idOf(1);
      await tester.tap(find.byKey(const ValueKey('nb-page-del-1')));
      await tester.pumpAndSettle();
      s.remoteInsert(0, doc: docWith('x')); // B passa a ser o índice 2 com o diálogo aberto
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('nb-confirm-yes')));
      await tester.pumpAndSettle();
      expect(s.current.map((p) => ids(p.doc)), [
        {'x'},
        {'a'},
      ]);
      expect(s.indexOfId(bId), -1);
    });

    testWidgets('inserir imagem: o envio fixa o id da página ativa mesmo que ela mude de posição', (tester) async {
      final s = FakeSession(pageCount: 2);
      await pumpNotebook(
        tester,
        s,
        size: _tall,
        pickImage: () async {
          // Enquanto o usuário escolhe, chega uma página nova antes da ativa.
          s.remoteInsert(0);
          return PickedImage(bytes: kPng, ext: 'png', width: 100, height: 50);
        },
      );
      await draw(tester, idx: 1); // ativa a página B
      final bId = s.idOf(1);
      await openMenu(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('nb-tool-image')));
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('nb-tool-image')));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      final withImage = s.current.where((p) => p.doc.images.isNotEmpty).toList();
      expect(withImage, hasLength(1));
      expect(withImage.single.id, bId);
    });
  });

  group('avisos por página', () {
    testWidgets('página "mais nova que o app" fica só para leitura, com o aviso', (tester) async {
      final s = FakeSession(pageCount: 1);
      await pumpNotebook(tester, s);
      s.remoteNotice(0, PageNotice.newerVersion);
      await tester.pump();
      await tester.pump();
      expect(find.text('Esta página foi feita numa versão mais nova do app'), findsOneWidget);
      await draw(tester);
      expect(s.updates, isEmpty);
    });

    testWidgets('página grande demais mostra o aviso para dividir em outra página', (tester) async {
      final s = FakeSession(pageCount: 1);
      await pumpNotebook(tester, s);
      s.remoteNotice(0, PageNotice.tooLarge);
      await tester.pump();
      await tester.pump();
      expect(find.text('Página grande demais — divida em outra página'), findsOneWidget);
    });

    testWidgets('caderno excluído em outro aparelho aparece na barra', (tester) async {
      final s = FakeSession(pageCount: 1);
      await pumpNotebook(tester, s);
      s.setStatus(SaveStatus.noteDeleted);
      await tester.pump();
      await tester.pump();
      expect(find.text('Este caderno foi excluído em outro aparelho'), findsOneWidget);
    });
  });
}
