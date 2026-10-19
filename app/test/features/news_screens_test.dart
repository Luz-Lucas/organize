import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_news_repository.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/news.dart';

import '../helpers.dart';

final _now = DateTime(2026, 9, 28, 10);

MemoryNewsRepository _news() => MemoryNewsRepository(
      sources: const [
        NewsSource(id: 'g1', name: 'G1', section: 'Principais', feedUrl: 'https://g1', subscribed: true),
        NewsSource(id: 'folha', name: 'Folha de S.Paulo', section: 'Poder', feedUrl: 'https://folha'),
      ],
      items: [
        NewsItem(
          id: 'n1',
          sourceId: 'g1',
          sourceName: 'G1',
          title: 'Chuva forte em BH',
          url: 'https://g1/chuva',
          publishedAt: _now.subtract(const Duration(hours: 2)),
        ),
        NewsItem(
          id: 'n2',
          sourceId: 'g1',
          sourceName: 'G1',
          title: 'Nova IA brasileira',
          summary: 'Pesquisadores apresentam modelo.',
          url: 'https://g1/ia',
          publishedAt: _now.subtract(const Duration(hours: 5)),
          highlighted: true,
        ),
      ],
      validFeeds: {'https://blog.dev/feed'},
    );

void main() {
  testWidgets('lista notícias com destaque primeiro e abre o link', (tester) async {
    final opened = <Uri>[];
    await pumpApp(tester, MemoryRepository(),
        location: '/noticias', now: _now, news: _news(), openLink: (u) async {
          opened.add(u);
          return true;
        });
    final ia = tester.getTopLeft(find.text('Nova IA brasileira'));
    final chuva = tester.getTopLeft(find.text('Chuva forte em BH'));
    expect(ia.dy, lessThan(chuva.dy));
    expect(find.byIcon(Icons.star), findsOneWidget);
    expect(find.textContaining('G1 · há 2 h'), findsOneWidget);
    await tester.tap(find.text('Chuva forte em BH'));
    await tester.pump();
    expect(opened, [Uri.parse('https://g1/chuva')]);
  });

  testWidgets('sem notícias mostra atalho para escolher fontes', (tester) async {
    await pumpApp(tester, MemoryRepository(), location: '/noticias');
    await tester.tap(find.text('Escolher fontes'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Fontes e interesses'), findsOneWidget);
  });

  testWidgets('atualizar pede coleta ao servidor', (tester) async {
    final news = _news();
    await pumpApp(tester, MemoryRepository(), location: '/noticias', news: news);
    await tester.tap(find.byKey(const Key('refresh-news')));
    await tester.pumpAndSettle();
    expect(news.refreshCount, 1);
  });

  testWidgets('assinar fonte e salvar interesses', (tester) async {
    final news = _news();
    await pumpApp(tester, MemoryRepository(),
        location: '/noticias/ajustes', news: news, size: const Size(1000, 1600));
    await tester.tap(find.byKey(const ValueKey('source-folha')));
    await tester.pumpAndSettle();
    expect((await news.sources()).firstWhere((s) => s.id == 'folha').subscribed, isTrue);

    await tester.enterText(find.byKey(const Key('news-keywords')), 'IA, UFMG;  clima');
    await tester.enterText(find.byKey(const Key('news-blocked')), 'BBB');
    await tester.tap(find.text('7 dias'));
    await tester.tap(find.byKey(const Key('save-news-prefs')));
    await tester.pumpAndSettle();
    final prefs = await news.prefs();
    expect(prefs.keywords, ['IA', 'UFMG', 'clima']);
    expect(prefs.blocked, ['BBB']);
    expect(prefs.maxAgeHours, 168);
    expect(find.text('Preferências salvas.'), findsOneWidget);
  });

  testWidgets('feed próprio que não é RSS mostra erro e não é salvo', (tester) async {
    final news = _news();
    await pumpApp(tester, MemoryRepository(),
        location: '/noticias/ajustes', news: news, size: const Size(1000, 1600));
    await tester.tap(find.byKey(const Key('add-feed')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('feed-name')), 'G1 site');
    await tester.enterText(find.byKey(const Key('feed-url')), 'https://g1.globo.com');
    await tester.pump(); // reconstrói o diálogo para habilitar \"Adicionar\"
    await tester.tap(find.widgetWithText(FilledButton, 'Adicionar'));
    await tester.pumpAndSettle();
    expect(find.text('Esse endereço não é um feed RSS/Atom.'), findsOneWidget);
    expect((await news.sources()).length, 2);

    await tester.tap(find.byKey(const Key('add-feed')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('feed-name')), 'Meu blog');
    await tester.enterText(find.byKey(const Key('feed-url')), 'https://blog.dev/feed');
    await tester.pump(); // reconstrói o diálogo para habilitar \"Adicionar\"
    await tester.tap(find.widgetWithText(FilledButton, 'Adicionar'));
    await tester.pumpAndSettle();
    expect(find.text('Meu blog'), findsOneWidget);
  });

  testWidgets('remover feed próprio', (tester) async {
    final news = MemoryNewsRepository(
      sources: const [
        NewsSource(
            id: 'c1',
            name: 'Meu blog',
            section: 'Personalizada',
            feedUrl: 'https://blog.dev/feed',
            custom: true,
            subscribed: true),
      ],
    );
    await pumpApp(tester, MemoryRepository(),
        location: '/noticias/ajustes', news: news, size: const Size(1000, 1600));
    expect(find.text('Meu blog'), findsOneWidget);
    await tester.tap(find.byTooltip('Remover feed'));
    await tester.pumpAndSettle();
    expect(find.text('Meu blog'), findsNothing);
    expect(await news.sources(), isEmpty);
  });

  testWidgets('Hoje não mostra mais manchetes; Notícias abre pela barra lateral', (tester) async {
    await pumpApp(tester, MemoryRepository(), now: _now, news: _news());
    expect(find.byKey(const Key('card-news')), findsNothing);
    expect(find.byKey(const Key('open-news')), findsNothing);
    expect(find.text('Nova IA brasileira'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('nav-/noticias')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Notícias'), findsOneWidget);
    expect(find.text('Nova IA brasileira'), findsOneWidget);
  });

  testWidgets('Ajustes tem botão de voltar para Notícias', (tester) async {
    await pumpApp(tester, MemoryRepository(), location: '/noticias', news: _news());
    await tester.tap(find.byKey(const Key('news-settings')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Fontes e interesses'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Notícias'), findsOneWidget);
  });

  testWidgets('Notícias relê o feed a cada vez que se entra vindo de Hoje', (tester) async {
    final news = _news();
    await pumpApp(tester, MemoryRepository(), now: _now, news: news);
    await tester.tap(find.byKey(const ValueKey('nav-/noticias')));
    await tester.pumpAndSettle();
    expect(find.text('Chuva forte em BH'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nav-/')));
    await tester.pumpAndSettle();
    await news.setSubscribed('g1', false); // mudança no servidor
    await tester.tap(find.byKey(const ValueKey('nav-/noticias')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Notícias'), findsOneWidget);
    expect(find.text('Chuva forte em BH'), findsNothing);
  });

  testWidgets('feed duplicado mostra mensagem em português', (tester) async {
    final news = _news();
    await pumpApp(
      tester,
      MemoryRepository(),
      location: '/noticias/ajustes',
      news: news,
      size: const Size(1000, 1600),
    );
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byKey(const Key('add-feed')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('feed-name')), 'Meu blog');
      await tester.enterText(find.byKey(const Key('feed-url')), 'https://blog.dev/feed');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Adicionar'));
      await tester.pumpAndSettle();
    }
    expect(find.text('Esse feed já foi adicionado.'), findsOneWidget);
    expect(find.textContaining('duplicate key'), findsNothing);
  });

  testWidgets('falha ao abrir o link mostra erro', (tester) async {
    await pumpApp(
      tester,
      MemoryRepository(),
      location: '/noticias',
      news: _news(),
      openLink: (_) async => false,
    );
    await tester.tap(find.text('Chuva forte em BH'));
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível abrir o link.'), findsOneWidget);
  });

  testWidgets('link com esquema inválido não é aberto', (tester) async {
    final opened = <Uri>[];
    final news = MemoryNewsRepository(
      sources: const [
        NewsSource(id: 'g1', name: 'G1', section: 'P', feedUrl: 'https://g1', subscribed: true),
      ],
      items: [
        NewsItem(
          id: 'x',
          sourceId: 'g1',
          sourceName: 'G1',
          title: 'Link estranho',
          url: 'javascript:alert(1)',
          publishedAt: _now,
        ),
      ],
    );
    await pumpApp(
      tester,
      MemoryRepository(),
      location: '/noticias',
      now: _now,
      news: news,
      openLink: (u) async {
        opened.add(u);
        return true;
      },
    );
    await tester.tap(find.text('Link estranho'));
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
    expect(find.text('Não foi possível abrir o link.'), findsOneWidget);
  });
}
