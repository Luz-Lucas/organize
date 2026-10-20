import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/widgets/widget_sink.dart';

void main() {
  test('widgetProviderNames lista os 6 widgets, Agenda e Tarefas entre eles', () {
    expect(widgetProviderNames, hasLength(6));
    expect(widgetProviderNames, contains('dev.organizacional.organizacional.widgets.AgendaTarefasWidgetProvider'));
    expect(widgetProviderNames, contains('dev.organizacional.organizacional.widgets.CalendarioWidgetProvider'));
    expect(widgetProviderNames, contains('dev.organizacional.organizacional.widgets.MercadoWidgetProvider'));
    expect(widgetProviderNames.toSet(), hasLength(6));
  });
}
