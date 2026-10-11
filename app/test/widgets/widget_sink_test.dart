import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/widgets/widget_sink.dart';

void main() {
  test('widgetProviderNames lista os 4 widgets, Agenda e Tarefas por último', () {
    expect(widgetProviderNames, hasLength(4));
    expect(widgetProviderNames.last,
        'dev.organizacional.organizacional.widgets.AgendaTarefasWidgetProvider');
    expect(widgetProviderNames.toSet(), hasLength(4));
  });
}
