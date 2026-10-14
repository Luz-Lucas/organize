import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/share_intent_service.dart';
import 'share_sheet.dart';

/// Fica acima do app e abre a folha "Salvar no Organizacional" quando outro app
/// compartilha algo (app fechado ou aberto).
class ShareIntentListener extends ConsumerStatefulWidget {
  const ShareIntentListener({super.key, required this.router, required this.isSignedIn, required this.child});

  final GoRouter router;
  final bool Function() isSignedIn;
  final Widget child;

  @override
  ConsumerState<ShareIntentListener> createState() => _ShareIntentListenerState();
}

class _ShareIntentListenerState extends ConsumerState<ShareIntentListener> {
  StreamSubscription<SharedContent>? _sub;
  bool _showing = false;
  final _queue = <SharedContent>[];

  @override
  void initState() {
    super.initState();
    final service = ref.read(shareIntentServiceProvider);
    _sub = service.stream.listen(_enqueue);
    service.initial().then((c) {
      if (c != null) _enqueue(c);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _enqueue(SharedContent content) {
    _queue.add(content);
    _drain();
  }

  Future<void> _drain() async {
    if (_showing) return;
    _showing = true;
    try {
      while (_queue.isNotEmpty && mounted) {
        final content = _queue.removeAt(0);
        final ctx = await _navigatorContext();
        if (ctx == null || !ctx.mounted) continue;
        await showShareSheet(ctx, content, signedIn: widget.isSignedIn());
      }
    } finally {
      _showing = false;
    }
  }

  /// Espera o Navigator do roteador existir (app recém-aberto).
  Future<BuildContext?> _navigatorContext() async {
    for (var i = 0; i < 50; i++) {
      final ctx = widget.router.routerDelegate.navigatorKey.currentContext;
      if (ctx != null) return ctx;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
