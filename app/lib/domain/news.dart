import 'package:flutter/foundation.dart';

import 'json.dart';

class NewsItem {
  const NewsItem({
    required this.id,
    this.sourceId = '',
    required this.sourceName,
    required this.title,
    this.summary = '',
    required this.url,
    this.imageUrl,
    required this.publishedAt,
    this.highlighted = false,
  });

  final String id;
  final String sourceId;
  final String sourceName;
  final String title;
  final String summary;
  final String url;
  final String? imageUrl;
  final DateTime publishedAt;
  final bool highlighted;

  factory NewsItem.fromMap(Map<String, dynamic> m) => NewsItem(
        id: m['id'] as String,
        sourceId: (m['source_id'] as String?) ?? '',
        sourceName: m['source_name'] as String,
        title: m['title'] as String,
        summary: (m['summary'] as String?) ?? '',
        url: m['url'] as String,
        imageUrl: m['image_url'] as String?,
        publishedAt: parseDate(m['published_at'])!,
        highlighted: (m['highlighted'] as bool?) ?? false,
      );
}

class NewsSource {
  const NewsSource({
    required this.id,
    required this.name,
    required this.section,
    required this.feedUrl,
    this.custom = false,
    this.subscribed = false,
  });

  final String id;
  final String name;
  final String section;
  final String feedUrl;
  final bool custom;
  final bool subscribed;

  NewsSource copyWith({bool? subscribed}) => NewsSource(
        id: id,
        name: name,
        section: section,
        feedUrl: feedUrl,
        custom: custom,
        subscribed: subscribed ?? this.subscribed,
      );
}

class NewsPrefs {
  const NewsPrefs({
    this.keywords = const [],
    this.blocked = const [],
    this.maxAgeHours = 48,
    this.briefingCount = 3,
  });

  final List<String> keywords;
  final List<String> blocked;
  final int maxAgeHours;
  final int briefingCount;

  factory NewsPrefs.fromMap(Map<String, dynamic> m) => NewsPrefs(
        keywords: ((m['keywords'] as List?) ?? const []).cast<String>(),
        blocked: ((m['blocked'] as List?) ?? const []).cast<String>(),
        maxAgeHours: (m['max_age_hours'] as num?)?.toInt() ?? 48,
        briefingCount: (m['briefing_count'] as num?)?.toInt() ?? 3,
      );

  Map<String, dynamic> toMap() => {
        'keywords': keywords,
        'blocked': blocked,
        'max_age_hours': maxAgeHours,
        'briefing_count': briefingCount,
      };

  @override
  bool operator ==(Object other) =>
      other is NewsPrefs &&
      listEquals(other.keywords, keywords) &&
      listEquals(other.blocked, blocked) &&
      other.maxAgeHours == maxAgeHours &&
      other.briefingCount == briefingCount;

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(keywords), Object.hashAll(blocked), maxAgeHours, briefingCount);
}

List<String> parseTerms(String input) {
  final seen = <String>{};
  final out = <String>[];
  for (final raw in input.split(RegExp(r'[,;\n]'))) {
    final term = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (term.isEmpty) continue;
    if (seen.add(term.toLowerCase())) out.add(term);
  }
  return out;
}

String timeAgo(DateTime t, DateTime now) {
  final d = now.difference(t);
  if (d.inMinutes < 1) return 'agora';
  if (d.inMinutes < 60) return 'há ${d.inMinutes} min';
  if (d.inHours < 24) return 'há ${d.inHours} h';
  if (d.inDays == 1) return 'ontem';
  return 'há ${d.inDays} dias';
}

String? validateFeedUrl(String input) {
  final uri = Uri.tryParse(input.trim());
  final ok = uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
  return ok ? null : 'Informe um endereço http(s) válido.';
}
