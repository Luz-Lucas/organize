import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/news.dart';
import 'news_repository.dart';
import 'repository.dart';

class SupabaseNewsRepository implements NewsRepository {
  SupabaseNewsRepository(this._db);

  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on PostgrestException catch (e) {
      throw RepositoryException(e.message, duplicate: e.code == '23505');
    } on FunctionException catch (e) {
      throw RepositoryException('Falha ao chamar o servidor (${e.status}).');
    } on RepositoryException {
      rethrow;
    } catch (e) {
      throw RepositoryException('Falha de conexão: $e');
    }
  }

  @override
  Future<List<NewsItem>> feed({int limit = 50}) => _guard(() async {
        final rows = await _db.rpc('news_feed', params: {'p_limit': limit}) as List<dynamic>;
        return rows.map((r) => NewsItem.fromMap(r as Map<String, dynamic>)).toList();
      });

  @override
  Future<List<NewsSource>> sources() => _guard(() async {
        final rows = await _db
            .from('news_sources')
            .select('id, name, section, feed_url, user_id')
            .order('name')
            .order('section');
        final subs = await _db.from('news_subscriptions').select('source_id');
        final subscribed = {for (final s in subs) s['source_id'] as String};
        return [
          for (final r in rows)
            NewsSource(
              id: r['id'] as String,
              name: r['name'] as String,
              section: r['section'] as String,
              feedUrl: r['feed_url'] as String,
              custom: r['user_id'] != null,
              subscribed: subscribed.contains(r['id']),
            ),
        ];
      });

  @override
  Future<void> setSubscribed(String sourceId, bool subscribed) => _guard(() async {
        if (subscribed) {
          await _db
              .from('news_subscriptions')
              .upsert({'source_id': sourceId}, onConflict: 'user_id,source_id', ignoreDuplicates: true);
        } else {
          await _db.from('news_subscriptions').delete().eq('source_id', sourceId);
        }
      });

  @override
  Future<NewsSource> addCustomSource({required String name, required String feedUrl}) =>
      _guard(() async {
        final problem = validateFeedUrl(feedUrl);
        if (problem != null) throw RepositoryException(problem);
        final url = feedUrl.trim();
        final res = await _db.functions.invoke('news-fetch', body: {'validate': url});
        final data = (res.data as Map).cast<String, dynamic>();
        if (data['ok'] != true) {
          throw RepositoryException('Esse endereço não é um feed RSS/Atom (${data['error']}).');
        }
        final row = await _db
            .from('news_sources')
            .insert({
              'user_id': _db.auth.currentUser!.id,
              'name': name.trim(),
              'section': 'Personalizada',
              'feed_url': url,
            })
            .select()
            .single();
        await _db.from('news_subscriptions').insert({'source_id': row['id']});
        return NewsSource(
          id: row['id'] as String,
          name: row['name'] as String,
          section: 'Personalizada',
          feedUrl: url,
          custom: true,
          subscribed: true,
        );
      });

  @override
  Future<void> deleteCustomSource(String id) =>
      _guard(() async => await _db.from('news_sources').delete().eq('id', id));

  @override
  Future<NewsPrefs> prefs() => _guard(() async {
        final row = await _db.from('news_prefs').select().maybeSingle();
        return row == null ? const NewsPrefs() : NewsPrefs.fromMap(row);
      });

  @override
  Future<void> savePrefs(NewsPrefs prefs) =>
      _guard(() async => await _db.from('news_prefs').upsert(prefs.toMap()));

  @override
  Future<void> refreshNow() =>
      _guard(() async => await _db.functions.invoke('news-fetch', body: const {}));
}
