import 'json.dart';

/// Limite sugerido para envio pelo app; acima disso o app avisa antes de enviar.
const driveWarnUploadBytes = 100 * 1024 * 1024;

const driveFolderMime = 'application/vnd.google-apps.folder';

enum DriveStatus {
  notConnected,
  ok,
  authRequired,
  error;

  static DriveStatus parse(Object? raw) => switch (raw) {
        'ok' => ok,
        'auth_required' => authRequired,
        'error' => error,
        _ => notConnected,
      };
}

/// Situação da conta do Google Drive (uma linha por usuário em `drive_state`).
class DriveState {
  const DriveState({
    this.accountEmail,
    this.status = DriveStatus.notConnected,
    this.rootFolderId,
    this.message,
  });

  final String? accountEmail;
  final DriveStatus status;

  /// Id da pasta "Organizacional" no Meu Drive.
  final String? rootFolderId;
  final String? message;

  bool get connected => status != DriveStatus.notConnected;

  factory DriveState.fromMap(Map<String, dynamic> m) => DriveState(
        accountEmail: m['account_email'] as String?,
        status: DriveStatus.parse(m['status']),
        rootFolderId: m['root_folder_id'] as String?,
        message: m['message'] as String?,
      );
}

class DriveItem {
  const DriveItem({
    required this.id,
    required this.name,
    this.mimeType = '',
    this.isFolder = false,
    this.size,
    this.modifiedTime,
    this.webViewLink,
    this.iconLink,
    this.shared = false,
  });

  final String id;
  final String name;
  final String mimeType;
  final bool isFolder;
  final int? size;
  final DateTime? modifiedTime;
  final String? webViewLink;
  final String? iconLink;
  final bool shared;

  factory DriveItem.fromMap(Map<String, dynamic> m) {
    final mime = (m['mimeType'] as String?) ?? '';
    return DriveItem(
      id: m['id'] as String,
      name: (m['name'] as String?) ?? '',
      mimeType: mime,
      isFolder: (m['isFolder'] as bool?) ?? mime == driveFolderMime,
      size: (m['size'] as num?)?.toInt(),
      modifiedTime: parseDate(m['modifiedTime']),
      webViewLink: m['webViewLink'] as String?,
      iconLink: m['iconLink'] as String?,
      shared: (m['shared'] as bool?) ?? false,
    );
  }

  DriveItem copyWith({String? name, bool? shared}) => DriveItem(
        id: id,
        name: name ?? this.name,
        mimeType: mimeType,
        isFolder: isFolder,
        size: size,
        modifiedTime: modifiedTime,
        webViewLink: webViewLink,
        iconLink: iconLink,
        shared: shared ?? this.shared,
      );
}

class DriveFolder {
  const DriveFolder({required this.id, required this.name, this.parents = const []});

  final String id;
  final String name;
  final List<String> parents;

  factory DriveFolder.fromMap(Map<String, dynamic> m) => DriveFolder(
        id: m['id'] as String,
        name: (m['name'] as String?) ?? '',
        parents: [for (final p in (m['parents'] as List?) ?? const []) p as String],
      );
}

class DriveListing {
  const DriveListing({required this.folder, required this.items, this.truncated = false});

  final DriveFolder folder;
  final List<DriveItem> items;

  /// O servidor cortou a lista no teto (há mais itens no Drive do que os mostrados).
  final bool truncated;
}

/// Resultado de uma busca por nome.
class DriveSearchResult {
  const DriveSearchResult({required this.items, this.truncated = false});

  final List<DriveItem> items;
  final bool truncated;
}

enum DriveRole {
  reader('reader', 'Leitor'),
  commenter('commenter', 'Comentarista'),
  writer('writer', 'Editor');

  const DriveRole(this.wire, this.label);

  final String wire;
  final String label;
}

class DrivePermission {
  const DrivePermission({required this.id, this.email, required this.role, required this.type});

  final String id;
  final String? email;
  final String role;
  final String type;

  bool get isOwner => role == 'owner';
  bool get isAnyone => type == 'anyone';

  String get roleLabel => switch (role) {
        'owner' => 'Dono',
        'writer' => 'Editor',
        'commenter' => 'Comentarista',
        _ => 'Leitor',
      };

  factory DrivePermission.fromMap(Map<String, dynamic> m) => DrivePermission(
        id: m['id'] as String,
        email: m['email'] as String?,
        role: (m['role'] as String?) ?? 'reader',
        type: (m['type'] as String?) ?? 'user',
      );
}

/// Resultado de um envio: o que o Drive devolveu ao fim do upload.
class UploadedFile {
  const UploadedFile({required this.id, required this.name, this.webViewLink});

  final String id;
  final String name;
  final String? webViewLink;
}

/// 2048 -> "2,0 KB"; 5,3 MB; 3,0 GB.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var v = bytes / 1024;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(1).replaceAll('.', ',')} ${units[i]}';
}
