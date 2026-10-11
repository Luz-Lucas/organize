import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import 'widget_sink.dart';
import 'widget_snapshot.dart';

/// Padrão sem-op (testes); `main.dart` sobrescreve com [HomeWidgetSink] no Android.
final widgetSinkProvider = Provider<WidgetSink>((ref) => const NoopWidgetSink());

const widgetSyncDebounce = Duration(seconds: 2);

/// Com o app aberto, grava o resumo dos widgets sempre que eventos, tarefas
/// ou ajustes mudam (debounce de 2 s).
final widgetSyncProvider = Provider<void>((ref) {
  final sink = ref.watch(widgetSinkProvider);
  final clock = ref.watch(clockProvider);
  // Janela fixada no dia da primeira leitura; o filtro final usa o `now` de cada flush.
  final from = widgetWindowStart(clock());
  Timer? timer;
  var disposed = false;
  ref.onDispose(() {
    disposed = true;
    timer?.cancel();
  });

  Future<void> flush() async {
    if (disposed) return;
    final now = clock();
    final events = ref.read(eventsFromProvider(from)).value;
    final tasks = ref.read(tasksProvider).value;
    if (events == null || tasks == null) return;
    final themeId = ref.read(settingsProvider).value?.theme ?? 'violeta';
    try {
      await sink.save(buildWidgetSnapshot(
        now: now,
        events: events,
        tasks: tasks,
        themeId: themeId,
      ));
      await sink.refresh();
    } catch (_) {
      // Widgets são secundários: falha de gravação não deve afetar o app.
    }
  }

  void schedule() {
    timer?.cancel();
    timer = Timer(widgetSyncDebounce, flush);
  }

  ref.listen(eventsFromProvider(from), (_, _) => schedule(), fireImmediately: true);
  ref.listen(tasksProvider, (_, _) => schedule(), fireImmediately: true);
  ref.listen(settingsProvider, (_, _) => schedule(), fireImmediately: true);
});
