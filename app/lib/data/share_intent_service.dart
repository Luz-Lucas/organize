import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/local_file.dart';

/// O que outro app compartilhou com o Organize (ACTION_SEND / SEND_MULTIPLE).
class SharedContent {
  const SharedContent({this.text, this.subject, this.files = const []});

  final String? text;
  final String? subject;
  final List<LocalFile> files;

  bool get hasText => (text ?? '').trim().isNotEmpty;
  bool get isEmpty => !hasText && files.isEmpty;

  factory SharedContent.fromMap(Map<dynamic, dynamic> m) => SharedContent(
        text: m['text'] as String?,
        subject: m['subject'] as String?,
        files: [
          for (final f in (m['files'] as List?) ?? const [])
            if (f is Map && f['path'] is String)
              LocalFile(
                name: (f['name'] as String?) ?? (f['path'] as String).split('/').last,
                path: f['path'] as String,
                size: (f['size'] as num?)?.toInt(),
                mimeType: f['mimeType'] as String?,
              ),
        ],
      );
}

abstract interface class ShareIntentService {
  /// Conteúdo que abriu o app (app fechado); lido uma única vez.
  Future<SharedContent?> initial();

  /// Compartilhamentos que chegam com o app já aberto.
  Stream<SharedContent> get stream;
}

/// Padrão: nada é compartilhado (testes, Linux).
class NoopShareIntentService implements ShareIntentService {
  const NoopShareIntentService();

  @override
  Future<SharedContent?> initial() async => null;

  @override
  Stream<SharedContent> get stream => const Stream.empty();
}

/// Fala com `ShareChannel.kt` (intent-filters de SEND na MainActivity).
class MethodChannelShareIntentService implements ShareIntentService {
  MethodChannelShareIntentService() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onShare' && call.arguments is Map) {
        final c = SharedContent.fromMap(call.arguments as Map);
        if (!c.isEmpty) _controller.add(c);
      }
    });
  }

  static const _channel = MethodChannel('dev.organizacional/share');
  final _controller = StreamController<SharedContent>.broadcast();

  @override
  Future<SharedContent?> initial() async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('getInitialShare');
    if (raw == null) return null;
    final c = SharedContent.fromMap(raw);
    return c.isEmpty ? null : c;
  }

  @override
  Stream<SharedContent> get stream => _controller.stream;
}

final shareIntentServiceProvider = Provider<ShareIntentService>((ref) => const NoopShareIntentService());
