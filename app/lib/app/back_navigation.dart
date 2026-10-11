import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Fecha o app. Injetável para os testes; o padrão é `SystemNavigator.pop`.
final exitAppProvider = Provider<void Function()>((ref) => () {
      SystemNavigator.pop();
    });

/// Janela para o segundo "voltar" que realmente sai do app.
const exitConfirmWindow = Duration(seconds: 2);

extension BackNavigation on BuildContext {
  /// Volta para a página anterior; se não há pilha (ex.: abriu por link direto),
  /// vai para [fallback] em vez de falhar.
  void popOrGo(String fallback) {
    if (canPop()) {
      pop();
    } else {
      go(fallback);
    }
  }
}

/// Política do botão "voltar" da casca do app.
///
/// Páginas internas empilhadas (`context.push`) são fechadas pelo próprio
/// Navigator antes de chegar aqui, e diálogos/gavetas também (o go_router tenta
/// primeiro os navegadores mais internos). O que sobra chega a este [PopScope]:
///  - fora do Início: vai para o Início (`/`);
///  - no Início: 1º voltar mostra um aviso, 2º dentro de [exitConfirmWindow] sai.
class BackHandler extends ConsumerStatefulWidget {
  const BackHandler({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  ConsumerState<BackHandler> createState() => _BackHandlerState();
}

class _BackHandlerState extends ConsumerState<BackHandler> {
  Timer? _timer;
  bool _armed = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _onPop(bool didPop, Object? result) {
    if (didPop) return;
    if (widget.location != '/') {
      context.go('/');
      return;
    }
    if (_armed) {
      _timer?.cancel();
      _armed = false;
      ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
      ref.read(exitAppProvider)();
      return;
    }
    _armed = true;
    _timer?.cancel();
    _timer = Timer(exitConfirmWindow, () => _armed = false);
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('Pressione voltar novamente para sair'),
        duration: exitConfirmWindow,
      ));
  }

  @override
  Widget build(BuildContext context) =>
      PopScope(canPop: false, onPopInvokedWithResult: _onPop, child: widget.child);
}
