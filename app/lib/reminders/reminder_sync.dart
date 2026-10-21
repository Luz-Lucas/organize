import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import 'reminder_scheduler.dart';

/// Padrão sem-op (testes e fora do Android); `main.dart` sobrescreve com o plugin no Android.
final reminderSinkProvider = Provider<ReminderSink>((ref) => const NoopReminderSink());

const reminderSyncDebounce = Duration(seconds: 2);

/// Com o app aberto, reagenda os lembretes do celular quando tarefas, eventos ou ajustes mudam
/// (debounce de 2 s) e ao voltar para o app (a janela de 3 dias anda sozinha). Pede a permissão de
/// notificação ao iniciar com a chave ligada e sempre que ela é ligada.
final reminderSyncProvider = Provider<void>((ref) {
  final sink = ref.watch(reminderSinkProvider);
  final clock = ref.watch(clockProvider);
  // Janela fixada no dia da primeira leitura (como no widget_sync); o filtro de cada reagenda usa o `now` dela.
  final first = clock();
  final from = DateTime(first.year, first.month, first.day);
  Timer? timer;
  var disposed = false;
  var asked = false;
  var askAgain = false;
  ref.onDispose(() {
    disposed = true;
    timer?.cancel();
  });

  Future<void> flush() async {
    if (disposed) return;
    final events = ref.read(eventsFromProvider(from)).value;
    final tasks = ref.read(tasksProvider).value;
    final settings = ref.read(settingsProvider).value;
    if (events == null || tasks == null || settings == null) return;
    try {
      if (settings.remindersPhone && (!asked || askAgain)) {
        final force = askAgain;
        asked = true;
        askAgain = false;
        await sink.requestPermission(force: force);
      }
      if (disposed) return;
      await rescheduleReminders(sink: sink, tasks: tasks, events: events, settings: settings, now: clock());
    } catch (_) {
      // Lembretes são secundários: falha do plugin não deve afetar o app.
    }
  }

  void schedule() {
    timer?.cancel();
    timer = Timer(reminderSyncDebounce, flush);
  }

  final observer = _ResumeObserver(schedule);
  WidgetsBinding.instance.addObserver(observer);
  ref.onDispose(() => WidgetsBinding.instance.removeObserver(observer));

  ref.listen(eventsFromProvider(from), (_, _) => schedule(), fireImmediately: true);
  ref.listen(tasksProvider, (_, _) => schedule(), fireImmediately: true);
  ref.listen(settingsProvider, (prev, next) {
    if (prev?.value?.remindersPhone == false && next.value?.remindersPhone == true) askAgain = true;
    schedule();
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
