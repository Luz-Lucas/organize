import 'package:home_widget/home_widget.dart';

/// Destino do resumo dos widgets (HomeWidget no Android; sem-op nos testes).
abstract interface class WidgetSink {
  Future<void> save(Map<String, String> data);
  Future<void> refresh();
}

const _pkg = 'dev.organizacional.organizacional.widgets';
const widgetProviderNames = [
  '$_pkg.HojeWidgetProvider',
  '$_pkg.TarefasWidgetProvider',
  '$_pkg.ProvaWidgetProvider',
  '$_pkg.AgendaTarefasWidgetProvider',
];

class HomeWidgetSink implements WidgetSink {
  const HomeWidgetSink();

  @override
  Future<void> save(Map<String, String> data) async {
    for (final e in data.entries) {
      await HomeWidget.saveWidgetData<String>(e.key, e.value);
    }
  }

  @override
  Future<void> refresh() async {
    for (final name in widgetProviderNames) {
      await HomeWidget.updateWidget(qualifiedAndroidName: name);
    }
  }
}

class NoopWidgetSink implements WidgetSink {
  const NoopWidgetSink();

  @override
  Future<void> save(Map<String, String> data) async {}

  @override
  Future<void> refresh() async {}
}
