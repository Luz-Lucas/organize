import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide TextBox;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/app/providers.dart';
import 'package:organizacional/data/memory_settings_repository.dart';
import 'package:organizacional/domain/user_settings.dart';
import 'package:organizacional/notebook/core/notebook_core.dart';
import 'package:organizacional/notebook/notebook_route.dart';
import 'package:organizacional/notebook/ui/notebook_prefs.dart';
import 'package:organizacional/notebook/ui/tool_settings.dart';
import 'package:organizacional/ui/org_theme.dart';

import 'menu_support.dart';
import 'ui_support.dart';

Finder k(String key) => find.byKey(ValueKey(key));

Future<void> tapK(WidgetTester tester, String key) async {
  await tester.tap(k(key));
  await tester.pumpAndSettle();
}

Future<void> drawLine(WidgetTester tester) => SimPointer(tester, PointerDeviceKind.stylus).drag(
  linePath(const Offset(100, 100), const Offset(400, 100)),
);

int favPenCount() => [for (var i = 0; i < 12; i++) if (k('nb-fav-pen-$i').evaluate().isNotEmpty) i].length;
int favColorCount() => [for (var i = 0; i < 12; i++) if (k('nb-fav-color-$i').evaluate().isNotEmpty) i].length;

void main() {
  group('barra compacta', () {
    testWidgets('mostra só os favoritos, borracha, laço, desfazer/refazer e o botão ⋯', (tester) async {
      await pumpNotebookPrefs(tester, FakeSession());
      expect(favPenCount(), 3);
      expect(favColorCount(), 5);
      for (final key in ['nb-tool-eraser', 'nb-tool-lasso', 'nb-undo', 'nb-redo', 'nb-more']) {
        expect(k(key), findsOneWidget, reason: key);
      }
      for (final key in [
        'nb-tool-pen',
        'nb-tool-fountain',
        'nb-tool-text',
        'nb-tool-image',
        'nb-add-page',
        'nb-zoom-in',
        'nb-finger-toggle',
        'nb-background',
        'nb-color-0',
        'nb-width-0',
      ]) {
        expect(k(key), findsNothing, reason: '$key só no menu');
      }
      expect(find.text('Ferramentas'), findsOneWidget); // rótulo do ⋯
    });

    testWidgets('caneta favorita aplica ferramenta, cor e espessura', (tester) async {
      final s = FakeSession();
      await pumpNotebookPrefs(tester, s);
      await tapK(tester, 'nb-fav-pen-2'); // marca-texto amarelo
      await drawLine(tester);
      final st = s.docOf(0).strokes.single;
      expect(st.tool, PenTool.highlighter);
      expect(st.argb & 0xFFFFFF, 0xFBBF24);
      expect(st.width, kPenWidths[1] * penWidthFactor(PenTool.highlighter));
    });

    testWidgets('a caneta preta favorita usa a cor de tinta do tema', (tester) async {
      final s = FakeSession();
      await pumpNotebookPrefs(tester, s);
      await tapK(tester, 'nb-fav-pen-1'); // azul
      await tapK(tester, 'nb-fav-pen-0'); // preta
      await drawLine(tester);
      final ink = tester.element(k('nb-page-0')).org.ink;
      expect(s.docOf(0).strokes.single.argb, ink.toARGB32());
      expect(s.docOf(0).strokes.single.tool, PenTool.pen);
    });

    testWidgets('cor favorita aplica a cor à caneta atual', (tester) async {
      final s = FakeSession();
      await pumpNotebookPrefs(tester, s);
      final org = tester.element(k('nb-page-0')).org;
      await tapK(tester, 'nb-fav-pen-0');
      await tapK(tester, 'nb-fav-color-2');
      await drawLine(tester);
      final st = s.docOf(0).strokes.single;
      expect(st.argb, org.accent.toARGB32());
      expect(st.tool, PenTool.pen);
    });

    testWidgets('cor favorita com a borracha ativa volta para a caneta', (tester) async {
      final s = FakeSession();
      await pumpNotebookPrefs(tester, s);
      await tapK(tester, 'nb-tool-eraser');
      await tapK(tester, 'nb-fav-color-3');
      await drawLine(tester);
      expect(s.docOf(0).strokes, hasLength(1));
    });

    testWidgets('tocar de novo na caneta selecionada abre o ajuste rápido; "Salvar no favorito" grava', (tester) async {
      final saved = <Map<String, dynamic>>[];
      await pumpNotebookPrefs(
        tester,
        FakeSession(),
        onPrefsChanged: (m) async => saved.add(m),
      );
      await tapK(tester, 'nb-fav-pen-1');
      expect(k('nb-quick-save'), findsNothing);
      await tapK(tester, 'nb-fav-pen-1');
      expect(k('nb-quick-save'), findsOneWidget);
      await tapK(tester, 'nb-quick-width-4');
      await tapK(tester, 'nb-quick-color-0');
      await tapK(tester, 'nb-quick-save');
      expect(k('nb-quick-save'), findsNothing);
      expect(saved, hasLength(1));
      final pens = NotebookPrefs.fromMap(saved.single).pens;
      expect(pens[1].widthIndex, 4);
      expect(pens[1].tool, PenTool.pen);
      expect(pens[1].argb, isNot(0xFF60A5FA)); // trocou a cor
      expect(pens, hasLength(3));
    });

    testWidgets('ajuste rápido sem salvar não altera o favorito', (tester) async {
      final saved = <Map<String, dynamic>>[];
      await pumpNotebookPrefs(tester, FakeSession(), onPrefsChanged: (m) async => saved.add(m));
      await tapK(tester, 'nb-fav-pen-0');
      await tapK(tester, 'nb-fav-pen-0');
      await tapK(tester, 'nb-quick-width-4');
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(saved, isEmpty);
    });
  });

  group('menu Ferramentas', () {
    testWidgets('⋯ abre o menu com tudo', (tester) async {
      await pumpNotebookPrefs(tester, FakeSession());
      await openMenu(tester);
      expect(k('nb-tools-menu'), findsOneWidget);
      for (final key in [
        'nb-tool-fountain',
        'nb-tool-pen',
        'nb-tool-pencil',
        'nb-tool-highlighter',
        'nb-menu-tool-eraser',
        'nb-menu-tool-lasso',
        'nb-tool-text',
        'nb-tool-image',
        for (var i = 0; i < 10; i++) 'nb-color-$i',
        'nb-color-custom',
        for (var i = 0; i < 5; i++) 'nb-width-$i',
        'nb-background',
        'nb-add-page',
        'nb-dup-page',
        'nb-del-page',
        'nb-zoom-in',
        'nb-zoom-out',
        'nb-zoom-label',
        'nb-finger-toggle',
        'nb-eraser-mode',
        'nb-compact-toggle',
        'nb-fav-edit',
      ]) {
        await tester.ensureVisible(k(key));
        expect(k(key), findsOneWidget, reason: key);
      }
    });

    testWidgets('canetas, cor e espessura do menu valem para o próximo traço', (tester) async {
      final s = FakeSession();
      await pumpNotebookPrefs(tester, s);
      final org = tester.element(k('nb-page-0')).org;
      await openMenu(tester);
      await tapInMenu(tester, 'nb-tool-pencil');
      await tapInMenu(tester, 'nb-color-2');
      await tapInMenu(tester, 'nb-width-4');
      await closeMenu(tester);
      await drawLine(tester);
      final st = s.docOf(0).strokes.single;
      expect(st.tool, PenTool.pencil);
      expect(st.argb & 0xFFFFFF, org.accent.toARGB32() & 0xFFFFFF);
      expect(st.width, 14.0);
    });

    testWidgets('a seleção no menu atualiza a barra (caneta favorita deixa de estar selecionada)', (tester) async {
      await pumpNotebookPrefs(tester, FakeSession());
      await tapK(tester, 'nb-fav-pen-0');
      Color? bg() => tester.widget<IconButton>(k('nb-fav-pen-0')).style?.backgroundColor?.resolve({});
      expect(bg(), isNotNull);
      await openMenu(tester);
      await tapInMenu(tester, 'nb-width-4');
      await closeMenu(tester);
      expect(bg(), isNull);
    });

    testWidgets('adicionar a caneta atual vira favorita e grava', (tester) async {
      final saved = <Map<String, dynamic>>[];
      await pumpNotebookPrefs(tester, FakeSession(), onPrefsChanged: (m) async => saved.add(m));
      await openMenu(tester);
      await tapInMenu(tester, 'nb-tool-pencil');
      await tapInMenu(tester, 'nb-width-3');
      await tapInMenu(tester, 'nb-fav-edit');
      await tapInMenu(tester, 'nb-fav-add-current');
      await closeMenu(tester);
      expect(favPenCount(), 4);
      final pens = NotebookPrefs.fromMap(saved.last).pens;
      expect(pens.last.tool, PenTool.pencil);
      expect(pens.last.widthIndex, 3);
      // a nova favorita está selecionada na barra e desenha igual
      await tapK(tester, 'nb-fav-pen-0');
      await tapK(tester, 'nb-fav-pen-3');
      expect(tester.widget<IconButton>(k('nb-fav-pen-3')).style?.backgroundColor?.resolve({}), isNotNull);
    });

    testWidgets('remover caneta favorita', (tester) async {
      final saved = <Map<String, dynamic>>[];
      await pumpNotebookPrefs(tester, FakeSession(), onPrefsChanged: (m) async => saved.add(m));
      await openMenu(tester);
      await tapInMenu(tester, 'nb-fav-edit');
      await tapInMenu(tester, 'nb-fav-remove-0');
      await closeMenu(tester);
      expect(favPenCount(), 2);
      final pens = NotebookPrefs.fromMap(saved.last).pens;
      expect(pens.map((e) => e.tool), [PenTool.pen, PenTool.highlighter]);
      expect(pens.first.argb, 0xFF60A5FA); // sobrou a azul
    });

    testWidgets('reordenar arrastando', (tester) async {
      final saved = <Map<String, dynamic>>[];
      await pumpNotebookPrefs(tester, FakeSession(), onPrefsChanged: (m) async => saved.add(m));
      await openMenu(tester);
      await tapInMenu(tester, 'nb-fav-edit');
      await tester.ensureVisible(k('nb-fav-handle-0'));
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(tester.getCenter(k('nb-fav-handle-0')));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 60));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 60));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      final pens = NotebookPrefs.fromMap(saved.last).pens;
      expect(pens.map((e) => e.tool), [PenTool.pen, PenTool.highlighter, PenTool.pen]);
      expect(pens.first.argb, 0xFF60A5FA);
      expect(pens.last.argb, isNull); // a preta foi para o fim
    });

    testWidgets('limite de 8 canetas favoritas', (tester) async {
      final saved = <Map<String, dynamic>>[];
      await pumpNotebookPrefs(tester, FakeSession(), onPrefsChanged: (m) async => saved.add(m));
      await openMenu(tester);
      await tapInMenu(tester, 'nb-fav-edit');
      for (var i = 0; i < 5; i++) {
        await tapInMenu(tester, 'nb-width-${i % 5}');
        await tapInMenu(tester, 'nb-tool-fountain');
        await tapInMenu(tester, 'nb-fav-add-current');
        await tapInMenu(tester, 'nb-tool-pencil');
        await tapInMenu(tester, 'nb-fav-add-current');
      }
      expect(NotebookPrefs.fromMap(saved.last).pens, hasLength(8));
      final add = tester.widget<ButtonStyleButton>(k('nb-fav-add-current'));
      expect(add.onPressed, isNull);
      await closeMenu(tester);
      expect(favPenCount(), 8);
      expect(favPenCount(), kMaxFavoritePens);
    });

    testWidgets('cores favoritas: adicionar a cor atual, remover e limite de 8', (tester) async {
      final saved = <Map<String, dynamic>>[];
      await pumpNotebookPrefs(tester, FakeSession(), onPrefsChanged: (m) async => saved.add(m));
      final org = tester.element(k('nb-page-0')).org;
      await openMenu(tester);
      await tapInMenu(tester, 'nb-fav-edit');
      await tapInMenu(tester, 'nb-color-9'); // azul claro, fora dos 5 favoritos
      await tapInMenu(tester, 'nb-fav-color-add');
      expect(NotebookPrefs.fromMap(saved.last).colorsFor(org), hasLength(6));
      await tapInMenu(tester, 'nb-fav-color-remove-0');
      expect(NotebookPrefs.fromMap(saved.last).colorsFor(org), hasLength(5));
      for (final i in [8, 7, 6, 5]) {
        await tapInMenu(tester, 'nb-color-$i');
        await tapInMenu(tester, 'nb-fav-color-add');
      }
      expect(NotebookPrefs.fromMap(saved.last).colorsFor(org), hasLength(8));
      expect(tester.widget<ButtonStyleButton>(k('nb-fav-color-add')).onPressed, isNull);
      await closeMenu(tester);
      expect(favColorCount(), 8);
    });

    testWidgets('"Barra compacta" desligada volta à barra completa; ligada, aos favoritos', (tester) async {
      final saved = <Map<String, dynamic>>[];
      await pumpNotebookPrefs(tester, FakeSession(), onPrefsChanged: (m) async => saved.add(m));
      await tapMenu(tester, 'nb-compact-toggle');
      expect(saved.last['compact'], false);
      expect(favPenCount(), 0);
      for (final key in ['nb-tool-pen', 'nb-tool-text', 'nb-add-page', 'nb-color-0', 'nb-width-0', 'nb-zoom-in', 'nb-more']) {
        expect(k(key), findsOneWidget, reason: key);
      }
      // o menu da barra completa traz os favoritos, a chave e a página
      await openMenu(tester);
      expect(k('nb-fav-edit'), findsOneWidget);
      expect(k('nb-compact-toggle'), findsOneWidget);
      expect(k('nb-tool-pen'), findsOneWidget); // só a da barra, sem duplicata
      await tapInMenu(tester, 'nb-compact-toggle');
      await closeMenu(tester);
      expect(saved.last['compact'], true);
      expect(favPenCount(), 3);
    });

    testWidgets('na barra completa a ferramenta funciona sem abrir o menu', (tester) async {
      final s = FakeSession();
      await pumpNotebookPrefs(tester, s, prefs: {'compact': false});
      await tapK(tester, 'nb-tool-highlighter');
      await drawLine(tester);
      expect(s.docOf(0).strokes.single.tool, PenTool.highlighter);
    });

    testWidgets('em tela estreita o menu é uma folha inferior; em larga, um painel lateral', (tester) async {
      await pumpNotebookPrefs(tester, FakeSession(), size: const Size(360, 780));
      await openMenu(tester);
      var r = tester.getRect(k('nb-tools-menu'));
      expect(r.width, 360);
      expect(r.bottom, closeTo(780, 1));
      await closeMenu(tester);
      await pumpNotebookPrefs(tester, FakeSession(), size: const Size(1000, 800));
      await openMenu(tester);
      r = tester.getRect(k('nb-tools-menu'));
      expect(r.right, closeTo(1000, 1));
      expect(r.width, lessThan(500));
      expect(r.height, closeTo(800, 1));
    });
  });

  group('sincronização dos favoritos', () {
    testWidgets('favoritos que chegam de outro aparelho atualizam a barra', (tester) async {
      final repo = MemorySettingsRepository();
      await tester.binding.setSurfaceSize(const Size(800, 1300));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [settingsRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(
            theme: buildOrgTheme(orgThemes.first, googleFonts: false),
            home: NotebookScreenHost(noteId: 'n1', title: 'Meu caderno', session: FakeSession()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(favPenCount(), 3);
      final remote = NotebookPrefs.fromMap(const {})
          .removePenAt(2)
          .removePenAt(1)
          .addPen(const FavoritePen(tool: PenTool.pencil, argb: 0xFF010203, widthIndex: 4))
          .toMap();
      await repo.setNotebookPrefs(remote);
      await tester.pump();
      await tester.pump();
      expect(favPenCount(), 2);
    });

    testWidgets('editar favoritos grava no repositório (só notebook_prefs)', (tester) async {
      final repo = MemorySettingsRepository(initial: const UserSettings(theme: 'coral'));
      await tester.binding.setSurfaceSize(const Size(800, 1300));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [settingsRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(
            theme: buildOrgTheme(orgThemes.first, googleFonts: false),
            home: NotebookScreenHost(noteId: 'n1', title: 'Meu caderno', session: FakeSession()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await openMenu(tester);
      await tapInMenu(tester, 'nb-fav-edit');
      await tapInMenu(tester, 'nb-fav-remove-0');
      await closeMenu(tester);
      final s = await repo.watchSettings().first;
      expect(s.theme, 'coral');
      expect(NotebookPrefs.fromMap(s.notebookPrefs).pens, hasLength(2));
      expect(favPenCount(), 2);
    });

    testWidgets('falha ao gravar mostra aviso e mantém a edição na tela', (tester) async {
      await pumpNotebookPrefs(
        tester,
        FakeSession(),
        onPrefsChanged: (m) async => throw Exception('sem rede'),
      );
      await openMenu(tester);
      await tapInMenu(tester, 'nb-fav-edit');
      await tapInMenu(tester, 'nb-fav-remove-0');
      await closeMenu(tester);
      expect(favPenCount(), 2);
      expect(find.text('Não foi possível sincronizar os favoritos.'), findsOneWidget);
    });
  });

  group('layout', () {
    testWidgets('360 dp com 8 canetas e 8 cores não estoura e a barra rola', (tester) async {
      final prefs = NotebookPrefs(
        pens: [
          for (var i = 0; i < 8; i++) FavoritePen(tool: PenTool.values[i % 4], argb: 0xFF000100 + i, widthIndex: i % 5),
        ],
        colors: [for (var i = 0; i < 8; i++) 0xFF101000 + i],
      ).toMap();
      await pumpNotebookPrefs(tester, FakeSession(), size: const Size(360, 780), prefs: prefs);
      expect(tester.takeException(), isNull);
      expect(favPenCount(), 8);
      expect(favColorCount(), 8);
      // desfazer, refazer e ⋯ ficam sempre visíveis, dentro da tela
      for (final key in ['nb-undo', 'nb-redo', 'nb-more']) {
        final r = tester.getRect(k(key));
        expect(r.left, greaterThanOrEqualTo(0), reason: key);
        expect(r.right, lessThanOrEqualTo(360), reason: key);
      }
      await openMenu(tester);
      await tapInMenu(tester, 'nb-fav-edit');
      expect(tester.takeException(), isNull);
      await closeMenu(tester);
      await drawLine(tester);
    });
  });
}
