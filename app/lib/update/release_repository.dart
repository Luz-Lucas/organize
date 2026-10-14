import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/repository.dart';
import 'app_release.dart';

/// Onde o app descobre e baixa as versões publicadas.
abstract interface class ReleaseRepository {
  /// A release mais nova (maior `build`) de [platform], ou null se não há nenhuma.
  Future<AppRelease?> latest(String platform);

  /// URL assinada, de curta duração, para baixar o arquivo em [storagePath].
  Future<Uri> signedUrl(String storagePath);
}

/// Tabela `app_releases` + bucket privado `app-releases` (o app autenticado só lê).
class SupabaseReleaseRepository implements ReleaseRepository {
  SupabaseReleaseRepository(this._db);

  final SupabaseClient _db;

  static const bucket = 'app-releases';

  /// Validade curta: o download começa logo em seguida.
  static const signedFor = Duration(minutes: 5);

  Future<T> _guard<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on PostgrestException catch (e) {
      throw RepositoryException(e.message);
    } on StorageException catch (e) {
      throw RepositoryException(e.message);
    } on RepositoryException {
      rethrow;
    } catch (e) {
      throw RepositoryException('Falha de conexão: $e');
    }
  }

  @override
  Future<AppRelease?> latest(String platform) => _guard(() async {
        final rows = await _db
            .from('app_releases')
            .select()
            .eq('platform', platform)
            .order('build', ascending: false)
            .limit(1);
        if (rows.isEmpty) return null;
        return AppRelease.fromJson(rows.first);
      });

  @override
  Future<Uri> signedUrl(String storagePath) => _guard(() async {
        final url = await _db.storage.from(bucket).createSignedUrl(storagePath, signedFor.inSeconds);
        return Uri.parse(url);
      });
}

/// Em memória (padrão dos testes e de plataformas sem atualização): [releases] por plataforma.
class MemoryReleaseRepository implements ReleaseRepository {
  MemoryReleaseRepository([List<AppRelease> releases = const []]) : releases = [...releases];

  final List<AppRelease> releases;

  /// Se definido, `latest` falha com isto.
  Object? latestError;
  int latestCalls = 0;

  @override
  Future<AppRelease?> latest(String platform) async {
    latestCalls++;
    final error = latestError;
    if (error != null) throw error;
    AppRelease? best;
    for (final r in releases) {
      if (r.platform == platform && (best == null || r.build > best.build)) best = r;
    }
    return best;
  }

  @override
  Future<Uri> signedUrl(String storagePath) async => Uri.parse('https://exemplo.test/assinada/$storagePath');
}
