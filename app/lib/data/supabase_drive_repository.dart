import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/drive.dart';
import 'drive_repository.dart';
import 'repository.dart';

typedef DriveInvoke = Future<Map<String, dynamic>> Function(String function, Map<String, dynamic> body);

/// Converte a resposta de erro da Edge Function (`{error, code}`) em [DriveException].
DriveException driveErrorFrom(int status, Object? details) {
  if (status == 0) return const DriveException('Falha de conexão. Verifique a internet e tente de novo.');
  if (details is Map && details['error'] is String) {
    return DriveException(details['error'] as String, code: details['code'] as String?);
  }
  return DriveException('Falha ao chamar o servidor ($status).');
}

/// A sessão de upload só vale em `https://www.googleapis.com/...` (sem usuário, senha ou porta).
bool isGoogleUploadUri(Uri uri) =>
    uri.scheme == 'https' && uri.host == 'www.googleapis.com' && uri.userInfo.isEmpty && !uri.hasPort;

/// Lê `drive_state` (só o servidor escreve) e fala com as funções `drive` e `gmail-connect`.
/// O token do Google nunca chega ao app: o upload usa uma URL de sessão criada no servidor.
class SupabaseDriveRepository implements DriveRepository {
  SupabaseDriveRepository(SupabaseClient db, {http.Client? httpClient})
      : _db = db,
        _http = httpClient ?? http.Client(),
        _invoke = _supabaseInvoke(db);

  /// Para testes: sem cliente Supabase.
  SupabaseDriveRepository.test({required this._invoke, http.Client? httpClient})
      : _db = null,
        _http = httpClient ?? http.Client();

  static DriveInvoke _supabaseInvoke(SupabaseClient db) => (fn, body) async {
        try {
          final res = await db.functions.invoke(fn, body: body);
          final data = res.data;
          return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
        } on FunctionException catch (e) {
          throw driveErrorFrom(e.status, e.details);
        }
      };

  final SupabaseClient? _db;
  final http.Client _http;
  final DriveInvoke _invoke;

