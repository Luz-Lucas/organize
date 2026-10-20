import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../domain/event_tag.dart';
import '../features/shopping/shopping_providers.dart';
import 'widget_appearance.dart';
import 'widget_sink.dart';
import 'widget_snapshot.dart';

/// Padrão sem-op (testes); `main.dart` sobrescreve com [HomeWidgetSink] no Android.
final widgetSinkProvider = Provider<WidgetSink>((ref) => const NoopWidgetSink());

/// Transparência do fundo dos widgets (%), preferência local do aparelho guardada no
/// armazenamento do `home_widget`. Escolher grava `w_bg_alpha` e atualiza os widgets.
final widgetBgTransparencyProvider =
    NotifierProvider<WidgetBgTransparencyNotifier, int>(WidgetBgTransparencyNotifier.new);

class WidgetBgTransparencyNotifier extends Notifier<int> {
  bool _touched = false;

  /// Termina quando a preferência gravada foi lida (nunca falha).
  Future<void> ready = Future.value();

  @override
  int build() {
    ready = _load();
    return 0;
  }

  Future<void> _load() async {
    try {
      final raw = await ref.read(widgetSinkProvider).read(widgetBgPctKey);
      final pct = int.tryParse(raw ?? '');
      if (pct != null && widgetBgTransparencyOptions.contains(pct) && !_touched && ref.mounted) {
        state = pct;
      }
    } catch (_) {
      // Sem leitura: fica no padrão (0 %).
    }
  }

  Future<void> set(int pct) async {
    _touched = true;
    state = pct;
    final sink = ref.read(widgetSinkProvider);
    try {
      await sink.save({widgetBgPctKey: '$pct', widgetBgAlphaKey: widgetBgAlphaFor(pct).toString()});
      await sink.refresh();
    } catch (_) {
      // Widgets são secundários: a escolha vale na tela mesmo se a gravação falhar.
    }
  }
}

const widgetSyncDebounce = Duration(seconds: 2);

/// Com o app aberto, grava o resumo dos widgets sempre que eventos, tarefas
/// ou ajustes mudam (debounce de 2 s).
final widgetSyncProvider = Provider<void>((ref) {
  final sink = ref.watch(widgetSinkProvider);
  final clock = ref.watch(clockProvider);
  // Janela fixada no dia da primeira leitura (mês anterior em diante, cobre também a de 14 dias);
  // o filtro final usa o `now` de cada flush.
  final from = calendarWindowStart(clock());
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
    // Espera a leitura da preferência para não gravar 0 % por cima de uma escolha anterior.
    await ref.read(widgetBgTransparencyProvider.notifier).ready;
    if (disposed) return;
    final bgPct = ref.read(widgetBgTransparencyProvider);
    try {
      await sink.save(buildWidgetSnapshot(
        now: now,
        events: events,
        tasks: tasks,
        themeId: themeId,
        bgTransparencyPct: bgPct,
        tags: ref.read(eventTagsProvider).value ?? const <EventTag>[],
        calendarEvents: events,
        // Sem compras carregadas (ou sem repositório) as chaves de mercado ficam como estavam.
        shoppingLists: ref.read(shoppingListsProvider).value,
        shoppingItems: ref.read(shoppingItemsProvider).value,
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
  ref.listen(eventTagsProvider, (_, _) => schedule(), fireImmediately: true);
  ref.listen(settingsProvider, (_, _) => schedule(), fireImmediately: true);
  ref.listen(shoppingListsProvider, (_, _) => schedule(), fireImmediately: true);
  ref.listen(shoppingItemsProvider, (_, _) => schedule(), fireImmediately: true);
});
