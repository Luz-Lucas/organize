import '../domain/news.dart';

abstract interface class NewsRepository {
  Future<List<NewsItem>> feed({int limit = 50});
  Future<List<NewsSource>> sources();
  Future<void> setSubscribed(String sourceId, bool subscribed);

  /// Valida o feed antes de salvar; lança RepositoryException com mensagem para o usuário.
  Future<NewsSource> addCustomSource({required String name, required String feedUrl});
  Future<void> deleteCustomSource(String id);
  Future<NewsPrefs> prefs();
  Future<void> savePrefs(NewsPrefs prefs);

  /// Pede ao servidor uma coleta imediata.
  Future<void> refreshNow();
}
