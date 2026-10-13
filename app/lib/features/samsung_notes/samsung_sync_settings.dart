import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../ui/common.dart' show plural;
import 'samsung_folder.dart';

/// Resumo da última rodada, mostrado em Ajustes.
class SamsungSyncLastRun {
  SamsungSyncLastRun({
    required this.at,
    this.uploaded = 0,
    this.skipped = 0,
    this.ignored = 0,
    this.errors = 0,
    this.message,
  });

  final DateTime at;
  final int uploaded;
  final int skipped;
  final int ignored;
  final int errors;

  /// Primeiro erro (ou aviso de reconexão), para mostrar ao usuário.
  final String? message;

  /// Ex.: "12 enviados, 2 ignorados" (+ ", 1 com erro").
  String get text {
    final base = '${plural(uploaded, 'enviado', 'enviados')}, ${plural(ignored, 'ignorado', 'ignorados')}';
    return errors == 0 ? base : '$base, $errors com erro';
  }

  Map<String, dynamic> toJson() => {
        'at': at.toUtc().toIso8601String(),
        'uploaded': uploaded,
        'skipped': skipped,
        'ignored': ignored,
        'errors': errors,
        if (message != null) 'message': message,
      };

  static SamsungSyncLastRun? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final at = raw['at'] is String ? DateTime.tryParse(raw['at'] as String) : null;
    if (at == null) return null;
    int n(String k) => raw[k] is num ? (raw[k] as num).toInt() : 0;
    return SamsungSyncLastRun(
      at: at,
      uploaded: n('uploaded'),
      skipped: n('skipped'),
      ignored: n('ignored'),
      errors: n('errors'),
      message: raw['message'] is String ? raw['message'] as String : null,
    );
  }
}

/// Configuração DESTE aparelho (celular e tablet têm pastas e chaves próprias).
class SamsungSyncSettings {
  const SamsungSyncSettings({this.enabled = false, this.folder, this.lastRun});

  final bool enabled;
  final SamsungFolder? folder;
  final SamsungSyncLastRun? lastRun;
}

abstract interface class SamsungSyncPrefs {
  Future<SamsungSyncSettings> load();
  Future<void> setEnabled(bool enabled);
  Future<void> setFolder(SamsungFolder? folder);
  Future<void> saveLastRun(SamsungSyncLastRun run);
}

class MemorySamsungSyncPrefs implements SamsungSyncPrefs {
  MemorySamsungSyncPrefs([SamsungSyncSettings initial = const SamsungSyncSettings()])
      : _enabled = initial.enabled,
        _folder = initial.folder,
        _lastRun = initial.lastRun;

  bool _enabled;
  SamsungFolder? _folder;
  SamsungSyncLastRun? _lastRun;

  @override
  Future<SamsungSyncSettings> load() async => SamsungSyncSettings(enabled: _enabled, folder: _folder, lastRun: _lastRun);

  @override
  Future<void> setEnabled(bool enabled) async => _enabled = enabled;

  @override
  Future<void> setFolder(SamsungFolder? folder) async => _folder = folder;

  @override
  Future<void> saveLastRun(SamsungSyncLastRun run) async => _lastRun = run;
}

const _kEnabled = 'samsung_sync_enabled';
const _kFolder = 'samsung_sync_folder';
const _kLastRun = 'samsung_sync_last_run';

/// Guarda no `SharedPreferences` do aparelho. Relê do disco a cada `load`, porque a tarefa em segundo
/// plano (outro isolate) também escreve aqui.
class SharedPreferencesSamsungSyncPrefs implements SamsungSyncPrefs {
  Future<SharedPreferences> _prefs({bool reload = false}) async {
    final p = await SharedPreferences.getInstance();
    if (reload) await p.reload();
    return p;
  }

  Object? _json(String? raw) {
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<SamsungSyncSettings> load() async {
    final p = await _prefs(reload: true);
    return SamsungSyncSettings(
      enabled: p.getBool(_kEnabled) ?? false,
      folder: SamsungFolder.fromJson(_json(p.getString(_kFolder))),
      lastRun: SamsungSyncLastRun.fromJson(_json(p.getString(_kLastRun))),
    );
  }

  @override
  Future<void> setEnabled(bool enabled) async => (await _prefs()).setBool(_kEnabled, enabled);

  @override
  Future<void> setFolder(SamsungFolder? folder) async {
    final p = await _prefs();
    if (folder == null) {
      await p.remove(_kFolder);
    } else {
      await p.setString(_kFolder, jsonEncode(folder.toJson()));
    }
  }

  @override
  Future<void> saveLastRun(SamsungSyncLastRun run) async => (await _prefs()).setString(_kLastRun, jsonEncode(run.toJson()));
}
