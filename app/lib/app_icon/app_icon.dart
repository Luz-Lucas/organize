import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';

/// Troca o ícone do app para acompanhar o tema (só Android).
abstract class AppIconService {
  /// Id do tema cujo ícone está ativo, ou null se desconhecido.
  Future<String?> current();

  /// Ativa o ícone do tema [themeId].
  Future<void> set(String themeId);
}

/// Padrão: não faz nada (testes e plataformas sem suporte).
class NoopAppIconService implements AppIconService {
  const NoopAppIconService();

  @override
  Future<String?> current() async => null;

  @override
  Future<void> set(String themeId) async {}
}

/// Fala com `AppIconChannel.kt` (activity-alias por tema).
class MethodChannelAppIconService implements AppIconService {
  const MethodChannelAppIconService();

  static const _channel = MethodChannel('dev.organizacional/app_icon');

  @override
  Future<String?> current() => _channel.invokeMethod<String>('current');

  @override
  Future<void> set(String themeId) => _channel.invokeMethod<void>('set', {'theme': themeId});
}

/// Padrão sem-op; `main.dart` sobrescreve com [MethodChannelAppIconService] no Android.
final appIconServiceProvider = Provider<AppIconService>((ref) => const NoopAppIconService());

/// Mantém o ícone do app igual ao tema escolhido: ao iniciar e a cada troca de
/// tema. Erros são ignorados — o ícone é secundário e nunca deve quebrar o app.
final appIconSyncProvider = Provider<void>((ref) {
  final service = ref.watch(appIconServiceProvider);
  String? lastTheme;
  var disposed = false;
  var chain = Future<void>.value();
  ref.onDispose(() => disposed = true);

  Future<void> apply(String theme) async {
    if (disposed) return;
    try {
      if (await service.current() != theme) await service.set(theme);
    } catch (_) {
      // Ignorado de propósito.
    }
  }

  ref.listen(settingsProvider, (_, next) {
    final theme = next.value?.theme;
    if (theme == null || theme == lastTheme) return;
    lastTheme = theme;
    // Serializa para que trocas rápidas de tema não se atropelem.
    chain = chain.then((_) => apply(theme));
  }, fireImmediately: true);
});
