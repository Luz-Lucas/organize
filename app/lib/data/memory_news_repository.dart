import '../domain/ids.dart';
import '../domain/news.dart';
import 'news_repository.dart';
import 'repository.dart';

/// Implementação em memória para testes. `highlighted` vem pronto nos itens.
class MemoryNewsRepository implements NewsRepository {
  MemoryNewsRepository({
    List<NewsSource> sources = const [],
    List<NewsItem> items = const [],
    this.validFeeds = const {},
  })  : _sources = [...sources],
        _items = [...items];

  final List<NewsSource> _sources;
  final List<NewsItem> _items;
  final Set<String> validFeeds;
  NewsPrefs _prefs = const NewsPrefs();
  bool failWrites = false;
  int refreshCount = 0;

  void _checkWrite() {
    if (failWrites) throw const RepositoryException('Sem conexão (simulado)');
  }

  @override
  Future<List<NewsItem>> feed({int limit = 50}) async {
    final subscribed = {for (final s in _sources) if (s.subscribed) s.id};
    final list = _items.where((i) => subscribed.contains(i.sourceId)).toList()
      ..sort((a, b) {
        if (a.highlighted != b.highlighted) return a.highlighted ? -1 : 1;
        return b.publishedAt.compareTo(a.publishedAt);
      });
    return list.take(limit).toList();
  }

  @override
  Future<List<NewsSource>> sources() async => List.of(_sources);

  @override
  Future<void> setSubscribed(String sourceId, bool subscribed) async {
    _checkWrite();
    final i = _sources.indexWhere((s) => s.id == sourceId);
    if (i >= 0) _sources[i] = _sources[i].copyWith(subscribed: subscribed);
  }

  @override
  Future<NewsSource> addCustomSource({required String name, required String feedUrl}) async {
    _checkWrite();
    final problem = validateFeedUrl(feedUrl);
    if (problem != null) throw RepositoryException(problem);
    if (!validFeeds.contains(feedUrl.trim())) {
      throw const RepositoryException('Esse endereço não é um feed RSS/Atom.');
    }
    final source = NewsSource(
      id: newId(),
      name: name.trim(),
      section: 'Personalizada',
      feedUrl: feedUrl.trim(),
      custom: true,
      subscribed: true,
    );
    _sources.add(source);
    return source;
  }

  @override
  Future<void> deleteCustomSource(String id) async {
    _checkWrite();
    _sources.removeWhere((s) => s.id == id && s.custom);
  }

  @override
  Future<NewsPrefs> prefs() async => _prefs;

  @override
  Future<void> savePrefs(NewsPrefs prefs) async {
    _checkWrite();
    _prefs = prefs;
  }

  @override
  Future<void> refreshNow() async {
    _checkWrite();
    refreshCount++;
  }
}
