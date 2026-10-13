import 'dart:async';
import 'dart:typed_data';

import '../domain/drive.dart';
import '../domain/ids.dart';
import 'drive_repository.dart';
import 'repository.dart';

class UploadCall {
  UploadCall(this.parentId, this.name, this.mimeType, this.size, [this.appProperties]);

  final String parentId;
  final String name;
  final String mimeType;
  final int size;
  final Map<String, String>? appProperties;
}

class _Node {
  _Node(this.item, this.parentId);

  DriveItem item;
  String? parentId;
  bool trashed = false;
  Map<String, String>? appProperties;
  Uint8List bytes = Uint8List(0);
  final List<DrivePermission> permissions = [
    const DrivePermission(id: 'owner', email: 'sua-conta@exemplo.com', role: 'owner', type: 'user'),
  ];
}

/// Implementação em memória usada nos testes.
class MemoryDriveRepository implements DriveRepository {
  MemoryDriveRepository({DriveState? state}) : _state = state ?? const DriveState(status: DriveStatus.ok, rootFolderId: 'org-root') {
    _nodes['my-drive'] = _Node(const DriveItem(id: 'my-drive', name: 'Meu Drive', mimeType: driveFolderMime, isFolder: true), null);
    _nodes['org-root'] =
        _Node(const DriveItem(id: 'org-root', name: 'Organizacional', mimeType: driveFolderMime, isFolder: true), 'my-drive');
  }

  DriveState? _state;
  final _nodes = <String, _Node>{};
  final _changes = StreamController<void>.broadcast(sync: true);

  bool failActions = false;

  /// Faz as chamadas falharem como se o acesso tivesse expirado.
  bool authRequired = false;
  int disconnectCalls = 0;
  String? lastConnectEmail;
  Uri connectUri = Uri.parse('https://accounts.google.com/o/oauth2/v2/auth?drive=1');
  final uploads = <UploadCall>[];

  /// Ids pedidos a `download`, na ordem.
  final downloads = <String>[];

  /// Simula o teto do servidor: list/search devolvem no máximo isso e marcam `truncated`.
  int? itemLimit;

  String get rootFolderId => 'org-root';

  void setState(DriveState? state) {
    _state = state;
    _changes.add(null);
  }

  DriveItem addFolder(String name, String parentId) {
    final item = DriveItem(id: newId(), name: name, mimeType: driveFolderMime, isFolder: true);
    _nodes[item.id] = _Node(item, parentId);
    return item;
  }

  DriveItem addFile(String name, String parentId, {String mimeType = 'application/pdf', int size = 1024, List<int>? bytes, String? id}) {
    final item = DriveItem(
      id: id ?? newId(),
      name: name,
      mimeType: mimeType,
      size: bytes?.length ?? size,
      webViewLink: 'https://drive.example/file/${_nodes.length}',
    );
    _nodes[item.id] = _Node(item, parentId);
    if (bytes != null) _nodes[item.id]!.bytes = Uint8List.fromList(bytes);
    return item;
  }

  @override
  Stream<DriveState?> watchState() {
    StreamSubscription<void>? sub;
    late final StreamController<DriveState?> controller;
    controller = StreamController<DriveState?>(
      onListen: () {
        controller.add(_state);
        sub = _changes.stream.listen((_) => controller.add(_state));
      },
      onCancel: () {
        sub?.cancel();
        controller.close();
      },
    );
    return controller.stream;
  }

  void _check() {
    if (authRequired) throw const DriveException('O acesso ao Google Drive expirou. Reconecte em Ajustes.', code: 'auth_required');
    if (failActions) throw const RepositoryException('Sem conexão (simulado)');
  }

  _Node _node(String id) {
    final n = _nodes[id == 'root' ? 'my-drive' : id];
    if (n == null) throw const DriveException('Item não encontrado no Google Drive.', code: 'not_found');
    return n;
  }

  @override
  Future<Uri> connectUrl({String? email}) async {
    if (failActions) throw const RepositoryException('Sem conexão (simulado)');
    lastConnectEmail = email;
    return connectUri;
  }

  @override
  Future<void> disconnect() async {
    if (failActions) throw const RepositoryException('Sem conexão (simulado)');
    disconnectCalls++;
    setState(const DriveState());
  }