  Future<T> _guard<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on RepositoryException {
      rethrow;
    } on PostgrestException catch (e) {
      throw RepositoryException(e.message);
    } catch (e) {
      // Sem `$e`: a exceção pode carregar a URL da sessão de upload (com upload_id) ou outros detalhes.
      throw const RepositoryException('Falha de conexão. Verifique a internet e tente de novo.');
    }
  }

  Future<Map<String, dynamic>> _call(String action, [Map<String, dynamic> params = const {}]) =>
      _guard(() => _invoke('drive', {'action': action, ...params}));

  @override
  Stream<DriveState?> watchState() => _db!
      .from('drive_state')
      .stream(primaryKey: ['user_id']).map((rows) => rows.isEmpty ? null : DriveState.fromMap(rows.first));

  @override
  Future<Uri> connectUrl({String? email}) => _guard(() async {
        final res = await _invoke('gmail-connect', {'provider': 'drive', 'email': ?email});
        final url = res['url'];
        final uri = url is String ? Uri.tryParse(url) : null;
        if (uri == null || uri.scheme != 'https') {
          throw const RepositoryException('Resposta inesperada do servidor.');
        }
        return uri;
      });

  @override
  Future<void> disconnect() async {
    await _call('disconnect');
  }

  @override
  Future<DriveListing> list({String? folderId}) async {
    final res = await _call('list', {'folderId': ?folderId});
    return DriveListing(
      folder: DriveFolder.fromMap(Map<String, dynamic>.from(res['folder'] as Map)),
      items: _items(res['items']),
      truncated: res['truncated'] == true,
    );
  }

  List<DriveItem> _items(Object? raw) =>
      [for (final m in (raw as List?) ?? const []) DriveItem.fromMap(Map<String, dynamic>.from(m as Map))];

  @override
  Future<DriveSearchResult> search(String query) async {
    final res = await _call('search', {'q': query});
    return DriveSearchResult(items: _items(res['items']), truncated: res['truncated'] == true);
  }

  DriveItem _item(Map<String, dynamic> res) => DriveItem.fromMap(Map<String, dynamic>.from(res['item'] as Map));

  @override
  Future<DriveItem> createFolder(String parentId, String name) async =>
      _item(await _call('create_folder', {'parentId': parentId, 'name': name}));

  @override
  Future<DriveItem> ensureFolder(String parentId, String name) async =>
      _item(await _call('ensure_folder', {'parentId': parentId, 'name': name}));

  @override
  Future<void> rename(String id, String name) async {
    await _call('rename', {'id': id, 'name': name});
  }

  @override
  Future<void> move(String id, String toFolderId) async {
    await _call('move', {'id': id, 'toFolderId': toFolderId});
  }

  @override
  Future<void> trash(String id) async {
    await _call('trash', {'id': id});
  }

  @override
  Future<void> restore(String id) async {
    await _call('restore', {'id': id});
  }

  @override
  Future<void> share(String id, String email, DriveRole role, {bool notify = false}) async {
    await _call('share', {'id': id, 'email': email, 'role': role.wire, if (notify) 'notify': true});
  }

  @override
  Future<String?> setLinkSharing(String id, bool enabled) async =>
      (await _call('share_link', {'id': id, 'enabled': enabled}))['webViewLink'] as String?;

  @override
  Future<List<DrivePermission>> permissions(String id) async {
    final res = await _call('permissions', {'id': id});
    return [
      for (final m in (res['permissions'] as List?) ?? const []) DrivePermission.fromMap(Map<String, dynamic>.from(m as Map)),
    ];
  }

  @override
  Future<void> unshare(String id, String permissionId) async {
    await _call('unshare', {'id': id, 'permissionId': permissionId});
  }

  @override
  Future<String> ensurePath(List<String> path) async {
    final res = await _call('ensure_path', {'path': path});
    final id = res['folderId'];
    if (id is! String || id.isEmpty) throw const RepositoryException('Resposta inesperada do servidor.');
    return id;
  }

  @override
  Future<DriveItem?> findBySha256(String sha256) async {
    final file = (await _call('find_by_sha256', {'sha256': sha256}))['file'];
    return file is Map ? DriveItem.fromMap(Map<String, dynamic>.from(file)) : null;
  }

  @override
  Future<UploadedFile> upload({
    required String parentId,
    required String name,
    required String mimeType,
    required int size,
    required Stream<List<int>> data,
    void Function(int sent, int total)? onProgress,
    Map<String, String>? appProperties,
  }) async {
    final session = await _call('upload_session', {
      'parentId': parentId,
      'name': name,
      'mimeType': mimeType,
      'size': size,
      if (appProperties != null && appProperties.isNotEmpty) 'appProperties': appProperties,
    });
    final uri = Uri.tryParse((session['uploadUrl'] as String?) ?? '');
    if (uri == null || !isGoogleUploadUri(uri)) {
      throw const RepositoryException('Resposta inesperada do servidor.');
    }
    return _guard(() async {
      final req = http.StreamedRequest('PUT', uri)
        ..contentLength = size
        ..headers['Content-Type'] = mimeType;
      var sent = 0;
      var tooMuch = false;
      Object? pumpError;
      // Alimenta o corpo enquanto o envio acontece (não carrega o arquivo inteiro na memória).
      final pump = () async {
        try {
          await for (final chunk in data) {
            if (sent + chunk.length > size) {
              tooMuch = true;
              break;
            }
            req.sink.add(chunk);
            sent += chunk.length;
            onProgress?.call(sent, size);
          }
        } catch (e) {
          pumpError = e; // a leitura do arquivo falhou; o envio abaixo termina com erro
        } finally {
          await req.sink.close();
        }
      }();
      final res = await http.Response.fromStream(await _http.send(req));
      await pump;
      if (pumpError != null) throw const RepositoryException('Não foi possível ler o arquivo.');
      if (tooMuch || sent != size) {
        throw const RepositoryException('O arquivo mudou durante o envio. Tente de novo.');
      }
      if (res.statusCode != 200 && res.statusCode != 201) {
        throw RepositoryException('Falha ao enviar o arquivo (${res.statusCode}).');
      }
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      if (body is! Map || body['id'] is! String) {
        throw const RepositoryException('Resposta inesperada do Google Drive.');
      }
      return UploadedFile(
        id: body['id'] as String,
        name: (body['name'] as String?) ?? name,
        webViewLink: body['webViewLink'] as String?,
      );
    });
  }
}
