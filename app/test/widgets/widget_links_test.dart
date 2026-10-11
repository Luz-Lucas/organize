import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/widgets/widget_links.dart';

void main() {
  test('rotas conhecidas', () {
    expect(routeForWidgetUri(Uri.parse('organizacional://agenda')), '/agenda');
    expect(routeForWidgetUri(Uri.parse('organizacional://tarefas')), '/tarefas');
  });

  test('outros links viram null', () {
    expect(routeForWidgetUri(Uri.parse('organizacional://outra')), isNull);
    expect(routeForWidgetUri(Uri.parse('https://agenda')), isNull);
    expect(routeForWidgetUri(Uri.parse('https://evil.com/agenda')), isNull);
  });
}
