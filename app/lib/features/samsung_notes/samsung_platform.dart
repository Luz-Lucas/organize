import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'folder_sync.dart';
import 'samsung_folder.dart';

/// Pacote do app Samsung Notes.
const samsungNotesPackage = 'com.samsung.android.app.notes';

/// O que só o Android sabe fazer (canal `dev.organizacional/samsung_notes`, ver `SamsungNotesChannel.kt`).
abstract interface class SamsungNotesPlatform {
  /// O Samsung Notes está instalado?
  Future<bool> isInstalled();

  /// Abre o app Samsung Notes (não há como abrir uma nota específica).
  Future<bool> open();

  /// "Acesso a todos os arquivos" (`MANAGE_EXTERNAL_STORAGE`) concedido?
  Future<bool> hasAllFilesAccess();

  /// Abre a tela do sistema onde o usuário concede o acesso. Devolve true se abriu.
  Future<bool> requestAllFilesAccess();

  /// Pastas candidatas existentes, na ordem de preferência.
  Future<List<String>> findFolders();

  /// Seletor de pasta do sistema (SAF); persiste a permissão. Null se cancelou.
  Future<SamsungFolder?> pickFolder();

  /// Arquivos de uma pasta escolhida pelo seletor (primeiro nível).
  Future<List<SyncEntry>> listTree(String uri);

  /// Copia um arquivo do seletor para o cache do app e devolve o caminho da cópia.
  Future<String?> copyToCache(String uri);

  /// Nome do aparelho (fabricante e modelo), gravado em `imported_files.device`.
  Future<String?> deviceName();

  /// Pasta do cache do app onde `openFile` aceita arquivos (`cache/samsung_open/`); null se não deu para criá-la.
  Future<String?> openDir();

  /// Abre o arquivo ([path] dentro de [openDir]) no Samsung Notes, que importa a nota como editável. Se o app
  /// não resolver, tenta o seletor do sistema. False se nada abriu o arquivo.
  Future<bool> openFile(String path);
}

/// Sem Android (Linux, testes): nada instalado, nada a buscar.
class NoopSamsungNotesPlatform implements SamsungNotesPlatform {
  const NoopSamsungNotesPlatform();

  @override
  Future<bool> isInstalled() async => false;
  @override
  Future<bool> open() async => false;
  @override
  Future<bool> hasAllFilesAccess() async => true;
  @override
  Future<bool> requestAllFilesAccess() async => false;
  @override
  Future<List<String>> findFolders() async => const [];
  @override
  Future<SamsungFolder?> pickFolder() async => null;
  @override
  Future<List<SyncEntry>> listTree(String uri) async => throw const FolderAccessException('Sem acesso à pasta.');
  @override
  Future<String?> copyToCache(String uri) async => null;
  @override
  Future<String?> deviceName() async => null;
  @override
  Future<String?> openDir() async => null;
  @override
  Future<bool> openFile(String path) async => false;
}

class MethodChannelSamsungNotesPlatform implements SamsungNotesPlatform {
  MethodChannelSamsungNotesPlatform([MethodChannel? channel]) : _channel = channel ?? const MethodChannel('dev.organizacional/samsung_notes');

  final MethodChannel _channel;

  Future<T?> _call<T>(String method, [Object? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<bool> isInstalled() async => (await _call<bool>('isInstalled')) ?? false;

  @override
  Future<bool> open() async => (await _call<bool>('open')) ?? false;

  @override
  Future<bool> hasAllFilesAccess() async => (await _call<bool>('hasAllFilesAccess')) ?? false;

  @override
  Future<bool> requestAllFilesAccess() async => (await _call<bool>('requestAllFilesAccess')) ?? false;

  @override
  Future<List<String>> findFolders() async {
    final raw = await _call<List<Object?>>('findFolders');
    return [for (final p in raw ?? const []) if (p is String) p];
  }

  @override
  Future<SamsungFolder?> pickFolder() async {
    final raw = await _call<Map<Object?, Object?>>('pickFolder');
    return raw == null ? null : SamsungFolder.fromJson(raw);
  }

  @override
  Future<List<SyncEntry>> listTree(String uri) async {
    final List<Object?>? raw;
    try {
      raw = await _channel.invokeMethod<List<Object?>>('listTree', {'uri': uri});
    } on PlatformException {
      throw const FolderAccessException('Sem acesso à pasta. Escolha a pasta de novo em Ajustes.');
    } on MissingPluginException {
      throw const FolderAccessException('Abra o app para sincronizar esta pasta.');
    }
    return [
      for (final m in raw ?? const [])
        if (m is Map && m['id'] is String && m['name'] is String)
          SyncEntry(
            id: m['id'] as String,
            name: m['name'] as String,
            size: (m['size'] as num?)?.toInt() ?? 0,
            modified: DateTime.fromMillisecondsSinceEpoch((m['modified'] as num?)?.toInt() ?? 0),
          ),
    ];
  }

  @override
  Future<String?> copyToCache(String uri) => _call<String>('copyToCache', {'uri': uri});

  @override
  Future<String?> deviceName() => _call<String>('deviceName');

  @override
  Future<String?> openDir() => _call<String>('openDir');

  @override
  Future<bool> openFile(String path) async => (await _call<bool>('openFile', {'path': path})) ?? false;
}

final samsungNotesPlatformProvider = Provider<SamsungNotesPlatform>((ref) => const NoopSamsungNotesPlatform());

/// O Samsung Notes está instalado neste aparelho? (só Android; no resto, sempre false)
final samsungNotesInstalledProvider = FutureProvider<bool>((ref) => ref.watch(samsungNotesPlatformProvider).isInstalled());
