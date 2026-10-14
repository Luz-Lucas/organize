import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// O que só o sistema sabe fazer com os arquivos baixados do Drive.
abstract interface class FilesPlatform {
  /// Abrir arquivos baixados é possível neste aparelho? (Android e Linux)
  bool get supported;

  /// Pasta persistente do cache (`drive_cache`); null se não deu para obtê-la.
  Future<String?> cacheRoot();

  /// Abre [path] no app padrão do sistema para [mime] (ou no seletor do Android, se houver mais de um).
  /// False se nada abriu o arquivo ou o caminho não é aceitável.
  Future<bool> openFile(String path, String mime);
}

/// Sem suporte (testes, web, iOS...): nada a abrir.
class NoopFilesPlatform implements FilesPlatform {
  const NoopFilesPlatform();

  @override
  bool get supported => false;
  @override
  Future<String?> cacheRoot() async => null;
  @override
  Future<bool> openFile(String path, String mime) async => false;
}

/// Android: canal `dev.organizacional/files` (ver `FilesChannel.kt`).
class MethodChannelFilesPlatform implements FilesPlatform {
  MethodChannelFilesPlatform([MethodChannel? channel]) : _channel = channel ?? const MethodChannel('dev.organizacional/files');

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
  bool get supported => true;

  @override
  Future<String?> cacheRoot() => _call<String>('cacheRoot');

  @override
  Future<bool> openFile(String path, String mime) async =>
      (await _call<bool>('openFile', {'path': path, 'mime': mime})) ?? false;
}

typedef ProcessRun = Future<int> Function(String executable, List<String> arguments);

Future<int> _runProcess(String executable, List<String> arguments) async => (await Process.run(executable, arguments)).exitCode;

/// Linux: `xdg-open` abre o arquivo no app padrão; a pasta segue o padrão XDG de dados do app.
class LinuxFilesPlatform implements FilesPlatform {
  LinuxFilesPlatform({Map<String, String>? env, ProcessRun? run})
      : _env = env ?? Platform.environment,
        _run = run ?? _runProcess;

  final Map<String, String> _env;
  final ProcessRun _run;

  @override
  bool get supported => true;

  @override
  Future<String?> cacheRoot() async {
    final xdg = _env['XDG_DATA_HOME'];
    final home = _env['HOME'];
    final base = (xdg != null && xdg.startsWith('/'))
        ? xdg
        : (home != null && home.startsWith('/') ? '$home/.local/share' : null);
    return base == null ? null : '$base/dev.organizacional.organizacional/drive_cache';
  }

  @override
  Future<bool> openFile(String path, String mime) async {
    // Caminho absoluto sempre: um nome começando com "-" seria lido como opção.
    if (!path.startsWith('/')) return false;
    try {
      return await _run('xdg-open', [path]) == 0;
    } catch (_) {
      return false;
    }
  }
}

/// Quem abre arquivos e guarda o cache neste aparelho (a `main` troca por Android/Linux).
final filesPlatformProvider = Provider<FilesPlatform>((ref) => const NoopFilesPlatform());
