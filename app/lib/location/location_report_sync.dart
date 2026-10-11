import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../data/location_repository.dart';
import 'location_service.dart';
import 'report_policy.dart';

/// Diz se há sessão ativa. `main.dart` sobrescreve com o cliente do Supabase;
/// o padrão (testes) é "logado".
final locationSignedInProvider = Provider<bool Function()>((ref) => () => true);

/// Com o app aberto e logado, reporta a posição do celular quando há casa
/// definida, "só em casa" está ligado e a permissão é ao menos "enquanto em
/// uso": ao abrir, ao retomar o app e quando a casa/chave mudam. No máximo uma
/// vez a cada [foregroundReportMinInterval]; falhas são ignoradas em silêncio.
final locationReportSyncProvider = Provider<void>((ref) {
  var disposed = false;
  var busy = false;
  DateTime? lastAttempt;

  HomeReportConfig? currentConfig() {
    final s = ref.read(settingsProvider).value;
    return s == null ? null : HomeReportConfig.fromSettings(s);
  }

  Future<void> maybeReport() async {
    if (disposed || busy) return;
    busy = true;
    try {
      final config = currentConfig();
      if (!shouldReportConfig(config)) return;
      if (!ref.read(locationSignedInProvider)()) return;
      final clock = ref.read(clockProvider);
      final now = clock();
      final last = lastAttempt;
      if (last != null && now.difference(last) < foregroundReportMinInterval) return;

      final service = ref.read(locationServiceProvider);
      final level = await service.permission();
      if (disposed || !shouldReportInForeground(config, level)) return;

      lastAttempt = now; // conta mesmo se o GPS falhar: não martela o aparelho
      final fix = await service.currentFix();
      if (disposed || fix == null) return;
      await ref.read(locationRepositoryProvider).report(fix, clock());
    } catch (_) {
      // Localização é secundária: nenhuma falha pode afetar o app.
    } finally {
      busy = false;
    }
  }

  final observer = _ResumeObserver(() => unawaited(maybeReport()));
  WidgetsBinding.instance.addObserver(observer);
  ref.onDispose(() {
    disposed = true;
    WidgetsBinding.instance.removeObserver(observer);
  });

  ref.listen(settingsProvider, (prev, next) {
    final before = prev?.value == null ? null : HomeReportConfig.fromSettings(prev!.value!);
    final after = next.value == null ? null : HomeReportConfig.fromSettings(next.value!);
    // Dispara na primeira leitura dos ajustes e quando casa/chave mudam.
    if (before != after) unawaited(maybeReport());
  }, fireImmediately: true);
});

class _ResumeObserver with WidgetsBindingObserver {
  _ResumeObserver(this.onResume);

  final VoidCallback onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }
}
