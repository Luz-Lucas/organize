import 'dart:typed_data';

import 'package:flutter/painting.dart' show ImageProvider, NetworkImage;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/repository.dart';
import '../../domain/ids.dart';
import '../ui/notebook_session.dart' show NotebookImageStore;
import 'notebook_image_purger.dart';

/// Imagens do caderno no bucket privado `notebook-images`.
///
/// Caminho `<user_id>/<note_id>/<uuid>.<ext>` (as policies liberam só o prefixo do
/// dono). O bucket aceita png, jpeg, webp, gif, heic e heif, até 10 MB; as duas
/// regras são conferidas aqui antes de gastar a rede. Apagar imagem só funciona
/// pela API do Storage (nunca por SQL), por isso [delete].
class SupabaseNotebookImageStore implements NotebookImageStore, NotebookImagePurger {
  SupabaseNotebookImageStore(
    this._db, {
    required this.noteId,
    String? Function()? userId,
    DateTime Function()? clock,
  })  : _userId = userId ?? (() => _db.auth.currentUser?.id),
        _clock = clock ?? DateTime.now;

  final SupabaseClient _db;
  final String noteId;
  final String? Function() _userId;
  final DateTime Function() _clock;

  static const bucket = 'notebook-images';
  static const maxBytes = 10 * 1024 * 1024;
  static const _signedFor = Duration(hours: 1);
  static const _renewBefore = Duration(minutes: 10);

  static const _mime = {
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'webp': 'image/webp',
    'gif': 'image/gif',
    'heic': 'image/heic',
    'heif': 'image/heif',
  };

  final _signed = <String, ({String url, DateTime expires})>{};

  Future<T> _guard<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on StorageException catch (e) {
      throw RepositoryException(e.message);
    } on RepositoryException {
      rethrow;
    } catch (e) {
      throw RepositoryException('Falha de conexão: $e');
    }
  }

  @override
  Future<String> upload(Uint8List bytes, String ext) async {
    final clean = ext.trim().toLowerCase().replaceFirst(RegExp(r'^\.'), '');
    final mime = _mime[clean];
    if (mime == null) {
      throw RepositoryException('Formato de imagem não aceito (.$clean). Use png, jpeg, webp, gif, heic ou heif.');
    }
    if (bytes.length > maxBytes) {
      throw const RepositoryException('A imagem passa de 10 MB.');
    }
    final user = _userId();
    if (user == null) throw const RepositoryException('Entre na conta para enviar imagens.');
    final path = '$user/$noteId/${newId()}.$clean';
    return await _guard(() async {
      await _db.storage.from(bucket).uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mime));
      return path;
    });
  }

  @override
  Future<ImageProvider> load(String path) async {
    final cached = _signed[path];
    final now = _clock();
    if (cached != null && now.isBefore(cached.expires.subtract(_renewBefore))) {
      return NetworkImage(cached.url);
    }
    final url = await _guard(() => _db.storage.from(bucket).createSignedUrl(path, _signedFor.inSeconds));
    _signed[path] = (url: url, expires: now.add(_signedFor));
    return NetworkImage(url);
  }

  /// Remove o objeto do Storage (as policies só deixam o dono apagar).
  Future<void> delete(String path) {
    _signed.remove(path);
    return _guard(() async {
      await _db.storage.from(bucket).remove([path]);
    });
  }

  /// Apaga todas as imagens do caderno (`<user>/<nota>/*`).
  @override
  Future<void> purgeAll() async {
    final user = _userId();
    if (user == null) return;
    final folder = '$user/$noteId';
    await _guard(() async {
      final files = await _db.storage.from(bucket).list(path: folder);
      final paths = [for (final f in files) if (f.name.isNotEmpty) '$folder/${f.name}'];
      if (paths.isNotEmpty) await _db.storage.from(bucket).remove(paths);
    });
    _signed.removeWhere((path, _) => path.startsWith('$folder/'));
  }
}
