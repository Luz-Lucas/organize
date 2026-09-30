import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_news_repository.dart';
import 'package:organizacional/data/repository.dart';
import 'package:organizacional/domain/news.dart';

void main() {
  final t = DateTime(2026, 9, 28, 10);
  NewsItem item(String id, String sourceId, {bool highlighted = false, int hoursAgo = 1}) => NewsItem(
        id: id,
        sourceId: sourceId,
        sourceName: sourceId,
        title: id,
        url: 'https://x/$id',
        publishedAt: t.subtract(Duration(hours: hoursAgo)),
        highlighted: highlighted,
      );

  test('feed mostra só fontes assinadas, destaques primeiro', () async {
    final repo = MemoryNewsRepository(
      sources: const [
        NewsSource(id: 'g1', name: 'G1', section: 'Principais', feedUrl: 'https://g1', subscribed: true),
        NewsSource(id: 'folha', name: 'Folha', section: 'Poder', feedUrl: 'https://folha'),
      ],
      items: [
        item('recente', 'g1', hoursAgo: 1),
        item('destaque', 'g1', highlighted: true, hoursAgo: 5),
        item('nao-assinada', 'folha'),
      ],
    );
    expect((await repo.feed()).map((i) => i.id), ['destaque', 'recente']);
    await repo.setSubscribed('folha', true);
    expect((await repo.feed()).length, 3);
  });

  test('feed próprio: URL inválida, não-feed e sucesso', () async {
    final repo = MemoryNewsRepository(validFeeds: {'https://blog.dev/feed'});
    await expectLater(
      repo.addCustomSource(name: 'Blog', feedUrl: 'blog.dev'),
      throwsA(isA<RepositoryException>()
          .having((e) => e.message, 'message', 'Informe um endereço http(s) válido.')),
    );
    await expectLater(
      repo.addCustomSource(name: 'Site', feedUrl: 'https://g1.globo.com'),
      throwsA(isA<RepositoryException>()
          .having((e) => e.message, 'message', startsWith('Esse endereço não é um feed RSS/Atom'))),
    );
    final added = await repo.addCustomSource(name: 'Blog', feedUrl: 'https://blog.dev/feed');
    expect(added.custom, isTrue);
    expect(added.subscribed, isTrue);
    expect((await repo.sources()).single.name, 'Blog');
  });

  test('preferências salvas voltam iguais; failWrites simula queda', () async {
    final repo = MemoryNewsRepository();
    const prefs = NewsPrefs(keywords: ['IA']);
    await repo.savePrefs(prefs);
    expect(await repo.prefs(), prefs);
    repo.failWrites = true;
    await expectLater(repo.savePrefs(const NewsPrefs()), throwsA(isA<RepositoryException>()));
  });
}
