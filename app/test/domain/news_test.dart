import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/domain/news.dart';

void main() {
  test('parseTerms separa por vírgula, ponto e vírgula e linha, sem duplicatas', () {
    expect(parseTerms(' IA, clima;  Copa do   Mundo\nia , ,'), ['IA', 'clima', 'Copa do Mundo']);
    expect(parseTerms('   '), isEmpty);
  });

  test('timeAgo', () {
    final now = DateTime(2026, 9, 28, 12);
    expect(timeAgo(now.add(const Duration(minutes: 5)), now), 'agora');
    expect(timeAgo(now.subtract(const Duration(seconds: 30)), now), 'agora');
    expect(timeAgo(now.subtract(const Duration(minutes: 7)), now), 'há 7 min');
    expect(timeAgo(now.subtract(const Duration(hours: 3)), now), 'há 3 h');
    expect(timeAgo(now.subtract(const Duration(hours: 30)), now), 'ontem');
    expect(timeAgo(now.subtract(const Duration(days: 4)), now), 'há 4 dias');
  });

  test('validateFeedUrl', () {
    expect(validateFeedUrl('https://blog.dev/feed'), isNull);
    expect(validateFeedUrl('  http://a.dev/rss.xml '), isNull);
    expect(validateFeedUrl('blog.dev/feed'), 'Informe um endereço http(s) válido.');
    expect(validateFeedUrl('ftp://a.dev/x'), 'Informe um endereço http(s) válido.');
  });

  test('NewsItem.fromMap lê a linha do news_feed', () {
    final item = NewsItem.fromMap({
      'id': 'i1',
      'source_id': 's1',
      'source_name': 'G1',
      'title': 'Manchete',
      'summary': null,
      'url': 'https://g1/x',
      'image_url': null,
      'published_at': '2026-09-28T13:00:00+00:00',
      'highlighted': true,
    });
    expect(item.summary, '');
    expect(item.highlighted, isTrue);
    expect(item.publishedAt.toUtc(), DateTime.utc(2026, 9, 28, 13));
  });

  test('NewsPrefs ida e volta', () {
    const prefs = NewsPrefs(keywords: ['IA'], blocked: ['BBB'], maxAgeHours: 24, briefingCount: 5);
    expect(NewsPrefs.fromMap(prefs.toMap()), prefs);
  });
}
