import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/features/settings/settings_screen.dart';
import 'package:organizacional/widgets/widget_sync.dart';

import '../helpers.dart';
import '../widgets/widget_appearance_test.dart' show MapSink;

void main() {
  testWidgets('Ajustes > Widgets: escolher a transparência grava no aparelho e atualiza os widgets', (tester) async {
    final sink = MapSink({'w_bg_pct': '25'});
    await pumpApp(tester, MemoryRepository(),
        location: '/ajustes', size: const Size(400, 900), overrides: [widgetSinkProvider.overrideWithValue(sink)]);

    expect(find.byType(SettingsScreen), findsOneWidget);
    // A lista é preguiçosa: primeiro o título da seção, depois as opções de transparência.
    await tester.scrollUntilVisible(find.text('Widgets'), 300, scrollable: find.byType(Scrollable).first);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('widget-bg-90')), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.text('Transparência do fundo'), findsOneWidget);
    for (final pct in [0, 25, 50, 75, 90]) {
      expect(find.byKey(ValueKey('widget-bg-$pct')), findsOneWidget, reason: '$pct%');
    }
    // A preferência gravada (25 %) aparece selecionada.
    expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('widget-bg-25'))).selected, isTrue);

    await tester.ensureVisible(find.byKey(const ValueKey('widget-bg-75')));
    await tester.tap(find.byKey(const ValueKey('widget-bg-75')));
    await tester.pumpAndSettle();

    expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('widget-bg-75'))).selected, isTrue);
    expect(sink.store['w_bg_alpha'], '64');
    expect(sink.store['w_bg_pct'], '75');
    expect(sink.refreshes, greaterThanOrEqualTo(1));
  });
}