  @override
  Future<DriveListing> list({String? folderId}) async {
    _check();
    final folder = _node(folderId ?? rootFolderId);
    final items = [
      for (final n in _nodes.values)
        if (!n.trashed && n.parentId == folder.item.id) n.item,
    ]..sort((a, b) {
        if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    final limit = itemLimit;
    final cut = limit != null && items.length > limit;
    return DriveListing(
      folder: DriveFolder(id: folder.item.id, name: folder.item.name, parents: [if (folder.parentId != null) folder.parentId!]),
      items: cut ? items.sublist(0, limit) : items,
      truncated: cut,
    );
  }

  @override
  Future<DriveSearchResult> search(String query) async {
    _check();
    final q = query.toLowerCase();
    final found = [
      for (final n in _nodes.values)
        if (!n.trashed && n.parentId != null && n.item.name.toLowerCase().contains(q)) n.item,
    ];
    final limit = itemLimit;
    final cut = limit != null && found.length > limit;
    return DriveSearchResult(items: cut ? found.sublist(0, limit) : found, truncated: cut);
  }

  @override
  Future<DriveItem> createFolder(String parentId, String name) async {
    _check();
    _node(parentId);
    return addFolder(name, _node(parentId).item.id);
  }

  @override
  Future<DriveItem> ensureFolder(String parentId, String name) async {
    _check();
    final parent = _node(parentId).item.id;
    for (final n in _nodes.values) {
      if (!n.trashed && n.parentId == parent && n.item.isFolder && n.item.name == name) return n.item;
    }
    return addFolder(name, parent);
  }

  @override
  Future<String> ensurePath(List<String> path) async {
    _check();
    var parent = 'my-drive';
    for (final name in path) {
      parent = (await ensureFolder(parent, name)).id;
    }
    return parent;
  }

  @override
  Future<DriveItem?> findBySha256(String sha256) async {
    _check();
    for (final n in _nodes.values) {
      if (!n.trashed && n.appProperties?['sha256'] == sha256) return n.item;
    }
    return null;
  }

  @override
  Future<Uint8List> download(String id) async {
    _check();
    final n = _node(id);
    if (n.trashed || n.item.isFolder) throw const DriveException('Item não encontrado no Google Drive.', code: 'not_found');
    downloads.add(id);
    return n.bytes;
  }

  @override
  Future<void> rename(String id, String name) async {
    _check();
    final n = _node(id);
    n.item = n.item.copyWith(name: name);
  }

  @override
  Future<void> move(String id, String toFolderId) async {
    _check();
    _node(id).parentId = _node(toFolderId).item.id;
  }

  @override
  Future<void> trash(String id) async {
    _check();
    _node(id).trashed = true;
  }

  @override
  Future<void> restore(String id) async {
    _check();
    _node(id).trashed = false;
  }

  @override
  Future<void> share(String id, String email, DriveRole role, {bool notify = false}) async {
    _check();
    final n = _node(id);
    n.permissions.add(DrivePermission(id: newId(), email: email, role: role.wire, type: 'user'));
    n.item = n.item.copyWith(shared: true);
  }

  @override
  Future<String?> setLinkSharing(String id, bool enabled) async {
    _check();
    final n = _node(id);
    n.permissions.removeWhere((p) => p.isAnyone);
    if (enabled) n.permissions.add(DrivePermission(id: newId(), role: 'reader', type: 'anyone'));
    return n.item.webViewLink;
  }

  @override
  Future<List<DrivePermission>> permissions(String id) async {
    _check();
    return List.of(_node(id).permissions);
  }

  @override
  Future<void> unshare(String id, String permissionId) async {
    _check();
    _node(id).permissions.removeWhere((p) => p.id == permissionId);
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
    _check();
    var sent = 0;
    final received = BytesBuilder(copy: false);
    await for (final chunk in data) {
      sent += chunk.length;
      received.add(chunk);
      onProgress?.call(sent, size);
    }
    uploads.add(UploadCall(parentId, name, mimeType, size, appProperties));
    final item = addFile(name, _node(parentId).item.id, mimeType: mimeType, size: size);
    _nodes[item.id]!.appProperties = appProperties;
    _nodes[item.id]!.bytes = received.takeBytes();
    return UploadedFile(id: item.id, name: name, webViewLink: item.webViewLink);
  }
}
